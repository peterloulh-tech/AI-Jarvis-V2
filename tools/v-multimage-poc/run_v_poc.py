#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import platform
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
import uuid
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from v_poc.contract import build_payload
from v_poc.benchmark import (
    BenchmarkCoordinator,
    build_benchmark_tasks,
    execute_concurrent_tasks,
    summarize_samples,
)
from v_poc.fixture import build_fixtures
from v_poc.hardware import NvidiaSampler
from v_poc.profiles import load_profiles, plan_profile
from v_poc.report import summarize_run, write_benchmark_artifacts, write_blocked_evidence
from v_poc.runner import (
    ArtifactError,
    CancellableHttpTransport,
    RunLock,
    UrllibTransport,
    build_server_command,
    execute_case,
    execute_benchmark_case,
    file_sha256,
    inspect_server_log,
    verify_artifact,
    verify_artifact_identity,
)


ROOT = Path(__file__).resolve().parent
PROFILE_FILE = ROOT / "profiles.json"


def _write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def _platform_name() -> str:
    return f"{platform.system()}-{platform.machine()}"


def _profile(args: argparse.Namespace) -> dict[str, Any]:
    return load_profiles(PROFILE_FILE)[args.profile]


def prepare(args: argparse.Namespace) -> int:
    profile = _profile(args)
    fixture_dir = args.output / "fixture"
    build_fixtures(fixture_dir)
    plan = plan_profile(profile)
    plan["fixture_manifest"] = str((fixture_dir / "fixture-manifest.json").resolve())
    _write_json(args.output / profile["id"] / "run-plan.json", plan)
    print(json.dumps({"status": "READY", "plan": plan}, ensure_ascii=False))
    return 0


def _verify_inputs(
    args: argparse.Namespace, profile: dict[str, Any], *, full_sha256: bool = False
) -> list[dict[str, Any]]:
    if not args.server.is_file():
        raise ArtifactError(f"runtime missing: {args.server}")
    if args.server.name not in {"llama-server", "llama-server.exe"}:
        raise ArtifactError(
            f"runtime filename mismatch: {args.server}; expected=llama-server[.exe]"
        )
    runtime_size = args.server.stat().st_size
    if runtime_size <= 0:
        raise ArtifactError(f"runtime size mismatch: {args.server}; expected=>0; actual={runtime_size}")
    runtime_item = {
        "role": "runtime",
        "path": str(args.server.resolve()),
        "size_bytes": runtime_size,
        "locked_release": profile["runtime"]["release"],
        "locked_revision": profile["runtime"]["revision"],
        "verification_mode": "full_sha256" if full_sha256 else "fast_identity",
    }
    if full_sha256:
        runtime_item["sha256"] = file_sha256(args.server)
    verified = [
        runtime_item
    ]
    for artifact in profile["artifacts"]:
        path = args.models_dir / artifact["name"]
        if full_sha256:
            item = verify_artifact(path, artifact["sha256"])
            if item["size_bytes"] != artifact["size_bytes"]:
                raise ArtifactError(
                    f"artifact size mismatch: {path}; expected={artifact['size_bytes']}; "
                    f"actual={item['size_bytes']}"
                )
        else:
            item = verify_artifact_identity(
                path,
                expected_name=artifact["name"],
                expected_size_bytes=artifact["size_bytes"],
            )
            item["locked_sha256"] = artifact["sha256"]
        item["role"] = artifact["role"]
        verified.append(item)
    return verified


def _artifact_failure_class(error: ArtifactError) -> str:
    return (
        "RUNTIME_ARTIFACT_UNAVAILABLE"
        if str(error).startswith("runtime ")
        else "MODEL_ARTIFACT_UNAVAILABLE"
    )


