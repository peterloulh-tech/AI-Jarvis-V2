import json
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.contract import build_payload, classify_response, score_result  # noqa: E402


class ContractTests(unittest.TestCase):
    def test_payload_uses_one_request_with_same_prompt_schema_and_all_images(self) -> None:
        payload = build_payload(
            image_data_urls=["data:image/png;base64,AAA", "data:image/png;base64,BBB"],
            task_id="ordinary-2",
            captured_at="2026-08-12T00:00:00Z",
            run_generation=1,
            style_id="friendly-witty-v1",
            previous_summary="蓝色圆点正在移动",
            output_mode="required",
        )
        content = payload["messages"][0]["content"]
        self.assertEqual([item["type"] for item in content], ["text", "image_url", "image_url"])
        self.assertEqual(payload["temperature"], 0)
        self.assertEqual(payload["top_k"], 1)
        self.assertEqual(payload["stream"], False)
        self.assertEqual(payload["chat_template_kwargs"], {"enable_thinking": False})
        self.assertEqual(
            payload["json_schema"]["required"],
            ["level", "emit", "event", "comments", "summary"],
        )
        self.assertEqual(
            list(payload["json_schema"]["properties"]),
            ["level", "emit", "event", "comments", "summary"],
        )
        self.assertEqual(payload["json_schema"]["properties"]["emit"], {"const": True})
        self.assertEqual(payload["json_schema"]["properties"]["level"]["enum"], ["ordinary", "highlight"])
        self.assertEqual(payload["json_schema"]["properties"]["comments"]["minItems"], 1)
        prompt = content[0]["text"]
        self.assertIn("task_id=ordinary-2", prompt)
        self.assertIn("style_id=friendly-witty-v1", prompt)
        self.assertIn("最多30个中文字", prompt)
        self.assertIn("本次必须输出", prompt)
        self.assertIn("主体及其具体动作或状态", prompt)
        self.assertIn("#main_event", prompt)
        self.assertIn("object interaction", prompt)
        self.assertIn("明确命中、碰撞或爆发光圈", prompt)
        self.assertIn("仅有主体出现、位置或普通移动", prompt)
        self.assertNotIn("平静或无可描述事件时为 false", prompt)
        self.assertNotIn("http://", json.dumps(payload, ensure_ascii=False))
        self.assertNotIn("https://", json.dumps(payload, ensure_ascii=False))

    def test_allow_silence_keeps_emit_false_branch_available(self) -> None:
        payload = build_payload(
            image_data_urls=["data:image/png;base64,AAA"],
            task_id="calm-1",
            captured_at="2026-08-12T00:00:00Z",
            run_generation=1,
            style_id="friendly-witty-v1",
            previous_summary="",
            output_mode="allow_silence",
        )
        branches = payload["json_schema"]["oneOf"]
        self.assertEqual(len(branches), 2)
        silence, emitted = branches
        self.assertEqual(
            silence["required"], ["level", "emit", "event", "comments", "summary"]
        )
        self.assertEqual(
            list(silence["properties"]),
            ["level", "emit", "event", "comments", "summary"],
        )
        self.assertEqual(silence["properties"]["emit"], {"const": False})
        self.assertEqual(silence["properties"]["event"], {"const": ""})
        self.assertEqual(silence["properties"]["level"], {"const": "none"})
        self.assertEqual(silence["properties"]["comments"], {"const": []})
        self.assertEqual(silence["properties"]["summary"], {"const": ""})
        self.assertEqual(emitted["properties"]["emit"], {"const": True})
        self.assertEqual(emitted["properties"]["event"]["minLength"], 1)
        self.assertEqual(emitted["properties"]["level"]["enum"], ["ordinary", "highlight"])
        self.assertEqual(emitted["properties"]["comments"]["minItems"], 1)
        prompt = payload["messages"][0]["content"][0]["text"]
        self.assertIn("允许智能沉默", prompt)
        self.assertIn("空画面、静态背景、只有装饰或界面", prompt)
        self.assertIn("不算事件，必须沉默", prompt)
        self.assertIn("不得把 empty、background 或静态界面本身当作事件", prompt)
        self.assertIn(
            '空画面或静态背景示例={"emit":false,"event":"","level":"none","comments":[],"summary":""}',
            prompt,
        )
        self.assertIn(
            '有动作或交互示例={"emit":true,"event":"角色完成一次跳跃","level":"ordinary"',
            prompt,
        )

    def test_accepts_emit_and_silence_contracts(self) -> None:
        ordinary = classify_response(json.dumps({
            "emit": True,
            "event": "蓝色圆点穿过中央标记",
            "level": "ordinary",
            "comments": ["稳稳推进，节奏在线"],
            "summary": "蓝点穿过中央标记",
        }, ensure_ascii=False))
        silence = classify_response(json.dumps({
            "emit": False,
            "event": "",
            "level": "none",
            "comments": [],
            "summary": "",
        }, ensure_ascii=False))
        self.assertEqual(ordinary["classification"], "VALID")
        self.assertEqual(ordinary["syntax_schema_valid"], True)
        self.assertEqual(silence["classification"], "VALID")
        self.assertEqual(silence["syntax_schema_valid"], True)

    def test_classifies_damage_without_repair_or_second_call(self) -> None:
        cases = {
            "not-json": "MALFORMED_JSON",
            json.dumps({"emit": True}): "SCHEMA_FIELDS",
            json.dumps({
                "emit": False, "event": "仍有事件", "level": "ordinary", "comments": [], "summary": ""
            }, ensure_ascii=False): "SILENCE_INCONSISTENT",
            json.dumps({
                "emit": True, "event": "事件", "level": "ordinary", "comments": ["评论"],
                "summary": "一二三四五六七八九十一二三四五六七八九十一二三四五六七八九十一",
            }, ensure_ascii=False): "SUMMARY_TOO_LONG",
            json.dumps({
                "emit": True, "event": "", "level": "none", "comments": [], "summary": ""
            }, ensure_ascii=False): "EMIT_INCOMPLETE",
            json.dumps({
                "emit": True, "event": "#main_event", "level": "ordinary",
                "comments": ["继续观察"], "summary": "",
            }, ensure_ascii=False): "EVENT_PLACEHOLDER",
            json.dumps({
                "emit": True, "event": "object interaction", "level": "ordinary",
                "comments": ["发生互动"], "summary": "",
            }, ensure_ascii=False): "EVENT_PLACEHOLDER",
        }
        for raw, expected in cases.items():
            with self.subTest(expected=expected):
                result = classify_response(raw)
                self.assertEqual(result["classification"], expected)
                self.assertEqual(result["repair_calls"], 0)
                self.assertEqual(
                    result["syntax_schema_valid"],
                    expected in {
                        "SILENCE_INCONSISTENT", "SUMMARY_TOO_LONG", "EMIT_INCOMPLETE",
                        "EVENT_PLACEHOLDER",
                    },
                )

    def test_scores_same_objective_fields_for_each_scene(self) -> None:
        parsed = {
            "emit": True,
            "event": "红色星形撞上金色目标并爆发光圈",
            "level": "highlight",
            "comments": ["这一撞直接点亮全场", "高光时刻来了"],
            "summary": "红星命中金色目标",
        }
        score = score_result(
            parsed,
            {
                "expected_emit": True,
                "expected_level": "highlight",
                "required_event_terms": ["红", "目标"],
                "forbidden_event_terms": ["胜利"],
            },
        )
        self.assertEqual(score["emit_correct"], True)
        self.assertEqual(score["level_correct"], True)
        self.assertEqual(score["event_terms_matched"], 2)
        self.assertEqual(score["event_terms_total"], 2)
        self.assertEqual(score["forbidden_terms_hit"], [])
        self.assertEqual(score["summary_factual"], True)
        self.assertEqual(score["comment_count"], 2)


if __name__ == "__main__":
    unittest.main()
