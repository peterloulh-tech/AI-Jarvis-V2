import sys
import threading
import csv
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.benchmark import (  # noqa: E402
    BenchmarkCoordinator,
    build_benchmark_tasks,
    execute_concurrent_tasks,
    summarize_samples,
)
from v_poc.report import write_benchmark_artifacts  # noqa: E402


class BenchmarkCoordinatorTests(unittest.TestCase):
    def test_tracks_unique_tasks_slots_and_out_of_order_completion(self) -> None:
        coordinator = BenchmarkCoordinator(
            parallel_slots=2,
            run_id="run-1",
            style_ids=("friendly", "dry"),
            event_context={
                "config_snapshot_hash": "abc123",
                "app_version": "commit-1",
                "model_id": "V-C01",
                "model_version": "model-rev",
                "runtime_version": "6e62ba5",
                "hardware_profile_id": "12GB-test",
                "driver_version": "591.44",
            },
        )
        first = coordinator.submit(
            task_id="task-1", captured_at="2026-08-27T00:00:01Z", submitted_us=10
        )
        second = coordinator.submit(
            task_id="task-2", captured_at="2026-08-27T00:00:02Z", submitted_us=20
        )
        coordinator.start("task-1", slot_id=0, started_us=30)
        coordinator.start("task-2", slot_id=1, started_us=40)

        coordinator.finish(
            "task-2",
            outcome="failure",
            completed_us=60,
            validated_us=65,
            summary="",
            error_code="SCHEMA_FIELDS",
        )
        coordinator.finish(
            "task-1",
            outcome="success",
            completed_us=80,
            validated_us=90,
            summary="first summary",
        )

        self.assertEqual((first.style_id, second.style_id), ("friendly", "dry"))
        self.assertEqual(coordinator.completion_order, ["task-2", "task-1"])
        self.assertEqual(coordinator.records["task-2"].completion_order, 1)
        self.assertEqual(coordinator.records["task-1"].completion_order, 2)
        self.assertEqual(coordinator.active_slots, {})
        self.assertTrue(
            all(event["config_snapshot_hash"] == "abc123" for event in coordinator.events)
        )
        self.assertTrue(all(event["model_id"] == "V-C01" for event in coordinator.events))
        with self.assertRaisesRegex(ValueError, "duplicate task_id"):
            coordinator.submit(
                task_id="task-1",
                captured_at="2026-08-27T00:00:03Z",
                submitted_us=100,
            )

        third = coordinator.submit(
            task_id="task-3", captured_at="2026-08-27T00:00:03Z", submitted_us=110
        )
        self.assertEqual(third.style_id, "friendly")

    def test_cancel_releases_slot_and_global_reset_expires_old_generation(self) -> None:
        coordinator = BenchmarkCoordinator(
            parallel_slots=1,
            run_id="run-2",
            style_ids=("friendly",),
        )
        coordinator.submit(
            task_id="cancel-me", captured_at="2026-08-27T00:00:01Z", submitted_us=10
        )
        coordinator.start("cancel-me", slot_id=0, started_us=20)
        coordinator.cancel("cancel-me", completed_us=30)
        self.assertEqual(coordinator.records["cancel-me"].outcome, "canceled")
        self.assertEqual(coordinator.active_slots, {})

        old = coordinator.submit(
            task_id="old", captured_at="2026-08-27T00:00:02Z", submitted_us=40
        )
        coordinator.start("old", slot_id=0, started_us=50)
        new_generation = coordinator.global_reset(reason="service_exit", at_us=60)

        self.assertEqual(new_generation, 2)
        self.assertEqual(old.run_generation, 1)
        self.assertEqual(coordinator.records["old"].outcome, "expired")
        self.assertEqual(coordinator.records["old"].discard_reason, "service_exit")
        self.assertEqual(coordinator.active_slots, {})

        coordinator.finish(
            "old",
            outcome="success",
            completed_us=70,
            validated_us=80,
            summary="must not become current",
        )
        self.assertIsNone(coordinator.latest_summary)

    def test_only_newer_valid_current_generation_summary_updates_state(self) -> None:
        coordinator = BenchmarkCoordinator(
            parallel_slots=2,
            run_id="run-3",
            style_ids=("friendly",),
        )
        for task_id, captured_at, slot_id in (
            ("newer", "2026-08-27T00:00:03Z", 0),
            ("older", "2026-08-27T00:00:02Z", 1),
        ):
            coordinator.submit(task_id=task_id, captured_at=captured_at, submitted_us=10)
            coordinator.start(task_id, slot_id=slot_id, started_us=20)

        coordinator.finish(
            "newer",
            outcome="success",
            completed_us=30,
            validated_us=40,
            summary="new summary",
        )
        after_summary = coordinator.submit(
            task_id="after-summary",
            captured_at="2026-08-27T00:00:04Z",
            submitted_us=45,
        )
        self.assertEqual(after_summary.previous_summary, "new summary")
        coordinator.finish(
            "older",
            outcome="success",
            completed_us=50,
            validated_us=60,
            summary="old summary",
        )

        self.assertEqual(coordinator.latest_summary.task_id, "newer")
        self.assertEqual(coordinator.latest_summary.text, "new summary")

        coordinator.submit(
            task_id="empty", captured_at="2026-08-27T00:00:04Z", submitted_us=70
        )
        coordinator.start("empty", slot_id=0, started_us=80)
        coordinator.finish(
            "empty",
            outcome="success",
            completed_us=90,
            validated_us=100,
            summary="",
        )
        self.assertEqual(coordinator.latest_summary.task_id, "newer")


