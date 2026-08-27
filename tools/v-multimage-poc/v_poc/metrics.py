from __future__ import annotations

import math
from typing import Iterable


def nearest_rank(values: Iterable[int], percentile: float) -> int:
    ordered = sorted(values)
    if not ordered:
        raise ValueError("nearest-rank requires at least one value")
    if percentile <= 0 or percentile > 1:
        raise ValueError("percentile must be greater than 0 and at most 1")
    index = math.ceil(percentile * len(ordered)) - 1
    return ordered[index]


def distribution(values: list[int]) -> dict[str, int]:
    if not values:
        return {"n": 0}
    return {
        "n": len(values),
        "min": min(values),
        "max": max(values),
        "p50": nearest_rank(values, 0.50),
        "p95": nearest_rank(values, 0.95),
    }