def check(args: argparse.Namespace) -> int:
    profile = _profile(args)
    evidence_path = args.output / profile["id"] / "blocked.json"
    try:
        verified = _verify_inputs(args, profile)
    except ArtifactError as error:
        failure_class = _artifact_failure_class(error)
        evidence = write_blocked_evidence(
            evidence_path,
            profile_id=profile["id"],
            failure_class=failure_class,
            detail=str(error),
            platform_name=_platform_name(),
        )
        print(json.dumps(evidence, ensure_ascii=False))
        return 2
    result = {
        "conclusion": "READY_TO_RUN",
        "profile_id": profile["id"],
        "platform": _platform_name(),
        "artifacts": verified,
        "windows_nvidia": "UNCONFIRMED" if platform.system() != "Windows" else "PENDING_RUN",
    }
    _write_json(args.output / profile["id"] / "artifact-check.json", result)
    print(json.dumps(result, ensure_ascii=False))
    return 0


def admit(args: argparse.Namespace) -> int:
    profile = _profile(args)
    evidence_path = args.output / profile["id"] / "blocked.json"
    try:
        verified = _verify_inputs(args, profile, full_sha256=True)
    except ArtifactError as error:
        evidence = write_blocked_evidence(
            evidence_path,
            profile_id=profile["id"],
            failure_class=_artifact_failure_class(error),
            detail=str(error),
            platform_name=_platform_name(),
        )
        print(json.dumps(evidence, ensure_ascii=False))
        return 2
    result = {
        "conclusion": "ADMITTED",
        "purpose": args.purpose,
        "profile_id": profile["id"],
        "platform": _platform_name(),
        "artifacts": verified,
    }
    _write_json(args.output / profile["id"] / "artifact-admission.json", result)
    print(json.dumps(result, ensure_ascii=False))
    return 0


def _wait_ready(endpoint: str, process: subprocess.Popen[bytes], timeout_s: float) -> float:
    started = time.monotonic()
    health_url = endpoint.rstrip("/") + "/health"
    while time.monotonic() - started < timeout_s:
        if process.poll() is not None:
            raise RuntimeError(f"llama-server exited during load with code {process.returncode}")
        try:
            with urllib.request.urlopen(health_url, timeout=2) as response:
                if response.status == 200:
                    return round((time.monotonic() - started) * 1000, 3)
        except (OSError, urllib.error.URLError):
            time.sleep(0.25)
    raise TimeoutError(f"llama-server was not ready within {timeout_s}s")


def _data_url(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def _classify_run_failure(error: Exception, log_path: Path) -> tuple[str, str]:
    detail = f"{type(error).__name__}: {error}"
    try:
        log_tail = log_path.read_text(encoding="utf-8", errors="replace")[-16384:]
    except OSError:
        log_tail = ""
    marker = "unknown model architecture"
    if marker in log_tail:
        line = next((line.strip() for line in log_tail.splitlines() if marker in line), marker)
        return "LOCKED_MODEL_RUNTIME_CONFLICT", f"{detail}; server: {line}"
    return "SERVER_OR_INFERENCE_FAILURE", detail


def _benchmark_run_id(value: str | None) -> str:
    run_id = value or str(uuid.uuid4())
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}", run_id):
        raise ValueError("run-id must be a safe 1-128 character identifier")
    return run_id


def _fault_result(
    *,
    fault: str,
    expected_samples: int,
    outcomes: dict[str, int],
    evidence: dict[str, Any],
    cleanup: dict[str, Any],
    model_loads: int,
    observed_slots: int | None,
    expected_slots: int,
) -> str:
    if fault == "none":
        return "NOT_APPLICABLE"
    common_pass = (
        evidence.get("injected") is True
        and cleanup.get("remaining_launched_processes") == 0
        and model_loads == 1
        and observed_slots == expected_slots
    )
    if fault == "cancel":
        behavior_pass = (
            evidence.get("cancel_result") is True
            and evidence.get("generation_after") == evidence.get("generation_before")
            and outcomes.get("canceled") == 1
            and outcomes.get("success") == expected_samples - 1
            and sum(outcomes.values()) == expected_samples
        )
    else:
        behavior_pass = (
            evidence.get("generation_after") == evidence.get("generation_before", 1) + 1
            and outcomes == {"expired": expected_samples}
        )
    return "PASS_FROZEN" if common_pass and behavior_pass else "FAIL_FROZEN"


