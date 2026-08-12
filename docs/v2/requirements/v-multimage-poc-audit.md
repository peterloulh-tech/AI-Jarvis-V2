# AI Jarvis V2 V 多图 PoC 四方审计与证据

> Dashi：AIJARVISV2-26；执行日期：2026-08-12；测试包：[`tools/v-multimage-poc`](../../../tools/v-multimage-poc/)

## 正式需求与采用路线

V05/V06 与任务 26 要求同一候选对 1/2/3 图各一次推理，同时产生主要事件、普通/高光、一个风格批次、智能沉默和不超过 30 个中文字摘要；无 OCR、分类/摘要补模型、格式修复调用或在线核心。两个固定 profile 必须使用同一 fixture、896×512 等比留边、prompt/schema 和评分，且每轮只有一个服务和一份权重。

四方审计结论：官方 `llama-server b10369@6e62ba5` 的 multimodal、JSON Schema、单模型 server 和 loopback HTTP 为 `DIRECT`；原作者 V1/O 与 Task93 含 O 产品语义且不能满足 V 契约，为 `CONFLICT/DUPLICATE`，未复用；项目仅复用纯证据口径，为 `DIRECT`；V2 只新增确定性 fixture、请求/校验/评分、单 profile 进程编排和证据输出，为 `V2-ONLY`。不存在 O import/link 或共享抽象改造。依据 `DEC-ARTIFACT-INTEGRITY-01`，大型制品普通 `check/run` 仅核对路径、锁定文件名与字节数；完整 SHA 只由显式 `admit --purpose` 在准入/变化/最终组包事件执行并保存，既有 SHA/revision 锁继续复用。

## 官方/原作者复核

锁定 b10369 源码归档完成本地构建，源码确认 `general.architecture` 支持值为 `qwen3vl`，server 官方单测覆盖 JSON Schema/单图并将 multiple-images 标为 TODO。Qwen 与 MiniCPM 原作者仓库当前 HEAD 仍等于任务 25 锁定 revision；MiniCPM 4.6 官方指南确认同一 `llama-server` 的 model+mmproj 用法。首次准入阶段补齐并回放 MiniCPM 官方 GGUF SHA：Q4_K_M `6b0c7496...892e2`、F16 mmproj `ca931d86...62de`；后续重复推理不再哈希。

## Mac 动态结果与边界

在 Apple M1 Pro/32GB、锁定 b10369 Metal build 上严格顺序执行，两个候选从未同时驻留。V-C01 精确锁定文件 SHA 均通过，但 model 的 `general.architecture=Qwen3VLForConditionalGeneration`，b10369 只接受 `qwen3vl`，加载即退出，0 次调用：`LOCKED_MODEL_RUNTIME_CONFLICT/BLOCKED`。旧 main/ModelScope Qwen blob 的 architecture 不同，未偷换使用。

V-C02 首次准入 SHA 通过并完成平静/普通/高光 × 1/2/3 图共 9 次单请求。诊断发现默认 thinking 会耗尽 384 tokens；按 b10369 官方 `chat_template_kwargs.enable_thinking=false` 最小修正并 TDD 固化后，9/9 均为可解析且字段/类型完整 JSON，但完整业务契约 0/9：`EMIT_INCOMPLETE` 3、`SILENCE_INCONSISTENT` 6；emit 判断 0/9、level 判断 3/9，模型调用 9、修复调用 0。请求耗时仅作 Mac 观察值（1,738.051～4,475.192 ms），不得外推 Windows/NVIDIA。

仓库证据摘要为 [`macos-arm64-2026-08-12.json`](../../../tools/v-multimage-poc/evidence/macos-arm64-2026-08-12.json)。当前没有可通过任务 26 硬门的锁定候选；Windows/NVIDIA、8GB/12GB+、GPU/显存、真实英雄联盟许可语料、双人金标及质量阈值全部为 `UNCONFIRMED/BLOCKED`。任务 27/28 和产品开发不得开始。