class BenchmarkMetricsTests(unittest.TestCase):
    def test_nearest_rank_uses_success_latency_and_preserves_outcome_denominator(self) -> None:
        samples = [
            {
                "task_id": "ok-1",
                "outcome": "success",
                "submitted_us": 0,
                "started_us": 100,
                "completed_us": 1100,
            },
            {
                "task_id": "ok-2",
                "outcome": "success",
                "submitted_us": 200,
                "started_us": 300,
                "completed_us": 3300,
            },
            {"task_id": "bad", "outcome": "failure", "submitted_us": 400},
            {"task_id": "late", "outcome": "timeout", "submitted_us": 500},
            {"task_id": "stop", "outcome": "canceled", "submitted_us": 600},
            {"task_id": "old", "outcome": "expired", "submitted_us": 700},
        ]

        summary = summarize_samples("V-C01-12GB+-s2-i3", samples)

        self.assertEqual(summary["n_total"], 6)
        self.assertEqual(summary["outcomes"], {
            "success": 2,
            "failure": 1,
            "timeout": 1,
            "canceled": 1,
            "expired": 1,
        })
        self.assertEqual(summary["latency_us"], {
            "n": 2,
            "min": 1000,
            "max": 3000,
            "p50": 1000,
            "p95": 3000,
        })
        self.assertEqual(summary["queue_us"], {
            "n": 2,
            "min": 100,
            "max": 100,
            "p50": 100,
            "p95": 100,
        })
        self.assertEqual(summary["throughput_per_second"], 625.0)

    def test_task_plan_fixes_image_count_and_interleaves_long_short_scenes(self) -> None:
        groups = [
            {"case_id": "calm-2", "scene": "calm", "image_count": 2},
            {"case_id": "ordinary-2", "scene": "ordinary", "image_count": 2},
            {"case_id": "highlight-2", "scene": "highlight", "image_count": 2},
            {"case_id": "highlight-3", "scene": "highlight", "image_count": 3},
        ]

        tasks = build_benchmark_tasks(
            profile_id="V-C01",
            parallel_slots=3,
            image_count=2,
            sample_count=5,
            groups=groups,
        )

        self.assertEqual(len(tasks), 5)
        self.assertEqual([task["scene"] for task in tasks], [
            "highlight", "calm", "ordinary", "highlight", "calm"
        ])
        self.assertTrue(all(task["image_count"] == 2 for task in tasks))
        self.assertEqual(len({task["task_id"] for task in tasks}), 5)
        self.assertEqual(tasks[0]["output_tier"], "standard")

        with self.assertRaisesRegex(ValueError, "sample_count must be positive"):
            build_benchmark_tasks(
                profile_id="V-C01",
                parallel_slots=1,
                image_count=1,
                sample_count=0,
                groups=groups,
            )