def run(args: argparse.Namespace) -> int:
    profile = _profile(args)
    output = args.output / profile["id"]
    output.mkdir(parents=True, exist_ok=True)
    fixture_dir = args.output / "fixture"
    manifest = build_fixtures(fixture_dir)
    try:
        verified = _verify_inputs(args, profile)
    except ArtifactError as error:
        failure_class = _artifact_failure_class(error)
        write_blocked_evidence(
            output / "blocked.json",
            profile_id=profile["id"],
            failure_class=failure_class,
            detail=str(error),
            platform_name=_platform_name(),
        )
        print(str(error), file=sys.stderr)
        return 2

    model = next(Path(item["path"]) for item in verified if item["role"] == "model")
    mmproj = next(Path(item["path"]) for item in verified if item["role"] == "mmproj")
    command = build_server_command(
        server=args.server, model=model, mmproj=mmproj, host="127.0.0.1", port=args.port
    )
    endpoint = f"http://127.0.0.1:{args.port}"
    log_path = output / "llama-server.log"
    started_at = datetime.now(timezone.utc).isoformat()
    results: list[dict[str, Any]] = []
    process: subprocess.Popen[bytes] | None = None
    sampler = NvidiaSampler(output / "gpu-samples.jsonl")
    stop_sampling = threading.Event()
    sampling_thread: threading.Thread | None = None

    def sample_gpu() -> None:
        while not stop_sampling.is_set():
            try:
                sampler.sample_once()
            except (FileNotFoundError, RuntimeError, subprocess.SubprocessError, ValueError):
                return
            stop_sampling.wait(1.0)

    with RunLock(args.output / ".active-v-poc.lock", profile_id=profile["id"]):
        with log_path.open("wb") as log:
            try:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                sampling_thread = threading.Thread(target=sample_gpu, daemon=True)
                sampling_thread.start()
                load_ms = _wait_ready(endpoint, process, args.load_timeout)
                for group in manifest["groups"]:
                    captured_at = datetime.now(timezone.utc).isoformat()
                    payload = build_payload(
                        image_data_urls=[
                            _data_url(fixture_dir / image["path"]) for image in group["images"]
                        ],
                        task_id=group["case_id"],
                        captured_at=captured_at,
                        run_generation=1,
                        style_id="friendly-witty-v1",
                        previous_summary="",
                        output_mode=group["output_mode"],
                    )
                    case = execute_case(
                        transport=UrllibTransport(),
                        endpoint=endpoint,
                        payload=payload,
                        gold=group["gold"],
                        timeout_s=args.request_timeout,
                    )
                    case.update(
                        {
                            "case_id": group["case_id"],
                            "scene": group["scene"],
                            "image_count": group["image_count"],
                            "output_mode": group["output_mode"],
                            "image_sha256": [image["sha256"] for image in group["images"]],
                            "captured_at": captured_at,
                        }
                    )
                    results.append(case)
                    _write_json(output / "cases" / f"{group['case_id']}.json", case)
            except Exception as error:
                failure_class, detail = _classify_run_failure(error, log_path)
                write_blocked_evidence(
                    output / "blocked.json",
                    profile_id=profile["id"],
                    failure_class=failure_class,
                    detail=detail,
                    platform_name=_platform_name(),
                )
                raise
            finally:
                stop_sampling.set()
                if sampling_thread is not None:
                    sampling_thread.join(timeout=3)
                if process is not None and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(timeout=10)
                    except subprocess.TimeoutExpired:
                        process.kill()
                        process.wait(timeout=10)

    evidence = {
        "schema_version": 1,
        "profile_id": profile["id"],
        "started_at": started_at,
        "completed_at": datetime.now(timezone.utc).isoformat(),
        "platform": _platform_name(),
        "runtime": profile["runtime"],
        "artifacts": verified,
        "command": command,
        "server_instances": 1,
        "weight_instances": 1,
        "load_ms": load_ms,
        "fixture_manifest_sha256": file_sha256(fixture_dir / "fixture-manifest.json"),
        "results": results,
        "summary": summarize_run(profile["id"], results),
        "gpu": sampler.summary(),
        "windows_nvidia": (
            "RECORDED" if platform.system() == "Windows" and sampler.samples else "UNCONFIRMED"
        ),
        "vram_8gb": (
            "RECORDED" if sampler.summary().get("vram_class") == "8GB" else "UNCONFIRMED"
        ),
        "vram_12gb_plus": (
            "RECORDED" if sampler.summary().get("vram_class") == "12GB+" else "UNCONFIRMED"
        ),
    }
    _write_json(output / "evidence.json", evidence)
    print(json.dumps(evidence["summary"], ensure_ascii=False))
    return 0


