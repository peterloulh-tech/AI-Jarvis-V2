# AIJARVISV2-25 — 筛选 V 模型与运行时候选

- 状态：`in_progress`（Dashi 于 2026-08-12 回读；本轮完成证据评论后移至 `in_review`）
- 交付提交：待本轮提交后回填
- 直接依赖：[AIJARVISV2-21](AIJARVISV2-21.md)

## 最终结果与关键文件

新增 [V 候选筛选](../../requirements/v-model-runtime-candidate-screening.md)与 [revision lock](../../requirements/v-model-runtime-candidate-lock.json)。推荐 `V-C01`：Qwen3-VL-4B-Instruct Q4_K_M、Q8 mmproj 与 `llama-server b10369`；它直接复用官方单模型 inference mode、共享 slots、multimodal、JSON Schema 和 Windows CUDA release。MiniCPM-V-4.6 因低资源但复杂中文质量风险保持 `HOLD`。

## 后续不得破坏的约束

任务 26 只先验证 V-C01；一个服务、一份权重、1～3 slot，不得以多进程/多模型副本伪装并发。1～3 图每组一次推理，同时完成事件、普通/高光、一个风格批次、智能沉默和 ≤30 中文字摘要；禁止 OCR、额外分类/摘要模型、补调用及在线核心服务。Task93 O 路线保持独立。

## 验证与遗留

已静态复核固定 revision、release digest、server 源码、模型卡和许可证；未执行 Windows/NVIDIA、8/12GB、1～3 图、结构质量、乱序、取消、复位、延迟、吞吐、长稳、完整离线包或再分发许可回放，全部留给任务 26/27 及后续发布门。

- 检索关键词：V-C01，Qwen3-VL-4B，llama-server，shared slots，multi-image，JSON Schema，8GB/12GB
