# AIJARVISV2-8 — 合并并评审非功能需求基线

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`80d14695b7c207e1ba534c1d2674a15c9486b75f`；评审收口 `b433f9dbfac5c074086a8d84ce73693670a3bd89`
- 直接依赖：[3](AIJARVISV2-3.md)、[4](AIJARVISV2-4.md)、[5](AIJARVISV2-5.md)、[6](AIJARVISV2-6.md)、[7](AIJARVISV2-7.md)

## 最终结果与关键文件

冻结任务3～7的25个工程附录哈希，补齐65条 NFR 追踪和十类硬约束出口；用户批准阶段门及卸载策略。入口为[附录清单](../../requirements/nfr-engineering-appendix-manifest-v1.0.md)、[阶段评审](../../requirements/nfr-stage-gate-review.md)与[风险清单](../../requirements/nfr-open-risks-and-pending-validation.md)。

## 后续不得破坏的约束

正式 NFR V1.0仍是唯一质量基线；工程附录不是第二份 NFR。冻结哈希、追踪、硬约束和待实测状态不得破坏；卸载策略见 [`DECISIONS.md`](../DECISIONS.md)。

## 验证与遗留

25/25哈希、ID、链接、CSV、追踪和差异范围已静态核验。真机、4h/8h、断网、故障、点击穿透、隐私和安装卸载仍待实测。

- 检索关键词：NFR-ENG-APPENDIX-V1.0，阶段门，十类硬约束，开放风险，卸载策略
