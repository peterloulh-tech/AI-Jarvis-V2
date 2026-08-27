#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SOURCE_MODELS="${1:-/Users/peterlou/Downloads/AI/ai弹幕程序文件/模型文件}"
DEST="${2:-/Users/peterlou/Downloads/AI/ai弹幕程序文件/任务27-V-Windows测试包}"

test -f "$SOURCE_MODELS/Qwen3-VL-4B-Instruct-Q4_K_M/Qwen3VL-4B-Instruct-Q4_K_M.gguf"
test -f "$SOURCE_MODELS/Qwen3-VL-4B-Instruct-Q4_K_M/mmproj-Qwen3VL-4B-Instruct-Q8_0.gguf"
test -f "$SOURCE_MODELS/MiniCPM-V-4.6-Q4_K_M/MiniCPM-V-4_6-Q4_K_M.gguf"
test -f "$SOURCE_MODELS/MiniCPM-V-4.6-Q4_K_M/mmproj-model-f16.gguf"

mkdir -p "$DEST/Models/V-C01" "$DEST/Models/V-C02" "$DEST/Evidence"
cp -R "$ROOT/v_poc" "$ROOT/profiles.json" "$ROOT/run_v_poc.py" "$ROOT/run-v-poc.ps1" \
  "$ROOT/Prepare-V-Windows-Test.ps1" "$ROOT/Run-Task27-Matrix.ps1" \
  "$ROOT/README.md" "$ROOT/README-Windows-Package.md" "$DEST/"
cp "$SOURCE_MODELS/Qwen3-VL-4B-Instruct-Q4_K_M/"*.gguf "$DEST/Models/V-C01/"
cp "$SOURCE_MODELS/MiniCPM-V-4.6-Q4_K_M/"*.gguf "$DEST/Models/V-C02/"
cp "$ROOT/../../docs/v2/requirements/v-model-runtime-candidate-lock.json" "$DEST/"
cp "$ROOT/../../third_party/runtime/vendor/LICENSE" "$DEST/LICENSE-llama.cpp.txt"
cp "$ROOT/../../third_party/runtime/vendor/licenses/LICENSE-curl" "$DEST/LICENSE-curl.txt"
cp "/Users/peterlou/Downloads/AI/ai弹幕程序文件/任务93-Win数据采集测试包/AIJARVISV2-93-RUN/Models/MiniCPM-o-4_5-gguf/LICENSE.Apache-2.0.txt" "$DEST/LICENSE-Apache-2.0.txt"

# Materialize the deterministic CC0 input set so the operator can inspect it
# before running Windows. The benchmark regenerates the same bytes on demand.
mkdir -p "$DEST/Fixtures"
python3 "$DEST/run_v_poc.py" prepare --profile V-C01 --output "$DEST/Fixtures" >/dev/null

cat > "$DEST/package-manifest.json" <<EOF
{
  "schema_version": 1,
  "artifact_name": "AIJARVISV2-27-v-windows-nvidia",
  "task": "AIJARVISV2-27",
  "runtime": "llama.cpp b10369 Windows CUDA 12.4 (downloaded by Prepare-V-Windows-Test.ps1)",
  "models": ["V-C01", "V-C02"],
  "fixture": "Fixtures/fixture/images plus fixture-manifest.json (CC0 synthetic, regenerated deterministically)",
  "network": "online only for first runtime preparation; benchmark is loopback-only"
}
EOF

find "$DEST" -type f -not -path '*/Evidence/*' -not -name 'package-sha256.txt' -print0 |
  sort -z | xargs -0 shasum -a 256 > "$DEST/package-sha256.txt"
echo "Assembled package: $DEST"
du -sh "$DEST"
