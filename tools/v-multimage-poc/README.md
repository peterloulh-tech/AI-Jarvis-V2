# AIJARVISV2-26 V 多图单次结构化输出 PoC

本目录是独立 Local V 测试包。它直接启动任务 25 锁定的官方 `llama-server b10369`，不依赖或导入 O Runtime、Harness、Session、Worker，也不实现第二套 runtime。模型文件与运行时二进制不进入仓库。

## 固定 profile 与约束

`profiles.json` 固定两个独立 profile：V-C01（Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj）和 V-C02（MiniCPM-V-4.6 Q4_K_M + F16 mmproj）。每次 CLI 只能选择一个 profile；运行锁保证同一输出根目录不能同时驻留两个候选。server 命令固定 `--parallel 1`、一个 `--model`、一个 `--mmproj`，只绑定 `127.0.0.1`，请求只含本地 base64 图片。

同一确定性 CC0 合成 fixture 覆盖平静、普通、高光 × 1/2/3 图，共 9 组；每张图为 896×512 `contain-no-stretch` 对照画布。普通/高光使用 `required`，由 schema 强制 `emit=true`、事件、等级和至少一条弹幕；只有平静组使用 `allow_silence` 评价智能沉默。两个候选使用同一 prompt/schema/评分；每组一个 HTTP 请求、零格式修复和零补调用。单图只评价当前可见状态，多图才评价运动；合成 fixture 不代替尚缺的英雄联盟许可录像、双人金标或质量阈值。

## 命令

准备 fixture 与 profile plan，不需要权重：

```text
python run_v_poc.py prepare --profile V-C01 --output evidence
python run_v_poc.py prepare --profile V-C02 --output evidence
```

Windows/NVIDIA 必须使用任务 25 固定的官方 `llama-b10369-bin-win-cuda-12.4-x64.zip`（SHA-256 `5eca96bb...642642`）和 `cudart` 包（SHA-256 `8c79a9b2...ae1d6`），先在受控准备环境下载并验包，再断网执行。普通 `check/run` 只检查 runtime 路径/文件名/非零字节数，以及模型路径/锁定文件名/锁定字节数，不重算大型制品 SHA；profile 中已记录的 SHA 身份保持不变并直接复用：

```powershell
.\run-v-poc.ps1 `
  -Profile V-C01 `
  -Python C:\AIJarvisV2-26\python.exe `
  -Server C:\AIJarvisV2-26\runtime\llama-server.exe `
  -ModelsDir D:\AIJarvisModels\V-C01 `
  -OutputDir D:\AIJarvisEvidence\task26
```

仅在首次准入、制品来源/版本/字节数变化或最终测试包组装时，显式增加一次 `-FullShaPurpose initial-admission`、`changed-artifact` 或 `final-package`。该动作调用 `admit` 完整回放 SHA 并写入 `artifact-admission.json`；普通重复开发和推理不得增加此参数，也不得重新联网锁定。

V-C01 完全退出、日志出现 cleanup 且进程枚举无 `llama-server.exe` 后，才可用新的输出目录执行 V-C02。不得同时执行两个 PowerShell 会话。运行结果位于 `<OutputDir>/<profile>/evidence.json`，逐 case 原始响应位于 `cases/`，GPU 原始时序位于 `gpu-samples.jsonl`；Mac 或无 `nvidia-smi` 时硬件字段保持 `UNCONFIRMED`。

## 失败分类与停止条件

- `MALFORMED_JSON` / `SCHEMA_FIELDS` / `SCHEMA_TYPES`：JSON 或 schema 失败。
- `SILENCE_INCONSISTENT` / `EMIT_INCOMPLETE` / `SUMMARY_TOO_LONG`：业务一致性失败。
- `RUNTIME_ARTIFACT_UNAVAILABLE` / `MODEL_ARTIFACT_UNAVAILABLE`：制品缺失、文件名/字节数不符，或显式准入时 SHA 不匹配，0 次调用。
- `SERVER_OR_INFERENCE_FAILURE`：加载、HTTP 或推理失败；保留 server 日志。
- `LOCKED_MODEL_RUNTIME_CONFLICT`：锁定模型与锁定 runtime 直接冲突，不得偷换 revision。

任何失败只记录并停止；禁止 OCR、分类/摘要模型、格式修复补调用、在线核心服务或第二模型副本。当前 Mac 证据见 `evidence/macos-arm64-2026-08-12.json`：V-C01 9/9 完整契约并通过 PoC 硬门；V-C02 的 6 个 required 用例全部输出，但 3 个平静组未正确沉默，整体硬门失败。这不是 Windows/NVIDIA 或产品 PASS。