class ConcurrentExecutionTests(unittest.TestCase):
    def test_executes_with_real_slot_concurrency_and_records_out_of_order_results(self) -> None:
        coordinator = BenchmarkCoordinator(
            parallel_slots=2,
            run_id="run-concurrent",
            style_ids=("friendly", "dry"),
        )
        release_slow = threading.Event()
        saw_two_active = threading.Event()

        def worker(record, task):
            if task["task_id"] == "slow":
                if not release_slow.wait(timeout=2):
                    raise TimeoutError("fast task never started")
            else:
                if len(coordinator.active_slots) == 2:
                    saw_two_active.set()
                release_slow.set()
            return {
                "outcome": "success",
                "summary": task["task_id"],
                "raw_result": {"task_id": record.task_id},
            }

        results = execute_concurrent_tasks(
            coordinator=coordinator,
            tasks=[
                {"task_id": "slow", "captured_at": "2026-08-27T00:00:01Z"},
                {"task_id": "fast", "captured_at": "2026-08-27T00:00:02Z"},
            ],
            worker=worker,
        )

        self.assertTrue(saw_two_active.is_set())
        self.assertEqual(coordinator.completion_order, ["fast", "slow"])
        self.assertEqual(results["slow"]["raw_result"], {"task_id": "slow"})
        self.assertEqual(results["fast"]["raw_result"], {"task_id": "fast"})

    def test_classifies_timeout_and_failure_without_dropping_denominator(self) -> None:
        coordinator = BenchmarkCoordinator(
            parallel_slots=2,
            run_id="run-errors",
            style_ids=("friendly",),
        )

        def worker(record, task):
            if task["task_id"] == "timeout":
                raise TimeoutError("request timed out")
            raise RuntimeError("server closed")

        execute_concurrent_tasks(
            coordinator=coordinator,
            tasks=[
                {"task_id": "timeout", "captured_at": "2026-08-27T00:00:01Z"},
                {"task_id": "failure", "captured_at": "2026-08-27T00:00:02Z"},
            ],
            worker=worker,
        )

        self.assertEqual(coordinator.records["timeout"].outcome, "timeout")
        self.assertEqual(coordinator.records["timeout"].error_code, "REQUEST_TIMEOUT")
        self.assertEqual(coordinator.records["failure"].outcome, "failure")
        self.assertEqual(coordinator.records["failure"].error_code, "RuntimeError")
        self.assertEqual(len(coordinator.completion_order), 2)


class BenchmarkArtifactTests(unittest.TestCase):
    def test_writes_traceable_csv_events_and_summary_for_one_sample_group(self) -> None:
        sample = {
            "run_id": "run-1",
            "sample_group": "V-C01-12GB+-s1-i1",
            "task_id": "task-1",
            "run_generation": 1,
            "captured_at": "2026-08-27T00:00:01Z",
            "submitted_order": 1,
            "completion_order": 1,
            "style_id": "friendly",
            "slot_id": 0,
            "scenario_run_id": "run-1",
            "scenario_id": "BENCH-007+BENCH-008",
            "mode": "V",
            "event_name": "model_result_completed",
            "monotonic_timestamp_us": 30,
            "submitted_us": 10,
            "started_us": 20,
            "completed_us": 30,
            "validated_us": 40,
            "outcome": "expired",
            "error_code": "GLOBAL_RESET",
            "discard_reason": "service_exit",
            "summary": "",
        }
        event = {
            "event_name": "model_result_completed",
            "monotonic_us": 30,
            "utc_timestamp": "2026-08-27T00:00:01Z",
            "run_id": "run-1",
            "run_generation": 1,
            "mode": "V",
            "task_id": "task-1",
            "slot_id": 0,
            "outcome": "expired",
            "discard_reason": "service_exit",
        }
        summary = {"sample_group": "V-C01-12GB+-s1-i1", "n_total": 1}

        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            paths = write_benchmark_artifacts(
                output,
                samples=[sample],
                events=[event],
                summary=summary,
            )

            with paths["samples_csv"].open(newline="", encoding="utf-8") as handle:
                reader = csv.DictReader(handle)
                rows = list(reader)
            template = ROOT.parents[1] / "docs/v2/requirements/templates/performance-sample-record.csv"
            with template.open(newline="", encoding="utf-8") as handle:
                template_fields = next(csv.reader(handle))
            self.assertEqual(reader.fieldnames, template_fields)
            self.assertEqual(len(rows), 1)
            self.assertEqual(rows[0]["task_id"], "task-1")
            self.assertEqual(rows[0]["sample_group"], "V-C01-12GB+-s1-i1")
            self.assertEqual(rows[0]["outcome"], "expired")
            events = [
                json.loads(line)
                for line in paths["events_jsonl"].read_text(encoding="utf-8").splitlines()
            ]
            self.assertEqual(events, [event])
            self.assertEqual(events[0]["discard_reason"], "service_exit")
            self.assertEqual(
                json.loads(paths["summary_json"].read_text(encoding="utf-8")), summary
            )


if __name__ == "__main__":
    unittest.main()
