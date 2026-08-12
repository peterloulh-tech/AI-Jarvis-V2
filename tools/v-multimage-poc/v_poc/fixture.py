from __future__ import annotations

import hashlib
import json
import struct
import zlib
from pathlib import Path


CANVAS_WIDTH = 896
CANVAS_HEIGHT = 512
SOURCE_WIDTH = 640
SOURCE_HEIGHT = 360


def _chunk(kind: bytes, payload: bytes) -> bytes:
    body = kind + payload
    return struct.pack(">I", len(payload)) + body + struct.pack(">I", zlib.crc32(body))


def _png(rgb: bytes, width: int, height: int) -> bytes:
    rows = b"".join(
        b"\x00" + rgb[y * width * 3 : (y + 1) * width * 3] for y in range(height)
    )
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + _chunk(b"IDAT", zlib.compress(rows, 9))
        + _chunk(b"IEND", b"")
    )


def _set_pixel(pixels: bytearray, x: int, y: int, color: tuple[int, int, int]) -> None:
    if 0 <= x < CANVAS_WIDTH and 0 <= y < CANVAS_HEIGHT:
        index = (y * CANVAS_WIDTH + x) * 3
        pixels[index : index + 3] = bytes(color)


def _rect(
    pixels: bytearray,
    left: int,
    top: int,
    right: int,
    bottom: int,
    color: tuple[int, int, int],
) -> None:
    row = bytes(color) * max(0, right - left)
    for y in range(max(0, top), min(CANVAS_HEIGHT, bottom)):
        start = (y * CANVAS_WIDTH + max(0, left)) * 3
        pixels[start : start + len(row)] = row


def _circle(
    pixels: bytearray, center_x: int, center_y: int, radius: int, color: tuple[int, int, int]
) -> None:
    radius_sq = radius * radius
    for y in range(center_y - radius, center_y + radius + 1):
        for x in range(center_x - radius, center_x + radius + 1):
            if (x - center_x) ** 2 + (y - center_y) ** 2 <= radius_sq:
                _set_pixel(pixels, x, y, color)


def _frame(scene: str, frame_index: int) -> bytes:
    pixels = bytearray(bytes((18, 22, 32)) * CANVAS_WIDTH * CANVAS_HEIGHT)
    # 640x360 -> 896x504, so the common comparison canvas has 4 px top/bottom padding.
    _rect(pixels, 0, 4, CANVAS_WIDTH, 508, (30, 42, 58))
    _rect(pixels, 442, 4, 454, 508, (205, 184, 92))
    _rect(pixels, 0, 248, CANVAS_WIDTH, 260, (205, 184, 92))
    for x in (32, 864):
        _rect(pixels, x - 3, 28, x + 3, 52, (242, 242, 242))
        _rect(pixels, x - 12, 37, x + 12, 43, (242, 242, 242))

    if scene == "calm":
        _circle(pixels, 196, 360, 30, (74, 144, 226))
    elif scene == "ordinary":
        _circle(pixels, (300, 448, 596)[frame_index], 360, 30, (74, 144, 226))
    elif scene == "highlight":
        _circle(pixels, (330, 430, 510)[frame_index], 214, 34, (226, 68, 68))
        _circle(pixels, 510, 214, 58, (235, 192, 52))
        if frame_index == 2:
            for radius in (72, 88, 104):
                for degree in range(0, 360, 3):
                    radians = degree * 3.141592653589793 / 180
                    _set_pixel(
                        pixels,
                        510 + int(radius * __import__("math").cos(radians)),
                        214 + int(radius * __import__("math").sin(radians)),
                        (255, 240, 128),
                    )
    else:
        raise ValueError(f"unsupported scene: {scene}")
    return _png(bytes(pixels), CANVAS_WIDTH, CANVAS_HEIGHT)


def build_fixtures(output_dir: Path) -> dict:
    output_dir.mkdir(parents=True, exist_ok=True)
    images_dir = output_dir / "images"
    images_dir.mkdir(exist_ok=True)
    files: list[dict] = []
    image_records: dict[tuple[str, int], dict] = {}

    scale = min(CANVAS_WIDTH / SOURCE_WIDTH, CANVAS_HEIGHT / SOURCE_HEIGHT)
    scaled_width = round(SOURCE_WIDTH * scale)
    scaled_height = round(SOURCE_HEIGHT * scale)
    padding = {
        "left": (CANVAS_WIDTH - scaled_width) // 2,
        "right": CANVAS_WIDTH - scaled_width - (CANVAS_WIDTH - scaled_width) // 2,
        "top": (CANVAS_HEIGHT - scaled_height) // 2,
        "bottom": CANVAS_HEIGHT - scaled_height - (CANVAS_HEIGHT - scaled_height) // 2,
    }
    padding["total_pixels"] = CANVAS_WIDTH * CANVAS_HEIGHT - scaled_width * scaled_height

    for scene in ("calm", "ordinary", "highlight"):
        for frame_index in range(3):
            relative = f"images/{scene}-{frame_index + 1}.png"
            payload = _frame(scene, frame_index)
            (output_dir / relative).write_bytes(payload)
            digest = hashlib.sha256(payload).hexdigest()
            record = {
                "path": relative,
                "sha256": digest,
                "source": {"width": SOURCE_WIDTH, "height": SOURCE_HEIGHT},
                "scaled": {"width": scaled_width, "height": scaled_height},
                "canvas": {"width": CANVAS_WIDTH, "height": CANVAS_HEIGHT},
                "padding": padding,
                "fit": "contain-no-stretch",
                "frame_index": frame_index + 1,
            }
            image_records[(scene, frame_index)] = record
            files.append({"path": relative, "sha256": digest, "size_bytes": len(payload)})

    gold = {
        "calm": {
            "expected_emit": False,
            "expected_level": "none",
            "required_event_terms": [],
            "forbidden_event_terms": ["击杀", "胜利", "爆炸"],
        },
        "ordinary": {
            "expected_emit": True,
            "expected_level": "ordinary",
            "required_event_terms": ["蓝", "中央"],
            "forbidden_event_terms": ["胜利", "击杀"],
        },
        "highlight": {
            "expected_emit": True,
            "expected_level": "highlight",
            "required_event_terms": ["红", "目标"],
            "forbidden_event_terms": ["胜利", "击杀"],
        },
    }
    groups = []
    for scene in ("calm", "ordinary", "highlight"):
        for image_count in (1, 2, 3):
            indexes = {1: (2,), 2: (0, 2), 3: (0, 1, 2)}[image_count]
            groups.append(
                {
                    "case_id": f"{scene}-{image_count}",
                    "scene": scene,
                    "image_count": image_count,
                    "images": [image_records[(scene, index)] for index in indexes],
                    "gold": gold[scene],
                }
            )

    manifest = {
        "schema_version": 1,
        "fixture_version": "AIJARVISV2-26-synthetic-v1",
        "license": {
            "spdx": "CC0-1.0",
            "origin": "deterministically generated by this repository",
            "allowed_use": ["selection", "protocol-validation", "regression"],
            "training_allowed": False,
            "third_party_content": False,
        },
        "limitations": [
            "synthetic protocol fixture; not a League of Legends quality gold corpus",
            "single-author labels; not the required two-person production calibration",
        ],
        "files": files,
        "groups": groups,
    }
    manifest_path = output_dir / "fixture-manifest.json"
    manifest_path.write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return manifest
