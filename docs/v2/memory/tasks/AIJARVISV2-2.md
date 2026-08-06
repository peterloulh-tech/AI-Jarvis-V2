# AIJARVISV2-2 — 定义非功能需求框架与统一度量词汇

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`a2258691720ee503b67895b9b21e1d89d4f07035`
- 直接依赖：[AIJARVISV2-1](AIJARVISV2-1.md)

## 最终结果与关键文件

统一40个度量词汇、39个指标和24个逻辑测量点，固定时间点、字段、分组、P50/P95 nearest-rank 与待实测管理。关键文件为 [`nfr-metrics-framework.md`](../../requirements/nfr-metrics-framework.md)、[`nfr-measurement-points.md`](../../requirements/nfr-measurement-points.md) 和 [`nfr-classification-and-traceability.md`](../../requirements/nfr-classification-and-traceability.md)。

## 后续不得破坏的约束

同一指标只能有一套定义、起止点和统计算法；硬要求、工程目标与待校准门槛必须分开。Windows 11/NVIDIA、4h P0、8h内部目标和 O 12/16/20秒保持冻结。

## 验证与遗留

ID唯一性、指标字段完整性和30个 CAL 覆盖已核验。加载、首弹幕、端到端、资源、恢复及 V 超时等门槛仍待模型和真机实测。

- 检索关键词：TERM，MET，MP，P50，P95，nearest-rank，测量点
