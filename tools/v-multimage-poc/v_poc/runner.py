from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.request
from pathlib import Path
from typing import Any, Protocol

from .contract import classify_response, score_result


class ArtifactError(RuntimeError):
    pass


class Transport(Protocol):
    def post_json(self, url: str, payload: dict, timeout_s: float) -> dict: ...


class UrllibTransport:
    def post_json(self, url: str, payload: dict, timeout_s: float) -> dict:
        request = urllib.request.Request(
            url,
            data=json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(request, timeout=timeout_s) as response:
            return json.loads(response.read().decode("utf-8"))


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_artifact(path: Path, expected_sha256: str) -> dict[str, Any]:
    if not path.is_file():
        raise ArtifactError(f"artifact missing: {path}")
    actual = file_sha256(path)
    if not expected_sha256 or actual.lower() != expected_sha256.lower():
        raise ArtifactError(
            f"artifact sha256 mismatch: {path}; expected={expected_sha256}; actual={actual}"
        )
    return {
        "path": str(path.resolve()),
        "sha256": actual,
        "size_bytes": path.stat().st_size,
        "verification_mode": "full_sha256",
    }


def verify_artifact_identity(
    path: Path, *, expected_name: str, expected_size_bytes: int
) -> dict[str, Any]:
    if not path.is_file():
        raise ArtifactError(f"artifact missing: {path}")
    if path.name != expected_name:
        raise ArtifactError(
            f"artifact filename mismatch: {path}; expected={expected_name}; actual={path.name}"
        )
    actual_size = path.stat().st_size
    if actual_size != expected_size_bytes:
        raise ArtifactError(
            f"artifact size mismatch: {path}; expected={expected_size_bytes}; actual={actual_size}"
        )
    return {
        "path": str(path.resolve()),
        "size_bytes": actual_size,
        "verification_mode": "fast_identity",
    }


def build_server_command(
    *, server: Path, model: Path, mmproj: Path, host: str, port: int
) -> list[str]:
    return [
        str(server),
        "--model",
        str(model),
        "--mmproj",
        str(mmproj),
        "--host",
        host,
        "--port",
        str(port),
        "--parallel",
        "1",
        "--cont-batching",
        "--ctx-size",
        "8192",
        "--n-gpu-layers",
        "99",
    ]


def _extract_content(response: dict[str, Any]) -> str:
    try:
        content = response["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError) as error:
        raise RuntimeError("llama-server response is missing choices[0].message.content") from error
    if not isinstance(content, str):
        raise RuntimeError("llama-server response content is not text")
    return content


def execute_case(
    *,
    transport: Transport,
    endpoint: str,
    payload: dict[str, Any],
    gold: dict[str, Any],
    timeout_s: float,
) -> dict[str, Any]:
    started_ns = time.monotonic_ns()
    response = transport.post_json(
        endpoint.rstrip("/") + "/v1/chat/completions", payload, timeout_s
    )
    completed_ns = time.monotonic_ns()
    raw = _extract_content(response)
    validation = classify_response(raw)
    score = None
    if validation.get("syntax_schema_valid") is True:
        score = score_result(validation["parsed"], gold)
    return {
        "model_call_count": 1,
        "repair_call_count": 0,
        "request_elapsed_ms": round((completed_ns - started_ns) / 1_000_000, 3),
        "raw_response_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "raw_response": raw,
        "validation": validation,
        "score": score,
        "server_usage": response.get("usage"),
        "finish_reason": response.get("choices", [{}])[0].get("finish_reason"),
    }


class RunLock:
    def __init__(self, path: Path, *, profile_id: str) -> None:
        self.path = path
        self.profile_id = profile_id
        self._owned = False

    def __enter__(self) -> "RunLock":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        try:
            descriptor = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
        except FileExistsError as error:
            raise RuntimeError("another V PoC run is active; only one profile may reside") from error
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            json.dump({"pid": os.getpid(), "profile_id": self.profile_id}, handle)
        self._owned = True
        return self

    def __exit__(self, exc_type: object, exc: object, traceback: object) -> None:
        if self._owned:
            self.path.unlink(missing_ok=True)
            self._owned = False