def benchmark(args: argparse.Namespace) -> int:
    if args.samples <= 0:
        raise ValueError("samples must be positive")
    if args.warmup < 0:
        raise ValueError("warmup must not be negative")

    style_ids = tuple(value.strip() for value in args.styles.split(",") if value.strip())
    if not style_ids:
        raise ValueError("styles must contain at least one style id")

    profile = _profile(args)
    run_id = _benchmark_run_id(args.run_id)
    output = args.output / profile["id"] / "benchmark" / run_id
    if output.exists() and (not output.is_dir() or any(output.iterdir())):
        raise ValueError(f"benchmark run output directory is not empty: {output}")
    output.mkdir(parents=True, exist_ok=True)
    try:
        verified = _verify_inputs(args, profile)
    except ArtifactError as error:
        evidence = write_blocked_evidence(
            output / "blocked.json",
            profile_id=profile["id"],
            failure_class=_artifact_failure_class(error),
            detail=str(error),
            platform_name=_platform_name(),
        )
        print(json.dumps(evidence, ensure_ascii=False))
        return 2
    fixture_dir = args.output / "fixture"
    manifest = build_fixtures(fixture_dir)
    model = next(Path(item["path"]) for item in verified if item["role"] == "model")
    mmproj = next(Path(item["path"]) for item in verified if item["role"] == "mmproj")
    command = build_server_command(
        server=args.server,
        model=model,
        mmproj=mmproj,
        host="127.0.0.1",
        port=args.port,
        parallel_slots=args.slots,
    )
    endpoint = f"http://127.0.0.1:{args.port}"
    log_path = output / "llama-server.log"
    transport = CancellableHttpTransport()
    sampler = NvidiaSampler(output / "gpu-samples.jsonl")
    stop_sampling = threading.Event()
    sampling_thread: threading.Thread | None = None
    process: subprocess.Popen[bytes] | None = None
    started_at = datetime.now(timezone.utc).isoformat()
    load_ms = 0.0
    cleanup = {"remaining_launched_processes": 0, "returncode": None}
    fault_evidence: dict[str, Any] = {
        "requested": args.fault,
        "injected": False,
        "generation_before": 1,
        "generation_after": 1,
    }
    fault_lock = threading.Lock()
    execution_results: dict[str, dict[str, Any]] = {}
    warmup_evidence: list[str] = []

    def sample_gpu() -> None:
        while not stop_sampling.wait(1.0):
            try:
                sampler.sample_once(phase="steady")
            except (FileNotFoundError, RuntimeError, subprocess.SubprocessError, ValueError):
                return

    try:
        with RunLock(args.output / ".active-v-poc.lock", profile_id=profile["id"]):
            with log_path.open("wb") as log:
                process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
                load_ms = _wait_ready(endpoint, process, args.load_timeout)
                try:
                    sampler.sample_once(phase="load_ready")
                except (FileNotFoundError, RuntimeError, subprocess.SubprocessError, ValueError):
                    pass
                sampling_thread = threading.Thread(target=sample_gpu, daemon=True)
                sampling_thread.start()

                selected_groups = [
                    group
                    for group in manifest["groups"]
                    if group["image_count"] == args.image_count
                ]
                for warmup_index in range(args.warmup):
                    group = selected_groups[warmup_index % len(selected_groups)]
                    captured_at = datetime.now(timezone.utc).isoformat()
                    payload = build_payload(
                        image_data_urls=[
                            _data_url(fixture_dir / image["path"])
                            for image in group["images"]
                        ],
                        task_id=f"warmup-{warmup_index + 1}",
                        captured_at=captured_at,
                        run_generation=1,
                        style_id="friendly-witty-v1",
                        previous_summary="",
                        output_mode=group["output_mode"],
                    )
                    warmup_task_id = f"warmup-{warmup_index + 1}"
                    warmup_result = execute_benchmark_case(
                        transport=transport,
                        task_id=warmup_task_id,
                        endpoint=endpoint,
                        payload=payload,
                        gold=group["gold"],
                        timeout_s=args.request_timeout,
                    )
                    warmup_result.update(
                        {
                            "task_id": warmup_task_id,
                            "captured_at": captured_at,
                            "scene": group["scene"],
                            "image_count": group["image_count"],
                            "output_tier": args.output_tier,
                            "excluded_from_metrics": True,
                            "image_sha256": [image["sha256"] for image in group["images"]],
                        }
                    )
                    warmup_ref = f"warmup/{warmup_task_id}.json"
                    _write_json(output / warmup_ref, warmup_result)
                    warmup_evidence.append(warmup_ref)

                try:
                    sampler.sample_once(phase="steady")
                except (FileNotFoundError, RuntimeError, subprocess.SubprocessError, ValueError):
                    pass

                gpu_before = sampler.summary()
                vram_class = str(gpu_before.get("vram_class", "UNCONFIRMED"))
                sample_group = (
                    f"{profile['id']}-{vram_class}-s{args.slots}-i{args.image_count}-"
                    f"{args.output_tier}"
                    + ("" if args.fault == "none" else f"-fault-{args.fault}")
                )
                config_snapshot = {
                    "profile_id": profile["id"],
                    "runtime_revision": profile["runtime"]["revision"],
                    "parallel_slots": args.slots,
                    "image_count": args.image_count,
                    "output_tier": args.output_tier,
                    "style_ids": style_ids,
                    "samples": args.samples,
                    "warmup": args.warmup,
                    "fault": args.fault,
                }
                config_snapshot_hash = hashlib.sha256(
                    json.dumps(
                        config_snapshot,
                        ensure_ascii=False,
                        sort_keys=True,
                        separators=(",", ":"),
                    ).encode("utf-8")
                ).hexdigest()
                hardware_profile_id = args.hardware_profile_id or vram_class
                event_context = {
                    "config_snapshot_hash": config_snapshot_hash,
                    "app_version": args.app_version,
                    "model_id": profile["id"],
                    "model_version": profile["source_revision"],
                    "runtime_version": profile["runtime"]["revision"],
                    "hardware_profile_id": hardware_profile_id,
                    "driver_version": str(gpu_before.get("driver_version", "UNCONFIRMED")),
                    "power_policy": args.power_policy,
                }
                coordinator = BenchmarkCoordinator(
                    parallel_slots=args.slots,
                    run_id=run_id,
                    style_ids=style_ids,
                    sample_group=sample_group,
                    event_context=event_context,
                )
                tasks = build_benchmark_tasks(
                    profile_id=profile["id"],
                    parallel_slots=args.slots,
                    image_count=args.image_count,
                    sample_count=args.samples,
                    groups=manifest["groups"],
                )
                for task in tasks:
                    task["captured_at"] = datetime.now(timezone.utc).isoformat()

                def worker(record: Any, task: dict[str, Any]) -> dict[str, Any]:
                    payload = build_payload(
                        image_data_urls=[
                            _data_url(fixture_dir / image["path"])
                            for image in task["images"]
                        ],
                        task_id=record.task_id,
                        captured_at=record.captured_at,
                        run_generation=record.run_generation,
                        style_id=record.style_id,
                        previous_summary=record.previous_summary,
                        output_mode=task["output_mode"],
                    )
                    injection_thread: threading.Thread | None = None
                    if args.fault != "none" and task["sample_index"] == 1:
                        def inject_fault() -> None:
                            deadline = time.monotonic() + min(args.request_timeout, 5)
                            while (
                                record.task_id not in transport.active_task_ids
                                and time.monotonic() < deadline
                            ):
                                time.sleep(0.005)
                            time.sleep(args.fault_delay)
                            with fault_lock:
                                fault_evidence.update(
                                    {
                                        "injected": True,
                                        "target_task_id": record.task_id,
                                        "injected_at": datetime.now(timezone.utc).isoformat(),
                                    }
                                )
                            if args.fault == "cancel":
                                cancel_result = transport.cancel(record.task_id)
                                with fault_lock:
                                    fault_evidence.update(
                                        {
                                            "cancel_result": cancel_result,
                                            "generation_after": coordinator.generation,
                                        }
                                    )
                            else:
                                if process is not None and process.poll() is None:
                                    if args.fault == "server-exit":
                                        process.kill()
                                    else:
                                        process.terminate()
                                generation = coordinator.global_reset(
                                    reason=args.fault,
                                    at_us=time.monotonic_ns() // 1_000,
                                )
                                with fault_lock:
                                    fault_evidence["generation_after"] = generation
                            try:
                                sampler.sample_once(phase="fault")
                            except (
                                FileNotFoundError,
                                RuntimeError,
                                subprocess.SubprocessError,
                                ValueError,
                            ):
                                pass

                        injection_thread = threading.Thread(target=inject_fault, daemon=True)
                        injection_thread.start()
                    try:
                        case = execute_benchmark_case(
                            transport=transport,
                            task_id=record.task_id,
                            endpoint=endpoint,
                            payload=payload,
                            gold=task["gold"],
                            timeout_s=args.request_timeout,
                        )
                    except Exception:
                        if injection_thread is not None:
                            injection_thread.join(timeout=args.fault_delay + 6)
                        if args.fault == "cancel" and fault_evidence.get("cancel_result") is True:
                            return {
                                "outcome": "canceled",
                                "error_code": "CLIENT_CANCELED",
                                "summary": "",
                            }
                        raise
                    if injection_thread is not None:
                        injection_thread.join(timeout=args.fault_delay + 6)
                    classification = case["validation"]["classification"]
                    parsed = case["validation"].get("parsed") or {}
                    case.update(
                        {
                            "task_id": record.task_id,
                            "run_generation": record.run_generation,
                            "style_id": record.style_id,
                            "previous_summary": record.previous_summary,
                            "captured_at": record.captured_at,
                            "scene": task["scene"],
                            "image_count": task["image_count"],
                            "output_tier": task["output_tier"],
                            "image_sha256": [image["sha256"] for image in task["images"]],
                        }
                    )
                    _write_json(output / "cases" / f"{record.task_id}.json", case)
                    return {
                        "outcome": "success" if classification == "VALID" else "failure",
                        "error_code": None if classification == "VALID" else classification,
                        "summary": parsed.get("summary", ""),
                        "raw_result": case,
                    }

                execution_results = execute_concurrent_tasks(
                    coordinator=coordinator,
                    tasks=tasks,
                    worker=worker,
                )
    except Exception as error:
        failure_class, detail = _classify_run_failure(error, log_path)
        write_blocked_evidence(
            output / "blocked.json",
            profile_id=profile["id"],
            failure_class=failure_class,
            detail=detail,
            platform_name=_platform_name(),
        )
        raise
    finally:
        stop_sampling.set()
        if sampling_thread is not None:
            sampling_thread.join(timeout=3)
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=10)
        if process is not None:
            cleanup = {
                "launched_pid": process.pid,
                "remaining_launched_processes": 0 if process.poll() is not None else 1,
                "returncode": process.returncode,
            }
            try:
                sampler.sample_once(phase="post_cleanup")
            except (FileNotFoundError, RuntimeError, subprocess.SubprocessError, ValueError):
                pass

    server_log_evidence = inspect_server_log(log_path)
    raw_samples = [record.to_dict() for record in coordinator.records.values()]
    summary = summarize_samples(coordinator.sample_group, raw_samples)
    gpu = sampler.summary()
    phase_samples = gpu.get("phase_samples", {})
    required_gpu_phases = {"load_ready", "steady", "post_cleanup"}
    if args.fault != "none":
        required_gpu_phases.add("fault")
    gpu_phases_complete = all(int(phase_samples.get(phase, 0)) > 0 for phase in required_gpu_phases)
    data_complete = (
        args.fault == "none"
        and platform.system() == "Windows"
        and gpu.get("status") == "RECORDED"
        and gpu.get("vram_class") in {"8GB", "12GB+"}
        and gpu_phases_complete
        and args.app_version != "UNCONFIRMED"
        and hardware_profile_id != "UNCONFIRMED"
        and args.power_policy != "UNCONFIRMED"
        and server_log_evidence["observed_model_loads"] == 1
        and server_log_evidence["observed_slot_count"] == args.slots
        and summary["n_total"] == args.samples
        and summary["outcomes"] == {"success": args.samples}
    )
    review_status = "DATA_COMPLETE_PENDING_CALIBRATION" if data_complete else "DATA_INCOMPLETE"
    fault_result = _fault_result(
        fault=args.fault,
        expected_samples=args.samples,
        outcomes=summary["outcomes"],
        evidence=fault_evidence,
        cleanup=cleanup,
        model_loads=int(server_log_evidence["observed_model_loads"]),
        observed_slots=server_log_evidence["observed_slot_count"],
        expected_slots=args.slots,
    )
    fixture_manifest_sha256 = file_sha256(fixture_dir / "fixture-manifest.json")
    throughput_window_us = 0
    successful = [sample for sample in raw_samples if sample["outcome"] == "success"]
    if successful:
        throughput_window_us = max(int(sample["completed_us"]) for sample in successful) - min(
            int(sample["started_us"]) for sample in successful
        )
    task_by_id = {str(task["task_id"]): task for task in tasks}
    completed_event_by_task = {
        str(event["task_id"]): event
        for event in coordinator.events
        if event["event_name"] == "model_result_completed"
    }
    samples: list[dict[str, Any]] = []
    for raw_sample in raw_samples:
        task_id = str(raw_sample["task_id"])
        task = task_by_id[task_id]
        completed_event = completed_event_by_task[task_id]
        case_path = output / "cases" / f"{task_id}.json"
        if not case_path.exists():
            _write_json(
                case_path,
                {
                    "schema_version": 1,
                    "task": raw_sample,
                    "execution": execution_results.get(task_id),
                    "fault_evidence": fault_evidence,
                    "scene": task["scene"],
                    "image_count": task["image_count"],
                    "output_tier": task["output_tier"],
                    "image_sha256": [image["sha256"] for image in task["images"]],
                },
            )
        started_us = raw_sample.get("started_us")
        completed_us = raw_sample.get("completed_us")
        duration_us = (
            int(completed_us) - int(started_us)
            if started_us is not None and completed_us is not None
            else ""
        )
        samples.append(
            {
                "schema_version": 1,
                "scenario_run_id": run_id,
                "scenario_id": "BENCH-007+BENCH-008",
                "sample_group": coordinator.sample_group,
                "run_id": run_id,
                "run_generation": raw_sample["run_generation"],
                "mode": "V",
                "app_version": args.app_version,
                "model_id": profile["id"],
                "model_version": profile["source_revision"],
                "quantization": profile["quantization"],
                "runtime_version": profile["runtime"]["revision"],
                "hardware_profile_id": hardware_profile_id,
                "driver_version": str(gpu.get("driver_version", "UNCONFIRMED")),
                "config_snapshot_hash": config_snapshot_hash,
                "input_asset_hash": fixture_manifest_sha256,
                "concurrency": args.slots,
                "image_count": args.image_count,
                "tier": args.output_tier,
                "budget_chars": "",
                "timeout_limit_s": args.request_timeout,
                "route": task["scene"],
                "event_name": "model_result_completed",
                "task_id": task_id,
                "event_id": "",
                "batch_id": "",
                "slot_id": raw_sample.get("slot_id"),
                "monotonic_timestamp_us": completed_us,
                "utc_timestamp": completed_event["utc_timestamp"],
                "outcome": raw_sample["outcome"],
                "error_code": raw_sample.get("error_code") or "",
                "duration_us": duration_us,
                "throughput_window_us": throughput_window_us,
                "throughput_valid_count": len(successful),
                "vram_mib": "",
                "ram_mib": "",
                "handle_count": "",
                "gpu_percent": "",
                "queue_depth": "",
                "queue_limit": args.slots,
                "content_age_ms": "",
                "evidence_ref": f"cases/{task_id}.json",
                "review_status": review_status,
            }
        )
    summary.update(
        {
            "schema_version": 1,
            "profile_id": profile["id"],
            "run_id": run_id,
            "started_at": started_at,
            "completed_at": datetime.now(timezone.utc).isoformat(),
            "platform": _platform_name(),
            "output_tier": args.output_tier,
            "image_count": args.image_count,
            "warmup_samples": args.warmup,
            "warmup_evidence": warmup_evidence,
            "fault": args.fault,
            "fault_evidence": fault_evidence,
            "fault_result": fault_result,
            "load_ms": load_ms,
            "runtime": {**profile["runtime"], "parallel_slots": args.slots},
            "config_snapshot": config_snapshot,
            "config_snapshot_hash": config_snapshot_hash,
            "environment": {
                **event_context,
                "os": platform.platform(),
                "cpu": platform.processor() or "UNCONFIRMED",
            },
            "artifacts": verified,
            "command": command,
            "fixture_manifest_sha256": fixture_manifest_sha256,
            "topology": {
                "server_instances": 1,
                "weight_instances": server_log_evidence["observed_model_loads"],
                "model_loads": server_log_evidence["observed_model_loads"],
                "observed_slot_count": server_log_evidence["observed_slot_count"],
                "parallel_slots": args.slots,
                "pid": cleanup.get("launched_pid"),
            },
            "completion_order": coordinator.completion_order,
            "latest_summary": (
                None
                if coordinator.latest_summary is None
                else {
                    "task_id": coordinator.latest_summary.task_id,
                    "captured_at": coordinator.latest_summary.captured_at,
                    "text": coordinator.latest_summary.text,
                }
            ),
            "gpu": gpu,
            "windows_nvidia": (
                "RECORDED"
                if platform.system() == "Windows" and gpu.get("status") == "RECORDED"
                else "UNCONFIRMED"
            ),
            "process_cleanup": cleanup,
            "conclusion": review_status,
        }
    )
    write_benchmark_artifacts(
        output,
        samples=samples,
        events=coordinator.events,
        summary=summary,
    )
    print(json.dumps(summary, ensure_ascii=False))
    return 0


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="AIJARVISV2-26/27 Local V test harness")
    subparsers = root.add_subparsers(dest="command", required=True)
    for name, handler in (
        ("prepare", prepare),
        ("check", check),
        ("admit", admit),
        ("run", run),
        ("benchmark", benchmark),
    ):
        command = subparsers.add_parser(name)
        command.add_argument("--profile", required=True, choices=("V-C01", "V-C02"))
        command.add_argument("--output", type=Path, required=True)
        if name in {"check", "admit", "run", "benchmark"}:
            command.add_argument("--server", type=Path, required=True)
            command.add_argument("--models-dir", type=Path, required=True)
        if name == "admit":
            command.add_argument(
                "--purpose",
                required=True,
                choices=("initial-admission", "changed-artifact", "final-package"),
            )
        if name == "run":
            command.add_argument("--port", type=int, default=8086)
            command.add_argument("--load-timeout", type=float, default=180)
            command.add_argument("--request-timeout", type=float, default=120)
        if name == "benchmark":
            command.add_argument("--slots", type=int, choices=(1, 2, 3), required=True)
            command.add_argument("--image-count", type=int, choices=(1, 2, 3), required=True)
            command.add_argument("--samples", type=int, default=20)
            command.add_argument("--warmup", type=int, default=1)
            command.add_argument("--run-id")
            command.add_argument("--output-tier", choices=("standard",), default="standard")
            command.add_argument("--styles", default="friendly-witty-v1")
            command.add_argument("--app-version", default="UNCONFIRMED")
            command.add_argument("--hardware-profile-id")
            command.add_argument("--power-policy", default="UNCONFIRMED")
            command.add_argument(
                "--fault",
                choices=("none", "cancel", "server-exit", "global-reset"),
                default="none",
            )
            command.add_argument("--fault-delay", type=float, default=0.25)
            command.add_argument("--port", type=int, default=8086)
            command.add_argument("--load-timeout", type=float, default=180)
            command.add_argument("--request-timeout", type=float, default=120)
        command.set_defaults(handler=handler)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.handler(args)
    except (ArtifactError, RuntimeError, TimeoutError, ValueError, urllib.error.URLError) as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
