# AIJARVISV2-25 — 筛选 V 模型与运行时候选

- 状态：`in_review`（Dashi 于 2026-08-12 回读）
- 交付提交：`244c63f6792f8f421b268aa2c645b938067ed53b`；状态收口提交见本任务后续 Git 记录
- 直接依赖：[AIJARVISV2-21](AIJARVISV2-21.md)

## 最终结果与关键文件

新增 [V 候选筛选](../../requirements/v-model-runtime-candidate-screening.md)与 [revision lock](../../requirements/v-model-runtime-candidate-lock.json)。经用户复核，锁定两个测试候选：`V-C01` 为 Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj，`V-C02` 为 MiniCPM-V-4.6 Q4_K_M + F16 mmproj；二者复用同一 `llama-server b10369`，分别代表质量/综合能力与低资源/效率路线。当前不指定最终产品模型。

## 后续不得破坏的约束

任务 26 的同一测试包必须包含两个独立 profile，并以相同 fixture、输入分组、prompt/schema 和评分口径分别实测；每轮仍只有一个服务、一份权重，不得同时加载两个候选或以多进程/多模型副本伪装并发。1～3 图每组一次推理，同时完成事件、普通/高光、一个风格批次、智能沉默和 ≤30 中文字摘要；禁止 OCR、额外分类/摘要模型、补调用及在线核心服务。任务 27 对任务 26 通过硬门的候选分别测 1～3 slots；最终唯一产品模型由任务 29 基于实测证据冻结。Task93 O 路线保持独立。

## 验证与遗留

已静态复核固定 revision、release digest、server 源码、模型卡和许可证；未执行 Windows/NVIDIA、8/12GB、1～3 图、结构质量、乱序、取消、复位、延迟、吞吐、长稳、完整离线包或再分发许可回放，全部留给任务 26/27 及后续发布门。

- 检索关键词：V-C01，V-C02，Qwen3-VL-4B，MiniCPM-V-4.6，llama-server，A/B，shared slots，multi-image，JSON Schema，8GB/12GB
