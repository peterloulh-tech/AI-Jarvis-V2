from __future__ import annotations

import copy
import json
from pathlib import Path
from typing import Any

from .contract import SCHEMA


CASES = [
    {"case_id": f"{scene}-{image_count}", "scene": scene, "image_count": image_count}
    for scene in ("calm", "ordinary", "highlight")
    for image_count in (1, 2, 3)
]


def load_profiles(path: Path) -> dict[str, dict[str, Any]]:
    document = json.loads(path.read_text(encoding="utf-8"))
    runtime = document["runtime"]
    profiles: dict[str, dict[str, Any]] = {}
    for profile in document["profiles"]:
        item = copy.deepcopy(profile)
        item["runtime"] = copy.deepcopy(runtime)
        profiles[item["id"]] = item
    if set(profiles) != {"V-C01", "V-C02"}:
        raise ValueError("profiles.json must contain exactly V-C01 and V-C02")
    return profiles


def plan_profile(profile: dict[str, Any]) -> dict[str, Any]:
    return {
        "profile_id": profile["id"],
        "runtime": profile["runtime"],
        "artifacts": profile["artifacts"],
        "model_specific_visual_parameters": profile["model_specific_visual_parameters"],
        "canvas": {"width": 896, "height": 512, "fit": "contain-no-stretch"},
        "cases": CASES,
        "request_contract": {
            "prompt_version": "AIJARVISV2-26-zh-CN-v1",
            "schema": SCHEMA,
            "style_id": "friendly-witty-v1",
            "model_calls_per_case": 1,
            "repair_calls": 0,
        },
        "server_instances": 1,
        "weight_instances": 1,
        "parallel_slots": 1,
        "network": "loopback-only-after-artifact-provisioning",
    }
