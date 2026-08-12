import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.contract import schema_for_mode  # noqa: E402
from v_poc.profiles import load_profiles, plan_profile  # noqa: E402
from v_poc.report import summarize_run, write_blocked_evidence  # noqa: E402


class ProfileTests(unittest.TestCase):
    def test_two_profiles_share_runtime_cases_prompt_and_score_contract(self) -> None:
        profiles = load_profiles(ROOT / "profiles.json")
        self.assertEqual(set(profiles), {"V-C01", "V-C02"})
        first = plan_profile(profiles["V-C01"])
        second = plan_profile(profiles["V-C02"])
        self.assertEqual(first["runtime"], second["runtime"])
        self.assertEqual(first["cases"], second["cases"])
        self.assertEqual(first["request_contract"], second["request_contract"])
        self.assertEqual(first["request_contract"]["prompt_version"], "AIJARVISV2-26-zh-CN-v3")
        self.assertEqual(
            first["request_contract"]["schemas"]["required"],
            schema_for_mode("required"),
        )
        self.assertEqual(
            first["request_contract"]["schemas"]["allow_silence"],
            schema_for_mode("allow_silence"),
        )
        self.assertEqual(first["canvas"], {"width": 896, "height": 512, "fit": "contain-no-stretch"})
        self.assertEqual(len(first["cases"]), 9)
        modes = {case["scene"]: case["output_mode"] for case in first["cases"]}
        self.assertEqual(modes, {"calm": "allow_silence", "ordinary": "required", "highlight": "required"})
        self.assertEqual(first["server_instances"], 1)
        self.assertEqual(first["weight_instances"], 1)
        self.assertEqual(first["parallel_slots"], 1)
        self.assertNotEqual(first["artifacts"], second["artifacts"])
        for profile in profiles.values():
            for artifact in profile["artifacts"]:
                self.assertRegex(artifact["sha256"], r"^[0-9a-f]{64}$")

    def test_missing_hardware_or_artifacts_writes_blocked_not_pass(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "blocked.json"
            evidence = write_blocked_evidence(
                output,
                profile_id="V-C01",
                failure_class="MODEL_ARTIFACT_UNAVAILABLE",
                detail="model missing",
                platform_name="macOS-arm64",
            )
            self.assertEqual(evidence["conclusion"], "BLOCKED")
            self.assertEqual(evidence["windows_nvidia"], "UNCONFIRMED")
            self.assertEqual(evidence["vram_8gb"], "UNCONFIRMED")
            self.assertEqual(evidence["vram_12gb_plus"], "UNCONFIRMED")
            self.assertEqual(json.loads(output.read_text(encoding="utf-8")), evidence)

    def test_summary_keeps_profiles_separate_and_counts_structure(self) -> None:
        results = [
            {"case_id": "calm-1", "image_count": 1, "validation": {"classification": "VALID", "syntax_schema_valid": True}, "score": {"emit_correct": True, "level_correct": True}},
            {"case_id": "ordinary-2", "image_count": 2, "validation": {"classification": "MALFORMED_JSON", "syntax_schema_valid": False}, "score": None},
            {"case_id": "highlight-3", "image_count": 3, "validation": {"classification": "VALID", "syntax_schema_valid": True}, "score": {"emit_correct": True, "level_correct": False}},
        ]
        summary = summarize_run("V-C02", results)
        self.assertEqual(summary["profile_id"], "V-C02")
        self.assertEqual(summary["cases_total"], 3)
        self.assertEqual(summary["syntax_schema_valid"], {"numerator": 2, "denominator": 3})
        self.assertEqual(summary["contract_valid"], {"numerator": 2, "denominator": 3})
        self.assertEqual(summary["by_image_count"]["2"]["failure_classes"], {"MALFORMED_JSON": 1})
        self.assertEqual(summary["by_image_count"]["1"]["syntax_schema_valid"], 1)
        self.assertEqual(summary["by_image_count"]["1"]["contract_valid"], 1)
        self.assertEqual(summary["level_correct"], {"numerator": 1, "denominator": 2})
        self.assertEqual(summary["hard_gate"], "FAIL")
        self.assertEqual(summary["quality_threshold"], "PENDING_CALIBRATION")

    def test_hard_gate_rejects_structurally_valid_but_wrong_decisions(self) -> None:
        results = [
            {
                "case_id": "calm-1",
                "image_count": 1,
                "validation": {
                    "classification": "VALID",
                    "syntax_schema_valid": True,
                },
                "score": {"emit_correct": False, "level_correct": False},
            }
        ]

        summary = summarize_run("V-C01", results)

        self.assertEqual(summary["contract_valid"], {"numerator": 1, "denominator": 1})
        self.assertEqual(summary["emit_correct"], {"numerator": 0, "denominator": 1})
        self.assertEqual(summary["level_correct"], {"numerator": 0, "denominator": 1})
        self.assertEqual(summary["hard_gate"], "FAIL")


if __name__ == "__main__":
    unittest.main()
