# AIJARVISV2-1 — 登记冻结需求基线并建立需求追踪矩阵

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`cfd553912de8acf35b9308cf234ccecd4c57c33b`
- 直接依赖：无

## 最终结果与关键文件

建立三基线登记、83 个功能追踪单元（覆盖24章）、14个 NFR 单元、60个候选验收项、范围排除和30个待校准项。入口为 [`baseline-manifest.md`](../../requirements/baseline-manifest.md)、[`requirements-catalog.md`](../../requirements/requirements-catalog.md) 与 [`traceability-matrix.md`](../../requirements/traceability-matrix.md)。

## 后续不得破坏的约束

功能 V1.0 是唯一功能范围，非功能 V1.0 是正式质量约束，验收 V0.1 只作候选；冲突时冻结版优先。O 硬超时保持12/16/20秒，V及明确待实测值不得擅自冻结。

## 验证与遗留

三份源文档 SHA-256、24章覆盖、ID与范围索引已静态核验；未做模型、架构或真机验证。后续只可补证据或校准允许的数值，不得扩大范围。

- 检索关键词：基线哈希，FR，NFR，AC，OOS，CAL，追踪矩阵
