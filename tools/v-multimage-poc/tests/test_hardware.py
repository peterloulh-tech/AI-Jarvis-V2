import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.hardware import NvidiaSampler, parse_nvidia_csv  # noqa: E402


class FakeProbe:
    def __init__(self, outputs: list[str]) -> None:
        self.outputs = iter(outputs)

    def __call__(self) -> str:
        return next(self.outputs)


class HardwareTests(unittest.TestCase):
    def test_parses_gpu_name_vram_and_utilization_without_vendor_claims(self) -> None:
        sample = parse_nvidia_csv("NVIDIA GeForce RTX 4070, 12282, 4100, 67, 591.44\n")
        self.assertEqual(sample["gpu_name"], "NVIDIA GeForce RTX 4070")
        self.assertEqual(sample["memory_total_mib"], 12282)
        self.assertEqual(sample["memory_used_mib"], 4100)
        self.assertEqual(sample["gpu_utilization_percent"], 67)
        self.assertEqual(sample["driver_version"], "591.44")

    def test_sampler_records_raw_samples_and_peak(self) -> None:
        probe = FakeProbe([
            "NVIDIA RTX TEST, 8192, 1200, 10, 591.44\n",
            "NVIDIA RTX TEST, 8192, 4600, 80, 591.44\n",
        ])
        with tempfile.TemporaryDirectory() as directory:
            sampler = NvidiaSampler(Path(directory) / "gpu-samples.jsonl", probe=probe)
            sampler.sample_once()
            sampler.sample_once()
            summary = sampler.summary()
            self.assertEqual(summary["status"], "RECORDED")
            self.assertEqual(summary["samples"], 2)
            self.assertEqual(summary["peak_memory_used_mib"], 4600)
            self.assertEqual(summary["peak_gpu_utilization_percent"], 80)
            self.assertEqual(summary["memory_used_mib"], {
                "p50": 1200,
                "p95": 4600,
                "max": 4600,
            })
            self.assertEqual(summary["gpu_utilization_percent"], {
                "p50": 10,
                "p95": 80,
                "max": 80,
            })
            self.assertEqual(summary["vram_class"], "8GB")
            self.assertEqual(summary["driver_version"], "591.44")
            self.assertEqual(len((Path(directory) / "gpu-samples.jsonl").read_text().splitlines()), 2)

    def test_sampler_preserves_measurement_phase_for_each_raw_sample(self) -> None:
        probe = FakeProbe([
            "NVIDIA RTX TEST, 16384, 6000, 20, 591.44\n",
            "NVIDIA RTX TEST, 16384, 9000, 70, 591.44\n",
            "NVIDIA RTX TEST, 16384, 800, 0, 591.44\n",
        ])
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "gpu-samples.jsonl"
            sampler = NvidiaSampler(output, probe=probe)

            sampler.sample_once(phase="load_ready")
            sampler.sample_once(phase="steady")
            sampler.sample_once(phase="post_cleanup")

            rows = [json.loads(line) for line in output.read_text().splitlines()]
            self.assertEqual(
                [row["phase"] for row in rows],
                ["load_ready", "steady", "post_cleanup"],
            )
            self.assertEqual(
                sampler.summary()["phase_samples"],
                {"load_ready": 1, "post_cleanup": 1, "steady": 1},
            )

    def test_unavailable_sampler_stays_unconfirmed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sampler = NvidiaSampler(Path(directory) / "gpu-samples.jsonl", probe=None)
            self.assertEqual(sampler.summary()["status"], "UNCONFIRMED")

    def test_non_target_vram_capacity_is_not_promoted_to_12gb_plus(self) -> None:
        probe = FakeProbe(["NVIDIA RTX TEST, 10240, 2000, 20, 591.44\n"])
        with tempfile.TemporaryDirectory() as directory:
            sampler = NvidiaSampler(Path(directory) / "gpu-samples.jsonl", probe=probe)
            sampler.sample_once(phase="steady")

            self.assertEqual(sampler.summary()["vram_class"], "OTHER")


if __name__ == "__main__":
    unittest.main()
