from __future__ import annotations

import queue
import threading
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from typing import Any, Callable

from .metrics import distribution


FINAL_OUTCOMES = ("success", "failure", "timeout", "canceled", "expired", "degraded")
SCENE_ORDER = ("highlight", "calm", "ordinary")


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _captured_key(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def build_benchmark_tasks(
    *,
    profile_id: str,
    parallel_slots: int,
    image_count: int,
    sample_count: int,
    groups: list[dict[str, Any]],
) -> list[dict[str, Any]]:
    if parallel_slots not in {1, 2, 3}:
        raise ValueError("parallel_slots must be 1, 2, or 3")
    if image_count not in {1, 2, 3}:
        raise ValueError("image_count must be 1, 2, or 3")
    if sample_count <= 0:
        raise ValueError("sample_count must be positive")
    by_scene = {
        str(group["scene"]): group
        for group in groups
        if int(group["image_count"]) == image_count
    }
    missing = [scene for scene in SCENE_ORDER if scene not in by_scene]
    if missing:
        raise ValueError(f"fixture is missing benchmark scenes: {', '.join(missing)}")

    tasks: list[dict[str, Any]] = []
    for index in range(sample_count):
        scene = SCENE_ORDER[index % len(SCENE_ORDER)]
        task = dict(by_scene[scene])
        task.update(
            {
                "task_id": (
                    f"{profile_id}-s{parallel_slots}-i{image_count}-{index + 1:04d}"
                ),
                "sample_index": index + 1,
                "output_tier": "standard",
            }
        )
        tasks.append(task)
    return tasks


@dataclass(frozen=True)
class SummaryState:
    task_id: str
    captured_at: str
    text: str


@dataclass
class TaskRecord:
    run_id: str
    sample_group: str
    task_id: str
    run_generation: int
    captured_at: str
    submitted_order: int
    style_id: str
    previous_summary: str
    submitted_us: int
    slot_id: int | None = None
    started_us: int | None = None
    completed_us: int | None = None
    validated_us: int | None = None
    completion_order: int | None = None
    outcome: str = "pending"
    error_code: str | None = None
    discard_reason: str | None = None
    summary: str = ""

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


class BenchmarkCoordinator:
    def __init__(
        self,
        *,
        parallel_slots: int,
        run_id: str,
        style_ids: tuple[str, ...],
        sample_group: str | None = None,
        event_context: dict[str, Any] | None = None,
    ) -> None:
        if parallel_slots not in {1, 2, 3}:
            raise ValueError("parallel_slots must be 1, 2, or 3")
        if not style_ids or any(not style_id for style_id in style_ids):
            raise ValueError("style_ids must contain at least one non-empty value")
        self.parallel_slots = parallel_slots
        self.run_id = run_id
        self.sample_group = sample_group or run_id
        self.event_context = dict(event_context or {})
        self.style_ids = style_ids
        self.generation = 1
        self.records: dict[str, TaskRecord] = {}
        self.completion_order: list[str] = []
        self.latest_summary: SummaryState | None = None
        self.events: list[dict[str, Any]] = []
        self._active_slots: dict[int, str] = {}
        self._submitted_count = 0
        self._lock = threading.RLock()

    @property
    def active_slots(self) -> dict[int, str]:
        with self._lock:
            return dict(self._active_slots)

    def _event(self, name: str, record: TaskRecord, at_us: int, **fields: Any) -> None:
        self.events.append(
            {
                "schema_version": 1,
                "event_name": name,
                "monotonic_us": at_us,
                "utc_timestamp": _utc_now(),
                **self.event_context,
                "run_id": self.run_id,
                "sample_group": self.sample_group,
                "run_generation": record.run_generation,
                "mode": "V",
                "task_id": record.task_id,
                "slot_id": record.slot_id,
                **fields,
            }
        )

    def submit(self, *, task_id: str, captured_at: str, submitted_us: int) -> TaskRecord:
        with self._lock:
            if task_id in self.records:
                raise ValueError(f"duplicate task_id: {task_id}")
            _captured_key(captured_at)
            self._submitted_count += 1
            record = TaskRecord(
                run_id=self.run_id,
                sample_group=self.sample_group,
                task_id=task_id,
                run_generation=self.generation,
                captured_at=captured_at,
                submitted_order=self._submitted_count,
                style_id=self.style_ids[(self._submitted_count - 1) % len(self.style_ids)],
                previous_summary=(
                    self.latest_summary.text if self.latest_summary is not None else ""
                ),
                submitted_us=submitted_us,
            )
            self.records[task_id] = record
            self._event("model_task_submitted", record, submitted_us)
            return record

    def start(self, task_id: str, *, slot_id: int, started_us: int) -> TaskRecord:
        with self._lock:
            record = self.records[task_id]
            if record.outcome != "pending":
                raise RuntimeError(f"task is not pending: {task_id}")
            if slot_id < 0 or slot_id >= self.parallel_slots:
                raise ValueError(f"slot_id outside configured parallel slots: {slot_id}")
            if slot_id in self._active_slots:
                raise RuntimeError(f"slot is already active: {slot_id}")
            record.slot_id = slot_id
            record.started_us = started_us
            record.outcome = "running"
            self._active_slots[slot_id] = task_id
            self._event("inference_started", record, started_us)
            return record

    def _complete(
        self,
        record: TaskRecord,
        *,
        outcome: str,
        completed_us: int,
        validated_us: int | None,
        error_code: str | None,
        discard_reason: str | None,
        summary: str,
    ) -> TaskRecord:
        if outcome not in FINAL_OUTCOMES:
            raise ValueError(f"unsupported benchmark outcome: {outcome}")
        if record.slot_id is not None:
            self._active_slots.pop(record.slot_id, None)
        record.completed_us = completed_us
        record.validated_us = validated_us
        record.outcome = outcome
        record.error_code = error_code
        record.discard_reason = discard_reason
        record.summary = summary
        self.completion_order.append(record.task_id)
        record.completion_order = len(self.completion_order)
        self._event(
            "model_result_completed",
            record,
            completed_us,
            outcome=outcome,
            error_code=error_code,
            discard_reason=discard_reason,
        )
        if validated_us is not None:
            self._event("result_validated", record, validated_us, outcome=outcome)
        return record

    def finish(
        self,
        task_id: str,
        *,
        outcome: str,
        completed_us: int,
        validated_us: int,
        summary: str,
        error_code: str | None = None,
    ) -> TaskRecord:
        with self._lock:
            record = self.records[task_id]
            if record.outcome in FINAL_OUTCOMES:
                return record
            if record.run_generation != self.generation:
                return self._complete(
                    record,
                    outcome="expired",
                    completed_us=completed_us,
                    validated_us=validated_us,
                    error_code=error_code,
                    discard_reason="old_generation",
                    summary="",
                )
            self._complete(
                record,
                outcome=outcome,
                completed_us=completed_us,
                validated_us=validated_us,
                error_code=error_code,
                discard_reason=None,
                summary=summary,
            )
            if outcome == "success" and summary:
                candidate_key = _captured_key(record.captured_at)
                current_key = (
                    _captured_key(self.latest_summary.captured_at)
                    if self.latest_summary is not None
                    else None
                )
                if current_key is None or candidate_key > current_key:
                    self.latest_summary = SummaryState(
                        task_id=record.task_id,
                        captured_at=record.captured_at,
                        text=summary,
                    )
            return record

    def cancel(self, task_id: str, *, completed_us: int) -> TaskRecord:
        with self._lock:
            record = self.records[task_id]
            if record.outcome in FINAL_OUTCOMES:
                return record
            return self._complete(
                record,
                outcome="canceled",
                completed_us=completed_us,
                validated_us=None,
                error_code="CLIENT_CANCELED",
                discard_reason="client_cancel",
                summary="",
            )

    def global_reset(self, *, reason: str, at_us: int) -> int:
        with self._lock:
            for record in self.records.values():
                if record.run_generation == self.generation and record.outcome in {"pending", "running"}:
                    self._complete(
                        record,
                        outcome="expired",
                        completed_us=at_us,
                        validated_us=None,
                        error_code="GLOBAL_RESET",
                        discard_reason=reason,
                        summary="",
                    )
            self._active_slots.clear()
            self.generation += 1
            return self.generation


def summarize_samples(sample_group: str, samples: list[dict[str, Any]]) -> dict[str, Any]:
    outcomes = Counter(str(sample["outcome"]) for sample in samples)
    success = [sample for sample in samples if sample["outcome"] == "success"]
    latency_us = [
        int(sample["completed_us"]) - int(sample["started_us"])
        for sample in success
    ]
    queue_us = [
        int(sample["started_us"]) - int(sample["submitted_us"])
        for sample in success
    ]
    if success:
        window_us = max(int(sample["completed_us"]) for sample in success) - min(
            int(sample["started_us"]) for sample in success
        )
        throughput = round(len(success) * 1_000_000 / window_us, 6) if window_us > 0 else 0.0
    else:
        throughput = 0.0
    return {
        "sample_group": sample_group,
        "n_total": len(samples),
        "outcomes": {
            outcome: outcomes[outcome]
            for outcome in FINAL_OUTCOMES
            if outcomes[outcome]
        },
        "latency_us": distribution(latency_us),
        "queue_us": distribution(queue_us),
        "throughput_per_second": throughput,
    }


BenchmarkWorker = Callable[[TaskRecord, dict[str, Any]], dict[str, Any]]


def _monotonic_us() -> int:
    return time.monotonic_ns() // 1_000


def execute_concurrent_tasks(
    *,
    coordinator: BenchmarkCoordinator,
    tasks: list[dict[str, Any]],
    worker: BenchmarkWorker,
    monotonic_us: Callable[[], int] = _monotonic_us,
) -> dict[str, dict[str, Any]]:
    slots: queue.Queue[int] = queue.Queue(maxsize=coordinator.parallel_slots)
    for slot_id in range(coordinator.parallel_slots):
        slots.put(slot_id)

    task_records: list[tuple[TaskRecord, dict[str, Any]]] = []
    for task in tasks:
        record = coordinator.submit(
            task_id=str(task["task_id"]),
            captured_at=str(task["captured_at"]),
            submitted_us=monotonic_us(),
        )
        task_records.append((record, task))

    results: dict[str, dict[str, Any]] = {}
    results_lock = threading.Lock()

    def execute(record: TaskRecord, task: dict[str, Any]) -> dict[str, Any]:
        slot_id = slots.get()
        try:
            if record.outcome in FINAL_OUTCOMES:
                evidence = {
                    "outcome": record.outcome,
                    "error_code": record.error_code,
                    "detail": record.discard_reason,
                }
                with results_lock:
                    results[record.task_id] = evidence
                return evidence
            coordinator.start(record.task_id, slot_id=slot_id, started_us=monotonic_us())
            try:
                worker_result = worker(record, task)
                outcome = str(worker_result.get("outcome", "success"))
                if outcome == "canceled":
                    coordinator.cancel(record.task_id, completed_us=monotonic_us())
                else:
                    coordinator.finish(
                        record.task_id,
                        outcome=outcome,
                        completed_us=monotonic_us(),
                        validated_us=monotonic_us(),
                        summary=str(worker_result.get("summary", "")),
                        error_code=worker_result.get("error_code"),
                    )
                evidence = dict(worker_result)
            except TimeoutError as error:
                coordinator.finish(
                    record.task_id,
                    outcome="timeout",
                    completed_us=monotonic_us(),
                    validated_us=monotonic_us(),
                    summary="",
                    error_code="REQUEST_TIMEOUT",
                )
                evidence = {
                    "outcome": "timeout",
                    "error_code": "REQUEST_TIMEOUT",
                    "detail": str(error),
                }
            except Exception as error:
                coordinator.finish(
                    record.task_id,
                    outcome="failure",
                    completed_us=monotonic_us(),
                    validated_us=monotonic_us(),
                    summary="",
                    error_code=type(error).__name__,
                )
                evidence = {
                    "outcome": "failure",
                    "error_code": type(error).__name__,
                    "detail": str(error),
                }
            with results_lock:
                results[record.task_id] = evidence
            return evidence
        finally:
            slots.put(slot_id)

    with ThreadPoolExecutor(max_workers=coordinator.parallel_slots) as executor:
        futures = [
            executor.submit(execute, record, task)
            for record, task in task_records
        ]
        for future in as_completed(futures):
            future.result()
    return results
