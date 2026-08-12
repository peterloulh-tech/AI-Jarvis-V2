from __future__ import annotations

import json
import shutil
import subprocess
import time
from pathlib import Path
from typing import Callable


Probe = Callable[[], str]


def parse_nvidia_csv(value: str) -> dict[str, int | str]:
    parts = [part.strip() for part in value.strip().split(",")]
    if len(parts) != 4:
        raise ValueError("unexpected nvidia-smi CSV field count")
    return {
        "gpu_name": parts[0],
        "memory_total_mib": int(parts[1]),
        "memory_used_mib": int(parts[2]),
        "gpu_utilization_percent": int(parts[3]),
    }


def nvidia_smi_probe() -> str:
    executable = shutil.which("nvidia-smi")
    if not executable:
        raise FileNotFoundError("nvidia-smi is unavailable")
    return subprocess.check_output(
        [
            executable,
            "--query-gpu=name,memory.total,memory.used,utilization.gpu",
            "--format=csv,noheader,nounits",
        ],
        text=True,
        timeout=10,
    )


class NvidiaSampler:
    def __init__(self, output: Path, *, probe: Probe | None = nvidia_smi_probe) -> None:
        self.output = output
        self.probe = probe
        self.samples: list[dict[str, int | str]] = []

    def sample_once(self) -> dict[str, int | str]:
        if self.probe is None:
            raise FileNotFoundError("nvidia-smi is unavailable")
        rows = [row for row in self.probe().splitlines() if row.strip()]
        if len(rows) != 1:
            raise RuntimeError("task 26 records exactly one active NVIDIA GPU per run")
        sample = parse_nvidia_csv(rows[0])
        sample["monotonic_ns"] = time.monotonic_ns()
        self.samples.append(sample)
        self.output.parent.mkdir(parents=True, exist_ok=True)
        with self.output.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(sample, ensure_ascii=False) + "\n")
        return sample

    def summary(self) -> dict[str, int | str]:
        if not self.samples:
            return {"status": "UNCONFIRMED", "samples": 0}
        total = int(self.samples[0]["memory_total_mib"])
        vram_class = "8GB" if total < 10240 else "12GB+"
        return {
            "status": "RECORDED",
            "samples": len(self.samples),
            "gpu_name": self.samples[0]["gpu_name"],
            "memory_total_mib": total,
            "peak_memory_used_mib": max(int(item["memory_used_mib"]) for item in self.samples),
            "peak_gpu_utilization_percent": max(
                int(item["gpu_utilization_percent"]) for item in self.samples
            ),
            "vram_class": vram_class,
        }
