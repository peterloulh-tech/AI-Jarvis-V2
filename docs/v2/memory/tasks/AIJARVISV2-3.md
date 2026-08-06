# AIJARVISV2-3 — 编写性能、资源与端到端时效非功能需求

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`898c0d9d6bf18b2aaf41c4d40650fd03c7afcda0`
- 直接依赖：[AIJARVISV2-2](AIJARVISV2-2.md)

## 最终结果与关键文件

形成13条性能 NFR、23个基准场景及性能/资源记录模板，覆盖 O 16GB独占、V 8/12GB与1～3路、225/350/500字预算、全链路时效及4h/8h资源趋势。入口为 [`performance-nfr.md`](../../requirements/performance-nfr.md)、[`performance-benchmark-scenarios.md`](../../requirements/performance-benchmark-scenarios.md) 与 [`performance-record-templates.md`](../../requirements/performance-record-templates.md)。

## 后续不得破坏的约束

O/V硬件表述和 O 12/16/20秒为冻结边界；8h只属内部目标。不得在无数据时承诺加载、首弹幕、P50/P95、吞吐、资源峰值或高负载游戏能力。

## 验证与遗留

链接、ID、CAL覆盖、表格与CSV字段、差异白名单均已静态核验。所有性能数值仍需最终模型、量化、运行时和 Windows 真机数据收口。

- 检索关键词：PERF-NFR，BENCH，O 16GB，V 8GB，V 12GB，4h，8h
