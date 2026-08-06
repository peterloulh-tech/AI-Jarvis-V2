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
- [reliability-nfr.md](reliability-nfr.md)：AIJARVISV2-4 的可靠性、故障隔离、有界等待、停止清理、单实例和长稳判定要求。
- [reliability-fault-recovery-matrix.md](reliability-fault-recovery-matrix.md)：冻结故障信号、期望动作、最大残留和验证方法矩阵。
- [reliability-test-and-record-templates.md](reliability-test-and-record-templates.md)：故障注入、4/8 小时、停止清理、异常退出和单实例记录模板。
- [windows-compatibility-nfr.md](windows-compatibility-nfr.md)：AIJARVISV2-5 的 Windows 正式支持、不承诺、明确排除和兼容质量边界。
- [windows-display-capture-matrix.md](windows-display-capture-matrix.md)：分辨率/DPI、单/多显示器、显示器/窗口采集及全屏场景矩阵。
- [windows-device-overlay-scenarios.md](windows-device-overlay-scenarios.md)：音频与显示设备变化、Overlay 可见性/点击穿透和系统事件场景。
- [windows-validation-record-templates.md](windows-validation-record-templates.md)：Windows 真机、简体中文、采集与 Overlay 执行记录模板。
- [privacy-security-nfr.md](privacy-security-nfr.md)：AIJARVISV2-6 的隐私、安全、采集权限、本机 IPC、日志脱敏与包完整性约束。
- [data-residency-and-clearing-matrix.md](data-residency-and-clearing-matrix.md)：逐类数据的来源、用途、驻留位置、上限、清除时机和导出规则。
- [threat-boundaries-and-network-behavior.md](threat-boundaries-and-network-behavior.md)：威胁边界、数据流/网络行为清单、断网/IPC/落盘/完整性验证方案。
- [diagnostic-package-minimization.md](diagnostic-package-minimization.md)：诊断包字段允许列表、始终排除项、弹幕勾选和最小化隐私矩阵。
- [privacy-security-validation-record-templates.md](privacy-security-validation-record-templates.md)：断网、原始音画落盘、生命周期、日志脱敏、诊断包和完整性记录模板。
- [offline-install-update-nfr.md](offline-install-update-nfr.md)：AIJARVISV2-7 的离线安装、仅手动更新、失败保护、卸载配置选择和版本化诊断要求。
- [package-layout-and-version-compatibility.md](package-layout-and-version-compatibility.md)：程序包/模型包/用户配置逻辑边界、发布清单、兼容判定和回退不变量。
- [update-observability-fields.md](update-observability-fields.md)：安装、更新、回退、卸载、诊断和主页面性能提示的版本化字段表。
- [offline-install-update-validation-plan.md](offline-install-update-validation-plan.md)：无需开发环境、完整离线包、断网 O/V、程序/模型更新、卸载和可观测性验证步骤与记录入口。
- [nfr-engineering-appendix-manifest-v1.0.md](nfr-engineering-appendix-manifest-v1.0.md)：AIJARVISV2-3～7 工程附录 V1.0 的文件、哈希和版本边界；不构成第二份正式 NFR。
- [nfr-stage-gate-review.md](nfr-stage-gate-review.md)：AIJARVISV2-8 的覆盖、追踪、冲突、十类硬约束和阶段出口检查。
- [nfr-open-risks-and-pending-validation.md](nfr-open-risks-and-pending-validation.md)：开放问题、CAL/AMB 待实测集合及禁止提前承诺的结论。
- [e2e-acceptance-matrix.md](e2e-acceptance-matrix.md)：AIJARVISV2-9 对候选 60 项补充的前置条件、操作、可观察结果、FR/NFR/任务追踪、24 章覆盖与范围防扩张检查。
- [o-mode-acceptance-and-benchmark-plan.md](o-mode-acceptance-and-benchmark-plan.md)：AIJARVISV2-10 对 O01～O10 补充的固定输入、专项步骤、冻结判定、O10/16GB 证据与真实缺口。
- [v-mode-acceptance-and-benchmark-plan.md](v-mode-acceptance-and-benchmark-plan.md)：AIJARVISV2-11 对 V01～V10 补充的回放输入、共享并发、候选保护、乱序/复位判定、V10 记录与真实缺口。
- [postprocessing-overlay-lifecycle-acceptance-plan.md](postprocessing-overlay-lifecycle-acceptance-plan.md)：AIJARVISV2-12 对配置锁、发送/高光路由、Overlay 显示与全生命周期补充的边界、状态、故障及清理判定。
- [replay-corpus-and-gold-format.md](replay-corpus-and-gold-format.md)：AIJARVISV2-13 定义 O/V 共用录像语料、许可脱敏、单调时间轴、事件金标、C10 评分与 4/8 小时回放编排。
- [windows-hardware-acceptance-matrix.md](windows-hardware-acceptance-matrix.md)：AIJARVISV2-14 编排 V 8/12GB、O 16GB 独占、显示/音频/系统状态、断网及英雄联盟同机真机验收组合。

任何后续工作发现候选验收与冻结需求不一致时，必须以功能冻结 V1.0、非功能冻结 V1.0 为准，并记录评审，不得直接改变范围。
