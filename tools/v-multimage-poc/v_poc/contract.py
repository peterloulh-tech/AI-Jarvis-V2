from __future__ import annotations

import json
import re
from typing import Any


SCHEMA = {
    "type": "object",
    "additionalProperties": False,
    "required": ["emit", "event", "level", "comments", "summary"],
    "properties": {
        "emit": {"type": "boolean"},
        "event": {"type": "string"},
        "level": {"type": "string", "enum": ["none", "ordinary", "highlight"]},
        "comments": {"type": "array", "items": {"type": "string"}, "maxItems": 3},
        "summary": {"type": "string", "maxLength": 30},
    },
}


def build_payload(
    *,
    image_data_urls: list[str],
    task_id: str,
    captured_at: str,
    run_generation: int,
    style_id: str,
    previous_summary: str,
) -> dict[str, Any]:
    if not 1 <= len(image_data_urls) <= 3:
        raise ValueError("each request requires 1 to 3 images")
    prompt = f"""你是本地视觉事件分析器。一次且仅一次分析以下按时间顺序排列的图像。
task_id={task_id}
captured_at={captured_at}
run_generation={run_generation}
style_id={style_id}
最近一条有效客观摘要={previous_summary or '无'}

只输出一个 JSON 对象，字段必须完整：
- emit：平静或无可描述事件时为 false；否则为 true。
- event：最多一个主要可见事件；emit=false 时必须为空字符串。
- level：emit=false 时为 none；普通事件为 ordinary；明显高光为 highlight。不要用画面变化量直接判断高光。
- comments：当前 style_id 的一个弹幕批次，0至3条；emit=false 时必须为空数组。不得侮辱、歧视、引战、编造事实或承诺胜利。
- summary：可选客观摘要，最多30个中文字；emit=false 时必须为空字符串。
禁止输出解释、Markdown 或 JSON 之外文本。"""
    content: list[dict[str, Any]] = [{"type": "text", "text": prompt}]
    content.extend(
        {"type": "image_url", "image_url": {"url": data_url}}
        for data_url in image_data_urls
    )
    return {
        "temperature": 0,
        "top_k": 1,
        "stream": False,
        "max_tokens": 384,
        "chat_template_kwargs": {"enable_thinking": False},
        "json_schema": SCHEMA,
        "messages": [{"role": "user", "content": content}],
    }


def _han_count(value: str) -> int:
    return len(re.findall(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]", value))


def classify_response(raw: str) -> dict[str, Any]:
    base: dict[str, Any] = {"repair_calls": 0, "syntax_schema_valid": False}
    try:
        value = json.loads(raw)
    except (TypeError, json.JSONDecodeError):
        return {**base, "classification": "MALFORMED_JSON", "parsed": None}
    required = {"emit", "event", "level", "comments", "summary"}
    if not isinstance(value, dict) or set(value) != required:
        return {**base, "classification": "SCHEMA_FIELDS", "parsed": value}
    if (
        not isinstance(value["emit"], bool)
        or not isinstance(value["event"], str)
        or value["level"] not in {"none", "ordinary", "highlight"}
        or not isinstance(value["comments"], list)
        or any(not isinstance(item, str) for item in value["comments"])
        or len(value["comments"]) > 3
        or not isinstance(value["summary"], str)
    ):
        return {**base, "classification": "SCHEMA_TYPES", "parsed": value}
    if value["emit"] is False and (
        value["event"] or value["level"] != "none" or value["comments"] or value["summary"]
    ):
        return {
            **base,
            "syntax_schema_valid": True,
            "classification": "SILENCE_INCONSISTENT",
            "parsed": value,
        }
    if value["emit"] is True and (
        not value["event"] or value["level"] == "none" or not value["comments"]
    ):
        return {
            **base,
            "syntax_schema_valid": True,
            "classification": "EMIT_INCOMPLETE",
            "parsed": value,
        }
    if _han_count(value["summary"]) > 30:
        return {
            **base,
            "syntax_schema_valid": True,
            "classification": "SUMMARY_TOO_LONG",
            "parsed": value,
        }
    return {**base, "syntax_schema_valid": True, "classification": "VALID", "parsed": value}


def score_result(parsed: dict[str, Any], gold: dict[str, Any]) -> dict[str, Any]:
    event = parsed["event"]
    required_terms = gold["required_event_terms"]
    forbidden_hit = [term for term in gold["forbidden_event_terms"] if term in event]
    matched = sum(term in event for term in required_terms)
    summary_terms = [term for term in required_terms if term in parsed["summary"]]
    summary_factual = not parsed["summary"] or (
        not forbidden_hit and (not required_terms or bool(summary_terms))
    )
    return {
        "emit_correct": parsed["emit"] == gold["expected_emit"],
        "level_correct": parsed["level"] == gold["expected_level"],
        "event_terms_matched": matched,
        "event_terms_total": len(required_terms),
        "forbidden_terms_hit": forbidden_hit,
        "summary_factual": summary_factual,
        "comment_count": len(parsed["comments"]),
        "comment_diversity_count": len(set(parsed["comments"])),
        "summary_han_count": _han_count(parsed["summary"]),
    }
