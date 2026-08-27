from __future__ import annotations

import hashlib
import http.client
import json
import os
import re
import socket
import threading
import time
import urllib.request
from pathlib import Path
from typing import Any, Protocol
from urllib.parse import urlsplit

from .contract import classify_response, score_result


class ArtifactError(RuntimeError):
    pass


def inspect_server_log(path: Path) -> dict[str, int | None]:
    value = path.read_text(encoding="utf-8", errors="replace")
    slot_matches = re.findall(r"\bn_slots\s*=\s*(\d+)", value)
    return {
        "observed_model_loads": value.count("srv load_model: loading model"),
        "observed_slot_count": int(slot_matches[-1]) if slot_matches else None,
    }


class Transport(Protocol):
    def post_json(self, url: str, payload: dict, timeout_s: float) -> dict: ...


class CancellableTransport(Protocol):
    def post_json(
        self, task_id: str, url: str, payload: dict, timeout_s: float
    ) -> dict: ...


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


class CancellableHttpTransport:
    def __init__(self) -> None:
        self._connections: dict[str, http.client.HTTPConnection] = {}
        self._lock = threading.Lock()

    @property
    def active_task_ids(self) -> set[str]:
        with self._lock:
            return set(self._connections)

    def post_json(
        self,
        task_id: str,
        url: str,
        payload: dict[str, Any],
        timeout_s: float,
    ) -> dict[str, Any]:
        target = urlsplit(url)
        if target.scheme != "http" or target.hostname not in {"127.0.0.1", "localhost", "::1"}:
            raise ValueError("benchmark transport only permits loopback HTTP")
        connection = http.client.HTTPConnection(
            target.hostname,
            target.port or 80,
            timeout=timeout_s,
        )
        with self._lock:
            if task_id in self._connections:
                raise RuntimeError(f"task already has an active connection: {task_id}")
            self._connections[task_id] = connection
        try:
            body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            path = target.path or "/"
            if target.query:
                path += "?" + target.query
            connection.request(
                "POST",
                path,
                body=body,
                headers={"Content-Type": "application/json"},
            )
            response = connection.getresponse()
            raw = response.read()
            if response.status < 200 or response.status >= 300:
                raise RuntimeError(f"llama-server HTTP status {response.status}")
            parsed = json.loads(raw.decode("utf-8"))
            if not isinstance(parsed, dict):
                raise RuntimeError("llama-server response is not a JSON object")
            return parsed
        finally:
            with self._lock:
                self._connections.pop(task_id, None)
            connection.close()

    def cancel(self, task_id: str) -> bool:
        with self._lock:
            connection = self._connections.get(task_id)
        if connection is None:
            return False
        try:
            if connection.sock is not None:
                connection.sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
        connection.close()
        return True


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
    *,
    server: Path,
    model: Path,
    mmproj: Path,
    host: str,
    port: int,
    parallel_slots: int = 1,
) -> list[str]:
    if parallel_slots not in {1, 2, 3}:
        raise ValueError("parallel_slots must be 1, 2, or 3")
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
        str(parallel_slots),
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


def _evaluate_response(
    response: dict[str, Any], *, gold: dict[str, Any], elapsed_ms: float
) -> dict[str, Any]:
    raw = _extract_content(response)
    validation = classify_response(raw)
    score = None
    if validation.get("syntax_schema_valid") is True:
        score = score_result(validation["parsed"], gold)
    return {
        "model_call_count": 1,
        "repair_call_count": 0,
        "request_elapsed_ms": elapsed_ms,
        "raw_response_sha256": hashlib.sha256(raw.encode("utf-8")).hexdigest(),
        "raw_response": raw,
        "validation": validation,
        "score": score,
        "server_usage": response.get("usage"),
        "finish_reason": response.get("choices", [{}])[0].get("finish_reason"),
    }


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
    return _evaluate_response(
        response,
        gold=gold,
        elapsed_ms=round((completed_ns - started_ns) / 1_000_000, 3),
    )


def execute_benchmark_case(
    *,
    transport: CancellableTransport,
    task_id: str,
    endpoint: str,
    payload: dict[str, Any],
    gold: dict[str, Any],
    timeout_s: float,
) -> dict[str, Any]:
    started_ns = time.monotonic_ns()
    response = transport.post_json(
        task_id,
        endpoint.rstrip("/") + "/v1/chat/completions",
        payload,
        timeout_s,
    )
    completed_ns = time.monotonic_ns()
    return _evaluate_response(
        response,
        gold=gold,
        elapsed_ms=round((completed_ns - started_ns) / 1_000_000, 3),
    )


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
