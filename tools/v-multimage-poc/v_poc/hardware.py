from __future__ import annotations

import json
import shutil
import subprocess
import threading
import time
from collections import Counter
from pathlib import Path
from typing import Callable

from .metrics import nearest_rank


Probe = Callable[[], str]


def parse_nvidia_csv(value: str) -> dict[str, int | str]:
    parts = [part.strip() for part in value.strip().split(",")]
    if len(parts) != 5:
        raise ValueError("unexpected nvidia-smi CSV field count")
    return {
        "gpu_name": parts[0],
        "memory_total_mib": int(parts[1]),
        "memory_used_mib": int(parts[2]),
        "gpu_utilization_percent": int(parts[3]),
        "driver_version": parts[4],
    }


def nvidia_smi_probe() -> str:
    executable = shutil.which("nvidia-smi")
    if not executable:
        raise FileNotFoundError("nvidia-smi is unavailable")
    return subprocess.check_output(
        [
            executable,
            "--query-gpu=name,memory.total,memory.used,utilization.gpu,driver_version",
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
        self._lock = threading.Lock()

    def sample_once(self, *, phase: str = "steady") -> dict[str, int | str]:
        if phase not in {"load_ready", "steady", "fault", "post_cleanup"}:
            raise ValueError(f"unsupported GPU sample phase: {phase}")
        if self.probe is None:
            raise FileNotFoundError("nvidia-smi is unavailable")
        with self._lock:
            rows = [row for row in self.probe().splitlines() if row.strip()]
            if len(rows) != 1:
                raise RuntimeError("V tests record exactly one active NVIDIA GPU per run")
            sample = parse_nvidia_csv(rows[0])
            sample["monotonic_ns"] = time.monotonic_ns()
            sample["phase"] = phase
            self.samples.append(sample)
            self.output.parent.mkdir(parents=True, exist_ok=True)
            with self.output.open("a", encoding="utf-8") as handle:
                handle.write(json.dumps(sample, ensure_ascii=False) + "\n")
        return sample

    def summary(self) -> dict[str, int | str]:
        if not self.samples:
            return {"status": "UNCONFIRMED", "samples": 0}
        total = int(self.samples[0]["memory_total_mib"])
        if 7168 <= total < 9216:
            vram_class = "8GB"
        elif total >= 11264:
            vram_class = "12GB+"
        else:
            vram_class = "OTHER"
        memory_used = [int(item["memory_used_mib"]) for item in self.samples]
        gpu_utilization = [int(item["gpu_utilization_percent"]) for item in self.samples]
        driver_versions = {str(item["driver_version"]) for item in self.samples}
        if len(driver_versions) != 1:
            raise RuntimeError("NVIDIA driver version changed within one benchmark run")
        return {
            "status": "RECORDED",
            "samples": len(self.samples),
            "gpu_name": self.samples[0]["gpu_name"],
            "driver_version": next(iter(driver_versions)),
            "memory_total_mib": total,
            "peak_memory_used_mib": max(int(item["memory_used_mib"]) for item in self.samples),
            "peak_gpu_utilization_percent": max(
                int(item["gpu_utilization_percent"]) for item in self.samples
            ),
            "memory_used_mib": {
                "p50": nearest_rank(memory_used, 0.50),
                "p95": nearest_rank(memory_used, 0.95),
                "max": max(memory_used),
            },
            "gpu_utilization_percent": {
                "p50": nearest_rank(gpu_utilization, 0.50),
                "p95": nearest_rank(gpu_utilization, 0.95),
                "max": max(gpu_utilization),
            },
            "phase_samples": dict(
                sorted(Counter(str(item["phase"]) for item in self.samples).items())
            ),
            "vram_class": vram_class,
        }
