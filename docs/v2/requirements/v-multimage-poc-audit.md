# AI Jarvis V2 V 多图 PoC 四方审计与证据

> Dashi：AIJARVISV2-26；执行日期：2026-08-12；测试包：[`tools/v-multimage-poc`](../../../tools/v-multimage-poc/)

## 正式需求与采用路线

V05/V06 与任务 26 要求同一候选对 1/2/3 图各一次推理，同时产生主要事件、普通/高光、一个风格批次、智能沉默和不超过 30 个中文字摘要；无 OCR、分类/摘要补模型、格式修复调用或在线核心。两个固定 profile 必须使用同一 fixture、896×512 等比留边、prompt/schema 和评分，且每轮只有一个服务和一份权重。

四方审计结论：官方 `llama-server b10369@6e62ba5` 的 multimodal、JSON Schema、单模型 server 和 loopback HTTP 为 `DIRECT`；原作者 V1/O 与 Task93 含 O 产品语义且不能满足 V 契约，为 `CONFLICT/DUPLICATE`，未复用；项目仅复用纯证据口径，为 `DIRECT`；V2 只新增确定性 fixture、请求/校验/评分、单 profile 进程编排和证据输出，为 `V2-ONLY`。不存在 O import/link 或共享抽象改造。依据 `DEC-ARTIFACT-INTEGRITY-01`，大型制品普通 `check/run` 仅核对路径、锁定文件名与字节数；完整 SHA 只由显式 `admit --purpose` 在准入/变化/最终组包事件执行并保存，既有 SHA/revision 锁继续复用。

## 官方/原作者复核

锁定 b10369 源码归档完成本地构建，源码确认 `general.architecture` 支持值为 `qwen3vl`，server 官方单测覆盖 JSON Schema/单图并将 multiple-images 标为 TODO。Qwen 与 MiniCPM 原作者仓库当前 HEAD 仍等于任务 25 锁定 revision；MiniCPM 4.6 官方指南确认同一 `llama-server` 的 model+mmproj 用法。首次准入阶段补齐并回放 MiniCPM 官方 GGUF SHA：Q4_K_M `6b0c7496...892e2`、F16 mmproj `ca931d86...62de`；后续重复推理不再哈希。

## Mac 动态结果与边界

在 Apple M1 Pro/32GB、锁定 b10369 Metal build 上严格顺序执行，两个候选从未同时驻留。首轮发现 Qwen 官方 metadata-only commit `594171a` 把 GGUF architecture 改成 b10369 不识别的 `Qwen3VLForConditionalGeneration`。经用户批准回退到同一官方模型、同一 Q4_K_M 的前一官方文件 `1cd86af`（`qwen3vl`，SHA `66358c...a0a`），以 `changed-artifact` 准入一次后成功加载；未修改模型或 runtime。

测试契约按真实产品开关分为两个单次请求模式：普通/高光 `required` 强制输出，平静 `allow_silence` 才允许智能沉默。V-C02 首轮失败的根因不是 runtime 或权重损坏，而是生成顺序与 fixture 边界：模型在理解场景前先生成 `emit=true`，旧平静图又保留了可被视作事件的蓝点。最小修正把 `level` 调到首字段、把静默/发言定义成两个完整互斥 schema 分支、清除平静图主体，并要求主要事件包含可见主体及具体动作/状态且拒绝占位词；没有增加模型调用或第二模型。

2026-08-13 在同一 Apple M1 Pro/32GB、同一锁定 b10369 Metal build 上严格顺序重跑两个 profile。V-C01 与 V-C02 的 JSON/schema、完整契约、emit、level 均 9/9，required 各 6/6、智能沉默各 3/3，每个 profile 模型调用 9、修复 0，PoC 硬门均为 `PASS`。V-C01 的 1/2/3 图平均请求耗时为 4050.543/3930.061/5643.466 ms，V-C02 为 2021.204/3260.302/4489.143 ms；只作本机相对观察。原始输出复核未见占位事件。

仓库保留[首轮证据](../../../tools/v-multimage-poc/evidence/macos-arm64-2026-08-12.json)和[修正证据](../../../tools/v-multimage-poc/evidence/macos-arm64-2026-08-13.json)。Windows/NVIDIA、8GB/12GB+、GPU/显存、真实英雄联盟许可语料、双人金标及质量阈值仍为 `UNCONFIRMED/BLOCKED`，不得把 Mac 结果外推为真机或产品 PASS。
