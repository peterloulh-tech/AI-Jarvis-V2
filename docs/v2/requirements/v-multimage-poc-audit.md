# AI Jarvis V2 V 多图 PoC 四方审计与证据

> Dashi：AIJARVISV2-26；执行日期：2026-08-12；测试包：[`tools/v-multimage-poc`](../../../tools/v-multimage-poc/)

## 正式需求与采用路线

V05/V06 与任务 26 要求同一候选对 1/2/3 图各一次推理，同时产生主要事件、普通/高光、一个风格批次、智能沉默和不超过 30 个中文字摘要；无 OCR、分类/摘要补模型、格式修复调用或在线核心。两个固定 profile 必须使用同一 fixture、896×512 等比留边、prompt/schema 和评分，且每轮只有一个服务和一份权重。

四方审计结论：官方 `llama-server b10369@6e62ba5` 的 multimodal、JSON Schema、单模型 server 和 loopback HTTP 为 `DIRECT`；原作者 V1/O 与 Task93 含 O 产品语义且不能满足 V 契约，为 `CONFLICT/DUPLICATE`，未复用；项目仅复用纯证据口径，为 `DIRECT`；V2 只新增确定性 fixture、请求/校验/评分、单 profile 进程编排和证据输出，为 `V2-ONLY`。不存在 O import/link 或共享抽象改造。依据 `DEC-ARTIFACT-INTEGRITY-01`，大型制品普通 `check/run` 仅核对路径、锁定文件名与字节数；完整 SHA 只由显式 `admit --purpose` 在准入/变化/最终组包事件执行并保存，既有 SHA/revision 锁继续复用。

## 官方/原作者复核

锁定 b10369 源码归档完成本地构建，源码确认 `general.architecture` 支持值为 `qwen3vl`，server 官方单测覆盖 JSON Schema/单图并将 multiple-images 标为 TODO。Qwen 与 MiniCPM 原作者仓库当前 HEAD 仍等于任务 25 锁定 revision；MiniCPM 4.6 官方指南确认同一 `llama-server` 的 model+mmproj 用法。首次准入阶段补齐并回放 MiniCPM 官方 GGUF SHA：Q4_K_M `6b0c7496...892e2`、F16 mmproj `ca931d86...62de`；后续重复推理不再哈希。

## Mac 动态结果与边界

在 Apple M1 Pro/32GB、锁定 b10369 Metal build 上严格顺序执行，两个候选从未同时驻留。首轮发现 Qwen 官方 metadata-only commit `594171a` 把 GGUF architecture 改成 b10369 不识别的 `Qwen3VLForConditionalGeneration`。经用户批准回退到同一官方模型、同一 Q4_K_M 的前一官方文件 `1cd86af`（`qwen3vl`，SHA `66358c...a0a`），以 `changed-artifact` 准入一次后成功加载；未修改模型或 runtime。

测试契约按真实产品开关分为两个单次请求模式：普通/高光 `required` 强制输出，平静 `allow_silence` 才允许智能沉默；schema 同时强制 required 分支的 `emit=true`、非空 event、ordinary/highlight 与至少一条 comment。fixture 修正单图不评价运动、红色高光主体不可被目标遮挡。V-C01 为 JSON/schema 9/9、完整契约 9/9、emit/level 均 9/9，模型调用 9、修复 0，PoC 硬门 `PASS`；1/2/3 图平均请求耗时分别为 3345.090/3391.228/5012.569 ms。V-C02 为 JSON/schema 9/9；6 个 required 用例完整有效，但 3 个 allow-silence 平静用例均错误 emit，完整契约 6/9，硬门 `FAIL`；1/2/3 图平均为 1782.794/2935.326/4109.590 ms。耗时只作本机相对成本观察。这证明主动要求输出有效，也证明 MiniCPM 的智能沉默仍不可靠。

仓库证据摘要为 [`macos-arm64-2026-08-12.json`](../../../tools/v-multimage-poc/evidence/macos-arm64-2026-08-12.json)。V-C01 已通过任务 26 的 Mac 功能 PoC 硬门；V-C02 未通过。Windows/NVIDIA、8GB/12GB+、GPU/显存、真实英雄联盟许可语料、双人金标及质量阈值仍为 `UNCONFIRMED/BLOCKED`，不得把 Mac 结果外推为真机或产品 PASS。
