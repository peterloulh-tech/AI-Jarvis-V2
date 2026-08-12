import json
import struct
import sys
import tempfile
import unittest
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from v_poc.fixture import build_fixtures  # noqa: E402


def png_size(path: Path) -> tuple[int, int]:
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise AssertionError(f"not a PNG: {path}")
    return struct.unpack(">II", data[16:24])


def png_pixel(path: Path, x: int, y: int) -> tuple[int, int, int]:
    data = path.read_bytes()
    offset = 8
    compressed = bytearray()
    while offset < len(data):
        length = struct.unpack(">I", data[offset : offset + 4])[0]
        kind = data[offset + 4 : offset + 8]
        if kind == b"IDAT":
            compressed.extend(data[offset + 8 : offset + 8 + length])
        offset += 12 + length
    raw = zlib.decompress(bytes(compressed))
    row_size = 1 + 896 * 3
    index = y * row_size + 1 + x * 3
    return tuple(raw[index : index + 3])


class FixtureTests(unittest.TestCase):
    def test_builds_deterministic_1_2_3_image_groups_on_common_canvas(self) -> None:
        with tempfile.TemporaryDirectory() as first, tempfile.TemporaryDirectory() as second:
            first_manifest = build_fixtures(Path(first))
            second_manifest = build_fixtures(Path(second))

            self.assertEqual(first_manifest, second_manifest)
            self.assertEqual(first_manifest["fixture_version"], "AIJARVISV2-26-synthetic-v3")
            groups = first_manifest["groups"]
            self.assertEqual(len(groups), 9)
            self.assertEqual(
                {(group["scene"], group["image_count"]) for group in groups},
                {(scene, count) for scene in ("calm", "ordinary", "highlight") for count in (1, 2, 3)},
            )
            for group in groups:
                self.assertEqual(len(group["images"]), group["image_count"])
                self.assertEqual(
                    group["output_mode"],
                    "allow_silence" if group["scene"] == "calm" else "required",
                )
                if group["image_count"] == 1:
                    self.assertNotIn("移动", group["gold"]["required_event_terms"])
                    self.assertNotIn("中央", group["gold"]["required_event_terms"])
                for image in group["images"]:
                    path = Path(first) / image["path"]
                    self.assertEqual(png_size(path), (896, 512))
                    self.assertEqual(image["canvas"], {"width": 896, "height": 512})
                    self.assertGreater(image["padding"]["total_pixels"], 0)
                    self.assertEqual(image["sha256"], next(
                        item["sha256"] for item in first_manifest["files"] if item["path"] == image["path"]
                    ))

            on_disk = json.loads((Path(first) / "fixture-manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(on_disk, first_manifest)
            self.assertEqual(first_manifest["license"]["third_party_content"], False)

            self.assertEqual(
                png_pixel(Path(first) / "images/calm-1.png", 196, 360),
                (30, 42, 58),
            )
            self.assertEqual(
                png_pixel(Path(first) / "images/ordinary-3.png", 596, 360),
                (74, 144, 226),
            )

    def test_png_payloads_are_valid_zlib_streams(self) -> None:
        with tempfile.TemporaryDirectory() as output:
            manifest = build_fixtures(Path(output))
            sample = Path(output) / manifest["files"][0]["path"]
            data = sample.read_bytes()
            offset = 8
            compressed = bytearray()
            while offset < len(data):
                length = struct.unpack(">I", data[offset : offset + 4])[0]
                kind = data[offset + 4 : offset + 8]
                payload = data[offset + 8 : offset + 8 + length]
                if kind == b"IDAT":
                    compressed.extend(payload)
                offset += 12 + length
            raw = zlib.decompress(bytes(compressed))
            self.assertEqual(len(raw), 512 * (1 + 896 * 3))


if __name__ == "__main__":
    unittest.main()
