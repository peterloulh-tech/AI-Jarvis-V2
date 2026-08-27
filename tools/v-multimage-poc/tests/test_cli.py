import json
import csv
import socket
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "run_v_poc.py"
sys.path.insert(0, str(ROOT))

import run_v_poc  # noqa: E402


def write_fake_server(path: Path, *, response_delay: float = 0) -> None:
    source = textwrap.dedent("""\
        #!/usr/bin/env python3
        import json
        import sys
        import time
        from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

        port = int(sys.argv[sys.argv.index("--port") + 1])
        slots = int(sys.argv[sys.argv.index("--parallel") + 1])
        print("srv load_model: loading model 'model.gguf'", flush=True)
        print(f"srv          init: initializing slots, n_slots = {slots}", flush=True)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                if self.path == "/health":
                    self.send_response(200)
                    self.end_headers()
                else:
                    self.send_response(404)
                    self.end_headers()

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                self.rfile.read(length)
                time.sleep(__RESPONSE_DELAY__)
                raw = json.dumps({
                    "level": "ordinary",
                    "emit": True,
                    "event": "visible movement",
                    "comments": ["steady"],
                    "summary": "",
                })
                body = json.dumps({
                    "choices": [{"message": {"content": raw}, "finish_reason": "stop"}],
                    "usage": {"prompt_tokens": 1, "completion_tokens": 1, "total_tokens": 2},
                }).encode()
                try:
                    self.send_response(200)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
                except OSError:
                    pass

            def log_message(self, format, *args):
                pass

        ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
        """).replace("__RESPONSE_DELAY__", repr(response_delay))
    path.write_text(source, encoding="utf-8")
    path.chmod(0o755)


