from __future__ import annotations

import csv
import json
from collections import Counter
from pathlib import Path
from typing import Any


BENCHMARK_SAMPLE_FIELDS = (
    "schema_version",
    "scenario_run_id",
    "scenario_id",
    "sample_group",
    "run_id",
    "run_generation",
    "mode",
    "app_version",
    "model_id",
    "model_version",
    "quantization",
    "runtime_version",
    "hardware_profile_id",
    "driver_version",
    "config_snapshot_hash",
    "input_asset_hash",
    "concurrency",
    "image_count",
    "tier",
    "budget_chars",
    "timeout_limit_s",
    "route",
    "event_name",
    "task_id",
    "event_id",
    "batch_id",
    "slot_id",
    "monotonic_timestamp_us",
    "utc_timestamp",
    "outcome",
    "error_code",
    "duration_us",
    "throughput_window_us",
    "throughput_valid_count",
    "vram_mib",
    "ram_mib",
    "handle_count",
    "gpu_percent",
    "queue_depth",
    "queue_limit",
    "content_age_ms",
    "evidence_ref",
    "review_status",
)


def write_benchmark_artifacts(
    output: Path,
    *,
    samples: list[dict[str, Any]],
    events: list[dict[str, Any]],
    summary: dict[str, Any],
) -> dict[str, Path]:
    output.mkdir(parents=True, exist_ok=True)
    samples_path = output / "samples.csv"
    with samples_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=BENCHMARK_SAMPLE_FIELDS, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(samples)

    events_path = output / "events.jsonl"
    with events_path.open("w", encoding="utf-8") as handle:
        for event in events:
            handle.write(json.dumps(event, ensure_ascii=False) + "\n")

    summary_path = output / "summary.json"
    summary_path.write_text(
        json.dumps(summary, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    return {
        "samples_csv": samples_path,
        "events_jsonl": events_path,
        "summary_json": summary_path,
    }


def _ratio(numerator: int, denominator: int) -> dict[str, int]:
    return {"numerator": numerator, "denominator": denominator}


def summarize_run(profile_id: str, results: list[dict[str, Any]]) -> dict[str, Any]:
    valid = [result for result in results if result["validation"]["classification"] == "VALID"]
    syntax_schema_valid = [
        result for result in results if result["validation"].get("syntax_schema_valid") is True
    ]
    scorable = [result for result in syntax_schema_valid if result.get("score") is not None]
    level_correct = [result for result in scorable if result["score"]["level_correct"]]
    emit_correct = [result for result in scorable if result["score"]["emit_correct"]]
    by_image_count: dict[str, Any] = {}
    for image_count in (1, 2, 3):
        group = [result for result in results if result["image_count"] == image_count]
        failures = Counter(
            result["validation"]["classification"]
            for result in group
            if result["validation"]["classification"] != "VALID"
        )
        by_image_count[str(image_count)] = {
            "cases": len(group),
            "syntax_schema_valid": sum(
                result["validation"].get("syntax_schema_valid") is True for result in group
            ),
            "contract_valid": sum(
                result["validation"]["classification"] == "VALID" for result in group
            ),
            "failure_classes": dict(sorted(failures.items())),
        }
    return {
        "profile_id": profile_id,
        "cases_total": len(results),
        "syntax_schema_valid": _ratio(len(syntax_schema_valid), len(results)),
        "contract_valid": _ratio(len(valid), len(results)),
        "emit_correct": _ratio(len(emit_correct), len(scorable)),
        "level_correct": _ratio(len(level_correct), len(scorable)),
        "by_image_count": by_image_count,
        "model_calls": sum(result.get("model_call_count", 0) for result in results),
        "repair_calls": sum(result.get("repair_call_count", 0) for result in results),
        "hard_gate": (
            "PASS"
            if (
                results
                and len(valid) == len(results)
                and len(emit_correct) == len(results)
                and len(level_correct) == len(results)
            )
            else "FAIL"
        ),
        "quality_threshold": "PENDING_CALIBRATION",
    }


def write_blocked_evidence(
    output: Path,
    *,
    profile_id: str,
    failure_class: str,
    detail: str,
    platform_name: str,
) -> dict[str, Any]:
    evidence = {
        "schema_version": 1,
        "profile_id": profile_id,
        "conclusion": "BLOCKED",
        "failure_class": failure_class,
        "detail": detail,
        "platform": platform_name,
        "windows_nvidia": "UNCONFIRMED",
        "vram_8gb": "UNCONFIRMED",
        "vram_12gb_plus": "UNCONFIRMED",
        "model_calls": 0,
        "repair_calls": 0,
    }
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(evidence, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return evidence
