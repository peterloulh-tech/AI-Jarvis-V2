import hashlib
import json
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.runner import (  # noqa: E402
    ArtifactError,
    CancellableHttpTransport,
    RunLock,
    build_server_command,
    execute_benchmark_case,
    execute_case,
    inspect_server_log,
    verify_artifact,
    verify_artifact_identity,
)


class FakeTransport:
    def __init__(self, response: dict) -> None:
        self.response = response
        self.calls: list[tuple[str, dict, float]] = []

    def post_json(self, url: str, payload: dict, timeout_s: float) -> dict:
        self.calls.append((url, payload, timeout_s))
        return self.response


class FakeCancellableTransport:
    def __init__(self, response: dict) -> None:
        self.response = response
        self.calls: list[tuple[str, str, dict, float]] = []

    def post_json(self, task_id: str, url: str, payload: dict, timeout_s: float) -> dict:
        self.calls.append((task_id, url, payload, timeout_s))
        return self.response


class RunnerTests(unittest.TestCase):
    def test_rejects_missing_or_wrong_weight_before_server_start(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.gguf"
            with self.assertRaisesRegex(ArtifactError, "missing"):
                verify_artifact(path, "0" * 64)
            path.write_bytes(b"wrong")
            with self.assertRaisesRegex(ArtifactError, "sha256 mismatch"):
                verify_artifact(path, "0" * 64)

    def test_fast_identity_checks_name_and_size_without_content_hash(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "model.gguf"
            path.write_bytes(b"fixed")
            identity = verify_artifact_identity(
                path,
                expected_name="model.gguf",
                expected_size_bytes=5,
            )
            self.assertEqual(identity["verification_mode"], "fast_identity")
            self.assertEqual(identity["size_bytes"], 5)
            self.assertNotIn("sha256", identity)
            with self.assertRaisesRegex(ArtifactError, "filename mismatch"):
                verify_artifact_identity(
                    path,
                    expected_name="other.gguf",
                    expected_size_bytes=5,
                )
            with self.assertRaisesRegex(ArtifactError, "size mismatch"):
                verify_artifact_identity(
                    path,
                    expected_name="model.gguf",
                    expected_size_bytes=6,
                )

    def test_builds_official_single_server_single_weight_command(self) -> None:
        for parallel_slots in (1, 2, 3):
            with self.subTest(parallel_slots=parallel_slots):
                command = build_server_command(
                    server=Path("C:/poc/llama-server.exe"),
                    model=Path("C:/models/model.gguf"),
                    mmproj=Path("C:/models/mmproj.gguf"),
                    host="127.0.0.1",
                    port=8086,
                    parallel_slots=parallel_slots,
                )
                self.assertEqual(command.count("--parallel"), 1)
                self.assertEqual(
                    command[command.index("--parallel") + 1], str(parallel_slots)
                )
                self.assertEqual(command.count("--model"), 1)
                self.assertEqual(command.count("--mmproj"), 1)
                self.assertNotIn("-hf", command)
                self.assertNotIn("--mmproj-url", command)
                self.assertEqual(command[0], "C:/poc/llama-server.exe")

        for invalid_slots in (0, 4):
            with self.subTest(invalid_slots=invalid_slots):
                with self.assertRaisesRegex(ValueError, "parallel_slots must be 1, 2, or 3"):
                    build_server_command(
                        server=Path("C:/poc/llama-server.exe"),
                        model=Path("C:/models/model.gguf"),
                        mmproj=Path("C:/models/mmproj.gguf"),
                        host="127.0.0.1",
                        port=8086,
                        parallel_slots=invalid_slots,
                    )

    def test_execute_case_makes_exactly_one_loopback_request_and_hashes_raw_output(self) -> None:
        raw = json.dumps({
            "emit": True,
            "event": "蓝色圆点穿过中央标记",
            "level": "ordinary",
            "comments": ["稳稳推进"],
            "summary": "蓝点穿过中央标记",
        }, ensure_ascii=False)
        transport = FakeTransport({
            "id": "chatcmpl-test",
            "choices": [{"index": 0, "message": {"role": "assistant", "content": raw}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 120, "completion_tokens": 40, "total_tokens": 160},
        })
        evidence = execute_case(
            transport=transport,
            endpoint="http://127.0.0.1:8086",
            payload={"messages": []},
            gold={"expected_emit": True, "expected_level": "ordinary", "required_event_terms": ["蓝", "标记"], "forbidden_event_terms": []},
            timeout_s=30,
        )
        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0][0], "http://127.0.0.1:8086/v1/chat/completions")
        self.assertEqual(evidence["model_call_count"], 1)
        self.assertEqual(evidence["repair_call_count"], 0)
        self.assertEqual(evidence["raw_response_sha256"], hashlib.sha256(raw.encode()).hexdigest())
        self.assertEqual(evidence["validation"]["classification"], "VALID")
        self.assertEqual(evidence["score"]["level_correct"], True)

    def test_benchmark_case_keeps_task_connection_and_raw_result_in_one_call(self) -> None:
        raw = json.dumps({
            "emit": True,
            "event": "红色星形命中目标",
            "level": "highlight",
            "comments": ["命中瞬间"],
            "summary": "红星命中目标",
        }, ensure_ascii=False)
        transport = FakeCancellableTransport({
            "choices": [{"message": {"content": raw}, "finish_reason": "stop"}],
            "usage": {"prompt_tokens": 10, "completion_tokens": 20, "total_tokens": 30},
        })

        evidence = execute_benchmark_case(
            transport=transport,
            task_id="V-C01-s2-i3-0001",
            endpoint="http://127.0.0.1:8086",
            payload={"messages": []},
            gold={
                "expected_emit": True,
                "expected_level": "highlight",
                "required_event_terms": ["红", "目标"],
                "forbidden_event_terms": [],
            },
            timeout_s=30,
        )

        self.assertEqual(len(transport.calls), 1)
        self.assertEqual(transport.calls[0][0], "V-C01-s2-i3-0001")
        self.assertEqual(evidence["model_call_count"], 1)
        self.assertEqual(evidence["repair_call_count"], 0)
        self.assertEqual(evidence["raw_response"], raw)
        self.assertEqual(evidence["validation"]["classification"], "VALID")

    def test_run_lock_prevents_a_second_profile_from_residing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lock_path = Path(directory) / "active.lock"
            with RunLock(lock_path, profile_id="V-C01"):
                with self.assertRaisesRegex(RuntimeError, "another V PoC run is active"):
                    with RunLock(lock_path, profile_id="V-C02"):
                        pass
            self.assertFalse(lock_path.exists())

    def test_cancellable_transport_interrupts_the_in_flight_task_connection(self) -> None:
        request_started = threading.Event()
        release_response = threading.Event()

        class SlowHandler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:
                content_length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(content_length)
                request_started.set()
                release_response.wait(timeout=2)
                body = json.dumps({"ok": True}).encode("utf-8")
                try:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except OSError:
                    pass

            def log_message(self, format: str, *args: object) -> None:
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), SlowHandler)
        server_thread = threading.Thread(target=server.serve_forever, daemon=True)
        server_thread.start()
        transport = CancellableHttpTransport()
        errors: list[Exception] = []

        def send_request() -> None:
            try:
                transport.post_json(
                    "cancel-me",
                    f"http://127.0.0.1:{server.server_port}/v1/chat/completions",
                    {"messages": []},
                    5,
                )
            except Exception as error:
                errors.append(error)

        request_thread = threading.Thread(target=send_request)
        request_thread.start()
        self.assertTrue(request_started.wait(timeout=2))
        self.assertEqual(transport.active_task_ids, {"cancel-me"})
        self.assertTrue(transport.cancel("cancel-me"))
        release_response.set()
        request_thread.join(timeout=2)
        server.shutdown()
        server.server_close()
        server_thread.join(timeout=2)

        self.assertFalse(request_thread.is_alive())
        self.assertTrue(errors)
        self.assertEqual(transport.active_task_ids, set())
        self.assertFalse(transport.cancel("missing"))

    def test_server_log_counts_observed_model_loads_without_assuming_one(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "llama-server.log"
            log.write_text(
                "srv load_model: loading model 'model.gguf'\n"
                "srv          init: initializing slots, n_slots = 3\n",
                encoding="utf-8",
            )
            evidence = inspect_server_log(log)
            self.assertEqual(evidence["observed_model_loads"], 1)
            self.assertEqual(evidence["observed_slot_count"], 3)

            log.write_text(
                "srv load_model: loading model 'model.gguf'\n"
                "srv load_model: loading model 'model.gguf'\n",
                encoding="utf-8",
            )
            evidence = inspect_server_log(log)
            self.assertEqual(evidence["observed_model_loads"], 2)
            self.assertEqual(evidence["observed_slot_count"], None)


if __name__ == "__main__":
    unittest.main()
