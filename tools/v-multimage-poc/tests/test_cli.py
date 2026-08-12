import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "run_v_poc.py"
sys.path.insert(0, str(ROOT))

import run_v_poc  # noqa: E402


class CliTests(unittest.TestCase):
    def run_cli(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CLI), *args],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_prepare_writes_fixture_and_profile_plan(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            result = self.run_cli("prepare", "--profile", "V-C01", "--output", str(output))
            self.assertEqual(result.returncode, 0, result.stderr)
            plan = json.loads((output / "V-C01" / "run-plan.json").read_text(encoding="utf-8"))
            manifest = json.loads((output / "fixture" / "fixture-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(plan["profile_id"], "V-C01")
            self.assertEqual(len(plan["cases"]), 9)
            self.assertEqual(len(manifest["groups"]), 9)

    def test_check_without_artifacts_records_blocked_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            models = Path(directory) / "models"
            result = self.run_cli(
                "check",
                "--profile",
                "V-C02",
                "--models-dir",
                str(models),
                "--server",
                str(Path(directory) / "llama-server"),
                "--output",
                str(output),
            )
            self.assertEqual(result.returncode, 2)
            evidence = json.loads((output / "V-C02" / "blocked.json").read_text(encoding="utf-8"))
            self.assertEqual(evidence["conclusion"], "BLOCKED")
            self.assertEqual(evidence["failure_class"], "RUNTIME_ARTIFACT_UNAVAILABLE")
            self.assertEqual(evidence["model_calls"], 0)

    def test_invalid_profile_cannot_mix_results(self) -> None:
        result = self.run_cli("prepare", "--profile", "V-C01,V-C02", "--output", "ignored")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid choice", result.stderr)

    def test_default_input_check_does_not_hash_large_artifacts(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "llama-server"
            model = root / "model.gguf"
            mmproj = root / "mmproj.gguf"
            server.write_bytes(b"server")
            model.write_bytes(b"model")
            mmproj.write_bytes(b"projector")
            args = mock.Mock(server=server, models_dir=root)
            profile = {
                "runtime": {"release": "b1", "revision": "abc"},
                "artifacts": [
                    {"role": "model", "name": model.name, "size_bytes": 5, "sha256": "0" * 64},
                    {"role": "mmproj", "name": mmproj.name, "size_bytes": 9, "sha256": "1" * 64},
                ],
            }
            with mock.patch.object(run_v_poc, "file_sha256", side_effect=AssertionError("hashed")):
                verified = run_v_poc._verify_inputs(args, profile, full_sha256=False)
            self.assertTrue(all(item["verification_mode"] == "fast_identity" for item in verified))

    def test_admission_mode_hashes_once_and_replays_locked_model_hashes(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "llama-server"
            model = root / "model.gguf"
            mmproj = root / "mmproj.gguf"
            server.write_bytes(b"server")
            model.write_bytes(b"model")
            mmproj.write_bytes(b"projector")
            profile = {
                "runtime": {"release": "b1", "revision": "abc"},
                "artifacts": [
                    {"role": "model", "name": model.name, "size_bytes": 5, "sha256": __import__("hashlib").sha256(b"model").hexdigest()},
                    {"role": "mmproj", "name": mmproj.name, "size_bytes": 9, "sha256": __import__("hashlib").sha256(b"projector").hexdigest()},
                ],
            }
            args = mock.Mock(server=server, models_dir=root)
            verified = run_v_poc._verify_inputs(args, profile, full_sha256=True)
            self.assertTrue(all(item["verification_mode"] == "full_sha256" for item in verified))
            self.assertTrue(all("sha256" in item for item in verified))

    def test_unknown_architecture_is_classified_as_locked_runtime_conflict(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory) / "llama-server.log"
            log.write_text(
                "error loading model: unknown model architecture: "
                "'Qwen3VLForConditionalGeneration'\n",
                encoding="utf-8",
            )
            failure_class, detail = run_v_poc._classify_run_failure(
                RuntimeError("llama-server exited during load with code 1"), log
            )
            self.assertEqual(failure_class, "LOCKED_MODEL_RUNTIME_CONFLICT")
            self.assertIn("unknown model architecture", detail)


if __name__ == "__main__":
    unittest.main()
