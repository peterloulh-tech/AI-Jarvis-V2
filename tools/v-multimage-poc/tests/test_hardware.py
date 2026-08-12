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
        sample = parse_nvidia_csv("NVIDIA GeForce RTX 4070, 12282, 4100, 67\n")
        self.assertEqual(sample["gpu_name"], "NVIDIA GeForce RTX 4070")
        self.assertEqual(sample["memory_total_mib"], 12282)
        self.assertEqual(sample["memory_used_mib"], 4100)
        self.assertEqual(sample["gpu_utilization_percent"], 67)

    def test_sampler_records_raw_samples_and_peak(self) -> None:
        probe = FakeProbe([
            "NVIDIA RTX TEST, 8192, 1200, 10\n",
            "NVIDIA RTX TEST, 8192, 4600, 80\n",
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
            self.assertEqual(summary["vram_class"], "8GB")
            self.assertEqual(len((Path(directory) / "gpu-samples.jsonl").read_text().splitlines()), 2)

    def test_unavailable_sampler_stays_unconfirmed(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            sampler = NvidiaSampler(Path(directory) / "gpu-samples.jsonl", probe=None)
            self.assertEqual(sampler.summary()["status"], "UNCONFIRMED")


if __name__ == "__main__":
    unittest.main()
