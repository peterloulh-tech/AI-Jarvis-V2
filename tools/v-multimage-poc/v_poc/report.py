from __future__ import annotations

import json
from collections import Counter
from pathlib import Path
from typing import Any


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
        "hard_gate": "PASS" if results and len(valid) == len(results) else "FAIL",
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
