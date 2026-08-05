# AI Jarvis V2 需求基线与追踪

本目录是 AI Jarvis V2 冻结需求基线、追踪关系和统一非功能度量框架的入口。

- [baseline-manifest.md](baseline-manifest.md)：三份文档、哈希、状态、优先级、冲突规则及 upstream 基线。
- [requirements-catalog.md](requirements-catalog.md)：统一的 FR/NFR/AC 稳定编号目录与 24 章覆盖。
- [traceability-matrix.md](traceability-matrix.md)：需求到后续 Dashi 任务以及任务到需求选择器的双向追踪。
- [scope-exclusions.md](scope-exclusions.md)：第一版明确排除与全文禁止项索引。
- [calibration-register.md](calibration-register.md)：仍需模型、回放或 Windows 真机实测的项目。
- [nfr-metrics-framework.md](nfr-metrics-framework.md)：AIJARVISV2-2 建立的统一度量词汇、P50/P95 规则和 39 个可测量指标定义。
- [nfr-measurement-points.md](nfr-measurement-points.md)：统一时点、最小日志字段、采样分组和隐私边界。
- [nfr-classification-and-traceability.md](nfr-classification-and-traceability.md)：NFR 硬要求/工程目标分类、冻结值、候选验收和后续任务映射。
- [performance-nfr.md](performance-nfr.md)：AIJARVISV2-3 的性能、资源与端到端时效可测约束及对外承诺边界。
- [performance-benchmark-scenarios.md](performance-benchmark-scenarios.md)：第 23.2 节逐项基准场景、输入、测量点和统计口径。
- [performance-record-templates.md](performance-record-templates.md)：P1 性能数据、4/8 小时资源趋势和端到端阶段记录模板。

任何后续工作发现候选验收与冻结需求不一致时，必须以功能冻结 V1.0、非功能冻结 V1.0 为准，并记录评审，不得直接改变范围。
