# AIJARVISV2-25 — 筛选 V 模型与运行时候选

- 状态：`done`（用户于 2026-08-12 明确验收，Dashi 同轮收口）
- 交付提交：`244c63f6792f8f421b268aa2c645b938067ed53b`；双候选决定 `9cffc94fcac39f27db11cc45618d2d164bf2894f`；V/O 隔离规则 `568b319e0b9f85373f154828a2c06d576e900a26`
- 直接依赖：[AIJARVISV2-21](AIJARVISV2-21.md)

## 最终结果与关键文件

新增 [V 候选筛选](../../requirements/v-model-runtime-candidate-screening.md)与 [revision lock](../../requirements/v-model-runtime-candidate-lock.json)。经用户复核，锁定两个测试候选：`V-C01` 为 Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj，`V-C02` 为 MiniCPM-V-4.6 Q4_K_M + F16 mmproj；二者复用同一 `llama-server b10369`。任务 26 动态纠正 V-C01 精确 GGUF 为同一官方模型的 `1cd86af...`（`qwen3vl`），候选方向不变。当前不指定最终产品模型。

## 后续不得破坏的约束

任务 26 的同一测试包必须包含两个独立 profile，并以相同 fixture、输入分组、prompt/schema 和评分口径分别实测；每轮仍只有一个服务、一份权重，不得同时加载两个候选或以多进程/多模型副本伪装并发。1～3 图每组一次推理，同时完成事件、普通/高光、一个风格批次、智能沉默和 ≤30 中文字摘要；禁止 OCR、额外分类/摘要模型、补调用及在线核心服务。任务 27 对任务 26 通过硬门的候选分别测 1～3 slots；最终唯一产品模型由任务 29 基于实测证据冻结。Task93 O 路线保持独立。

## 验证与遗留

已静态复核固定 revision、release digest、server 源码、模型卡和许可证；任务 26 已在 Mac/Metal 动态回放两个 profile：V-C01 通过功能硬门，V-C02 因智能沉默失败而停止。Windows/NVIDIA、8/12GB、真实语料质量、乱序、取消、复位、吞吐、长稳、完整离线包或再分发许可回放仍留给后续任务与发布门。

- 检索关键词：V-C01，V-C02，Qwen3-VL-4B，MiniCPM-V-4.6，llama-server，A/B，shared slots，multi-image，JSON Schema，8GB/12GB
