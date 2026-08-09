# AIJARVISV2-92 — O Reference Harness v2 重建与离线验证

- 状态：`in_review`（Dashi 回读日期：2026-08-10）
- 交付提交：`592f197c7b377d72d66d8af69a12d973b650bd51`
- 直接依赖：AIJARVISV2-23

## 最终结果与关键文件

已建立独立于正式 Product Adapter 的薄 Reference Harness，直接使用 Locked `llama.cpp-omni` C API，只承担参数/资源安全、原始结果暴露和测试 instrumentation。[`README.md`](../../../../tools/o-reference-harness-v2/README.md) 定义 `official-runtime-reference` 与 `v2-contract` 两个分离 profile、真实 runtime boundary 与 payload completion 分层、Legacy 文件级复用边界及 Windows 动态入口；源码、固定 fixture、manifest、runner/package 和手动 workflow 均位于 `tools/o-reference-harness-v2/` 及 `.github/workflows/aijarvisv2-92-reference-harness.yml`。

## 后续不得破坏的约束

Harness 只建立 Locked model/runtime 行为参考，不实现产品状态机、IPC、Worker、Overlay 或正式 Product Adapter。不得伪造官方 EOS；原始 fragment 必须逐条保留，业务 JSON 仅在 aggregation 后判定。官方 runtime 正常与 V2 三人设三批契约必须分别归因。cadence 由 profile/manifest 驱动，不得恢复 3 秒/11 块专用逻辑。

## 验证与遗留

零 GPU 套件通过 6 个 core、4 个 CLI、3 个 fixture、runner contract、并发 input/result 关联，以及 2 profile × 2 cadence dry-run；验证 33×1 秒与 11×3 秒输入、PCM/marker/vision/SHA-256、真实四 fragment 未完成前缀、完整三批、boundary/failure/timeout/order。Locked 头文件语法检查通过，`git diff --check` 通过。新增 binary，故为 `BUILD_REQUIRED`；Windows/MSVC/CUDA 构建、便携包、模型加载、动态 LISTEN/SPEAK/fragment/latency/VRAM/cleanup 均为 `DYNAMIC-ONLY`，只由 AIJARVISV2-93 验收。

- 检索关键词：Reference Harness v2、official-runtime-reference、v2-contract、runtime boundary、payload complete、legacy replay、AIJARVISV2-93
