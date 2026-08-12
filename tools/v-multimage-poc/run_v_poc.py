#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
import json
import platform
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from v_poc.contract import build_payload
from v_poc.fixture import build_fixtures
from v_poc.hardware import NvidiaSampler
from v_poc.profiles import load_profiles, plan_profile
from v_poc.report import summarize_run, write_blocked_evidence
from v_poc.runner import (
    ArtifactError,
    RunLock,
    UrllibTransport,
    build_server_command,
    execute_case,
    file_sha256,
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


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(description="AIJARVISV2-26 Local V multi-image PoC")
    subparsers = root.add_subparsers(dest="command", required=True)
    for name, handler in (
        ("prepare", prepare),
        ("check", check),
        ("admit", admit),
        ("run", run),
    ):
        command = subparsers.add_parser(name)
        command.add_argument("--profile", required=True, choices=("V-C01", "V-C02"))
        command.add_argument("--output", type=Path, required=True)
        if name in {"check", "admit", "run"}:
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
        command.set_defaults(handler=handler)
    return root


def main() -> int:
    args = parser().parse_args()
    try:
        return args.handler(args)
    except (ArtifactError, RuntimeError, TimeoutError, urllib.error.URLError) as error:
        print(f"{type(error).__name__}: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
