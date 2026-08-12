import hashlib
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.runner import (  # noqa: E402
    ArtifactError,
    RunLock,
    build_server_command,
    execute_case,
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
        command = build_server_command(
            server=Path("C:/poc/llama-server.exe"),
            model=Path("C:/models/model.gguf"),
            mmproj=Path("C:/models/mmproj.gguf"),
            host="127.0.0.1",
            port=8086,
        )
        self.assertEqual(command.count("--parallel"), 1)
        self.assertEqual(command[command.index("--parallel") + 1], "1")
        self.assertEqual(command.count("--model"), 1)
        self.assertEqual(command.count("--mmproj"), 1)
        self.assertNotIn("-hf", command)
        self.assertNotIn("--mmproj-url", command)
        self.assertEqual(command[0], "C:/poc/llama-server.exe")

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

    def test_run_lock_prevents_a_second_profile_from_residing(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            lock_path = Path(directory) / "active.lock"
            with RunLock(lock_path, profile_id="V-C01"):
                with self.assertRaisesRegex(RuntimeError, "another V PoC run is active"):
                    with RunLock(lock_path, profile_id="V-C02"):
                        pass
            self.assertFalse(lock_path.exists())


if __name__ == "__main__":
    unittest.main()