def free_port() -> int:
    with socket.socket() as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


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

    def test_qwen_profile_uses_official_pre_metadata_change_artifact(self) -> None:
        profile = run_v_poc.load_profiles(run_v_poc.PROFILE_FILE)["V-C01"]
        model = next(item for item in profile["artifacts"] if item["role"] == "model")
        self.assertEqual(model["size_bytes"], 2497281664)
        self.assertEqual(
            model["sha256"],
            "66358cb18bb6b3b1b6675aa412c7a88ef01d228f481184d13668e5201c730a0a",
        )
        self.assertEqual(model["gguf_architecture"], "qwen3vl")

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

    def test_benchmark_without_artifacts_records_run_scoped_blocked_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            result = self.run_cli(
                "benchmark",
                "--profile", "V-C01",
                "--models-dir", str(Path(directory) / "models"),
                "--server", str(Path(directory) / "llama-server"),
                "--output", str(output),
                "--slots", "1",
                "--image-count", "1",
                "--run-id", "missing-artifacts",
            )

            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
            evidence = json.loads(
                (output / "V-C01" / "benchmark" / "missing-artifacts" / "blocked.json")
                .read_text(encoding="utf-8")
            )
            self.assertEqual(evidence["failure_class"], "RUNTIME_ARTIFACT_UNAVAILABLE")
            self.assertEqual(evidence["model_calls"], 0)

    def test_benchmark_rejects_invalid_values_without_traceback_or_output_escape(self) -> None:
        base_args = [
            "benchmark",
            "--profile", "V-C01",
            "--models-dir", "missing-models",
            "--server", "missing-server",
            "--output", "ignored",
            "--slots", "1",
            "--image-count", "1",
        ]
        for extra, marker in (
            (["--samples", "0"], "samples"),
            (["--styles", ""], "styles"),
            (["--run-id", "../escaped"], "run-id"),
        ):
            with self.subTest(extra=extra):
                result = self.run_cli(*(base_args + extra))
                self.assertEqual(result.returncode, 2)
                self.assertNotIn("Traceback", result.stderr)
                self.assertIn(marker, result.stderr)

    def test_benchmark_refuses_to_mix_evidence_in_existing_run_directory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "evidence"
            run_output = output / "V-C01" / "benchmark" / "existing-run"
            run_output.mkdir(parents=True)
            sentinel = run_output / "summary.json"
            sentinel.write_text('{"existing": true}\n', encoding="utf-8")

            result = self.run_cli(
                "benchmark",
                "--profile", "V-C01",
                "--models-dir", str(Path(directory) / "missing-models"),
                "--server", str(Path(directory) / "missing-server"),
                "--output", str(output),
                "--slots", "1",
                "--image-count", "1",
                "--run-id", "existing-run",
            )

            self.assertEqual(result.returncode, 2)
            self.assertNotIn("Traceback", result.stderr)
            self.assertIn("not empty", result.stderr)
            self.assertEqual(sentinel.read_text(encoding="utf-8"), '{"existing": true}\n')

    def test_invalid_profile_cannot_mix_results(self) -> None:
        result = self.run_cli("prepare", "--profile", "V-C01,V-C02", "--output", "ignored")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("invalid choice", result.stderr)

    def test_benchmark_parser_keeps_slots_and_image_count_in_one_sample_group(self) -> None:
        args = run_v_poc.parser().parse_args([
            "benchmark",
            "--profile", "V-C01",
            "--server", "C:/runtime/llama-server.exe",
            "--models-dir", "C:/models/V-C01",
            "--output", "C:/evidence/task27",
            "--slots", "3",
            "--image-count", "2",
        ])

        self.assertIs(args.handler, run_v_poc.benchmark)
        self.assertEqual(args.slots, 3)
        self.assertEqual(args.image_count, 2)
        self.assertEqual(args.samples, 20)
        self.assertEqual(args.warmup, 1)
        self.assertEqual(args.fault, "none")

        with self.assertRaises(SystemExit):
            run_v_poc.parser().parse_args([
                "benchmark",
                "--profile", "V-C01",
                "--server", "llama-server.exe",
                "--models-dir", "models",
                "--output", "evidence",
                "--slots", "4",
                "--image-count", "2",
            ])

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

    def test_benchmark_runs_one_server_and_writes_traceable_group_evidence(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "llama-server"
            write_fake_server(server)
            model = root / "model.gguf"
            mmproj = root / "mmproj.gguf"
            model.write_bytes(b"model")
            mmproj.write_bytes(b"mmproj")
            output = root / "evidence"
            port = free_port()
            args = run_v_poc.parser().parse_args([
                "benchmark",
                "--profile", "V-C01",
                "--server", str(server),
                "--models-dir", str(root),
                "--output", str(output),
                "--slots", "2",
                "--image-count", "1",
                "--samples", "3",
                "--warmup", "1",
                "--run-id", "test-run",
                "--port", str(port),
            ])
            verified = [
                {"role": "runtime", "path": str(server), "size_bytes": server.stat().st_size},
                {"role": "model", "path": str(model), "size_bytes": model.stat().st_size},
                {"role": "mmproj", "path": str(mmproj), "size_bytes": mmproj.stat().st_size},
            ]

            with mock.patch.object(run_v_poc, "_verify_inputs", return_value=verified):
                result = run_v_poc.benchmark(args)

            self.assertEqual(result, 0)
            group = output / "V-C01" / "benchmark" / "test-run"
            summary = json.loads((group / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["n_total"], 3)
            self.assertEqual(summary["outcomes"], {"success": 3})
            self.assertEqual(summary["topology"]["server_instances"], 1)
            self.assertEqual(summary["topology"]["weight_instances"], 1)
            self.assertEqual(summary["topology"]["parallel_slots"], 2)
            self.assertEqual(summary["runtime"]["parallel_slots"], 2)
            self.assertEqual(summary["process_cleanup"]["remaining_launched_processes"], 0)
            self.assertEqual(summary["conclusion"], "DATA_INCOMPLETE")
            self.assertEqual(summary["fault_result"], "NOT_APPLICABLE")
            self.assertEqual(len(list((group / "cases").glob("*.json"))), 3)
            warmup = json.loads(
                (group / "warmup" / "warmup-1.json").read_text(encoding="utf-8")
            )
            self.assertTrue(warmup["excluded_from_metrics"])
            self.assertEqual(warmup["task_id"], "warmup-1")
            self.assertEqual(summary["warmup_evidence"], ["warmup/warmup-1.json"])
            first_event = json.loads(
                (group / "events.jsonl").read_text(encoding="utf-8").splitlines()[0]
            )
            self.assertRegex(first_event["config_snapshot_hash"], r"^[0-9a-f]{64}$")
            self.assertEqual(first_event["app_version"], "UNCONFIRMED")
            self.assertEqual(first_event["model_id"], "V-C01")
            self.assertEqual(first_event["runtime_version"], "6e62ba538478202094edc6c100c782719e310aa3")
            self.assertIn("hardware_profile_id", first_event)
            self.assertIn("driver_version", first_event)
            with (group / "samples.csv").open(newline="", encoding="utf-8") as handle:
                sample_row = next(csv.DictReader(handle))
            self.assertEqual(sample_row["scenario_run_id"], "test-run")
            self.assertEqual(sample_row["scenario_id"], "BENCH-007+BENCH-008")
            self.assertEqual(sample_row["mode"], "V")
            self.assertEqual(sample_row["model_id"], "V-C01")
            self.assertEqual(sample_row["concurrency"], "2")
            self.assertEqual(sample_row["image_count"], "1")
            self.assertEqual(sample_row["tier"], "standard")
            self.assertGreater(int(sample_row["duration_us"]), 0)
            self.assertRegex(sample_row["input_asset_hash"], r"^[0-9a-f]{64}$")
            self.assertTrue(sample_row["evidence_ref"].startswith("cases/"))
            self.assertEqual(sample_row["review_status"], "DATA_INCOMPLETE")

    def test_benchmark_cancel_interrupts_one_request_and_keeps_other_samples(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            server = root / "llama-server"
            write_fake_server(server, response_delay=0.25)
            model = root / "model.gguf"
            mmproj = root / "mmproj.gguf"
            model.write_bytes(b"model")
            mmproj.write_bytes(b"mmproj")
            output = root / "evidence"
            args = run_v_poc.parser().parse_args([
                "benchmark",
                "--profile", "V-C01",
                "--server", str(server),
                "--models-dir", str(root),
                "--output", str(output),
                "--slots", "2",
                "--image-count", "1",
                "--samples", "3",
                "--warmup", "0",
                "--run-id", "cancel-run",
                "--fault", "cancel",
                "--fault-delay", "0.05",
                "--port", str(free_port()),
            ])
            verified = [
                {"role": "runtime", "path": str(server), "size_bytes": server.stat().st_size},
                {"role": "model", "path": str(model), "size_bytes": model.stat().st_size},
                {"role": "mmproj", "path": str(mmproj), "size_bytes": mmproj.stat().st_size},
            ]

            with mock.patch.object(run_v_poc, "_verify_inputs", return_value=verified):
                result = run_v_poc.benchmark(args)

            self.assertEqual(result, 0)
            group = output / "V-C01" / "benchmark" / "cancel-run"
            summary = json.loads((group / "summary.json").read_text(encoding="utf-8"))
            self.assertEqual(summary["n_total"], 3)
            self.assertEqual(summary["outcomes"], {"success": 2, "canceled": 1})
            self.assertEqual(summary["fault_evidence"]["cancel_result"], True)
            self.assertEqual(summary["fault_evidence"]["generation_after"], 1)
            self.assertEqual(summary["fault_result"], "PASS_FROZEN")
            self.assertEqual(summary["process_cleanup"]["remaining_launched_processes"], 0)
            self.assertEqual(len(list((group / "cases").glob("*.json"))), 3)

    def test_benchmark_service_faults_expire_all_old_generation_tasks(self) -> None:
        for fault in ("server-exit", "global-reset"):
            with self.subTest(fault=fault), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                server = root / "llama-server"
                write_fake_server(server, response_delay=0.25)
                model = root / "model.gguf"
                mmproj = root / "mmproj.gguf"
                model.write_bytes(b"model")
                mmproj.write_bytes(b"mmproj")
                output = root / "evidence"
                args = run_v_poc.parser().parse_args([
                    "benchmark",
                    "--profile", "V-C01",
                    "--server", str(server),
                    "--models-dir", str(root),
                    "--output", str(output),
                    "--slots", "2",
                    "--image-count", "1",
                    "--samples", "3",
                    "--warmup", "0",
                    "--run-id", fault,
                    "--fault", fault,
                    "--fault-delay", "0.05",
                    "--port", str(free_port()),
                ])
                verified = [
                    {"role": "runtime", "path": str(server), "size_bytes": server.stat().st_size},
                    {"role": "model", "path": str(model), "size_bytes": model.stat().st_size},
                    {"role": "mmproj", "path": str(mmproj), "size_bytes": mmproj.stat().st_size},
                ]

                with mock.patch.object(run_v_poc, "_verify_inputs", return_value=verified):
                    result = run_v_poc.benchmark(args)

                self.assertEqual(result, 0)
                group = output / "V-C01" / "benchmark" / fault
                summary = json.loads((group / "summary.json").read_text(encoding="utf-8"))
                self.assertEqual(summary["n_total"], 3)
                self.assertEqual(summary["outcomes"], {"expired": 3})
                self.assertEqual(summary["fault_evidence"]["generation_after"], 2)
                self.assertEqual(summary["fault_result"], "PASS_FROZEN")
                self.assertEqual(summary["topology"]["server_instances"], 1)
                self.assertEqual(summary["topology"]["model_loads"], 1)
                self.assertEqual(summary["topology"]["observed_slot_count"], 2)
                self.assertEqual(
                    summary["process_cleanup"]["remaining_launched_processes"], 0
                )
                self.assertEqual(len(list((group / "cases").glob("*.json"))), 3)


if __name__ == "__main__":
    unittest.main()
