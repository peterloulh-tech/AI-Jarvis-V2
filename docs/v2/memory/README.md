# AI Jarvis V2 项目记忆

本目录是面向新 Codex 会话的轻量摘要索引，不是任务系统、需求基线或测试证据仓库。目标是让新会话以最少上下文恢复当前项目事实，再按需进入真实来源。

## 事实来源

| 内容 | 权威来源 | 记忆的作用 |
|---|---|---|
| 任务状态、描述、依赖、评论 | Dashi 项目 `ai-jarvis-v2` | 保存短摘要和入口 |
| 交付内容 | Git 提交与实际文件 | 标记最终提交和关键文件 |
| 验证结果 | Git 提交与差异、实际文件、可复核测试记录 | 摘录边界并链接证据；Dashi 评论只作线索 |
| 跨任务用户决定 | 用户明确决定及批准记录 | 在 `DECISIONS.md` 固化 |

发生冲突时，以对应权威来源为准并修正记忆。历史交付物中的状态句只代表当时快照，不能替代 Dashi 当前状态。

## 最小读取路径

任务启动时先读仓库 `AGENTS.md`、[`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)、当前 Dashi 任务及相关评论和任务明确列出的直接依赖，再根据编号、链接或实际需要读取命中的少量任务卡、需求文件和代码。

已知当前任务编号、直接依赖和相关文件时，不必读取本索引。需要查找历史任务、定位来源、按关键词寻找摘要，或当前任务缺少明确依赖时才读取本索引；命中后只打开少量相关任务卡，不批量读取全部任务卡。

任务进入 `in_review` 时，用 [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md) 创建或更新卡片；用户正式通过后只更新状态等必要字段。跨任务决定才进入 [`DECISIONS.md`](DECISIONS.md)。

## 文件职责

- [`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)：当前有效阶段、冻结基线、公共约定、开放风险和下一步注意事项。
- [`DECISIONS.md`](DECISIONS.md)：已批准且会约束多个后续任务的决定。
- [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md)：唯一任务卡模板。
- [`tasks/`](tasks/)：只收录已进入 `in_review` 或 `done` 的真实任务。

## 已收录任务

| 任务编号 | 模块 | 状态 | 稳定关键词 | 一句话摘要 | 任务卡路径 |
|---|---|---|---|---|---|
| AIJARVISV2-1 | 需求基线 | `done` | 基线哈希、追踪矩阵、FR/NFR、AC/CAL | 登记并冻结需求基线，建立覆盖功能、非功能、候选验收与范围项的统一追踪矩阵。 | [tasks/AIJARVISV2-1.md](tasks/AIJARVISV2-1.md) |
| AIJARVISV2-2 | 度量框架 | `done` | 统一度量、TERM/MET/MP、P50/P95、测量点 | 统一非功能度量词汇、指标、测量点和分位统计口径，为后续验收提供一致基准。 | [tasks/AIJARVISV2-2.md](tasks/AIJARVISV2-2.md) |
| AIJARVISV2-3 | 性能与资源 | `done` | PERF-NFR、基准场景、资源趋势、真机校准 | 形成性能、资源与端到端时效要求及基准场景，明确真机数据校准和承诺边界。 | [tasks/AIJARVISV2-3.md](tasks/AIJARVISV2-3.md) |
| AIJARVISV2-4 | 可靠性与恢复 | `done` | REL-NFR、故障隔离、有界等待、停止清理 | 形成可靠性、故障恢复和长时间运行要求，统一故障及运行状态记录入口。 | [tasks/AIJARVISV2-4.md](tasks/AIJARVISV2-4.md) |
| AIJARVISV2-5 | Windows 兼容 | `done` | Windows 11、NVIDIA、DPI、Overlay | 形成 Windows、采集与 Overlay 兼容要求，覆盖显示缩放、设备和系统事件场景。 | [tasks/AIJARVISV2-5.md](tasks/AIJARVISV2-5.md) |
| AIJARVISV2-6 | 隐私与安全 | `done` | 数据驻留、原始音画、断网、诊断包 | 形成隐私安全与数据生命周期要求，明确离线、落盘、清除和诊断包处理边界。 | [tasks/AIJARVISV2-6.md](tasks/AIJARVISV2-6.md) |
| AIJARVISV2-7 | 安装更新与可观测性 | `done` | 离线包、手动更新、兼容回退、卸载 | 定义离线安装、包分离、手动更新、兼容回退、卸载和可观测字段规范。 | [tasks/AIJARVISV2-7.md](tasks/AIJARVISV2-7.md) |
| AIJARVISV2-8 | NFR 阶段门 | `done` | 工程附录、阶段门、硬约束、开放风险 | 冻结非功能工程附录并完成阶段门评审，统一硬约束、开放风险与卸载决定。 | [tasks/AIJARVISV2-8.md](tasks/AIJARVISV2-8.md) |
| AIJARVISV2-9 | 端到端验收 | `done` | 验收矩阵、P0/P1、证据通道、范围追踪 | 建立冻结功能的端到端验收矩阵，覆盖全量候选项、追踪范围和证据通道。 | [tasks/AIJARVISV2-9.md](tasks/AIJARVISV2-9.md) |
| AIJARVISV2-10 | O 模式验收 | `done` | O01～O10、O-IN、硬超时、16GB | 建立 O 模式专项验收与性能基准方案，覆盖输入、超时、稳定及恢复判定。 | [tasks/AIJARVISV2-10.md](tasks/AIJARVISV2-10.md) |
| AIJARVISV2-11 | V 模式验收 | `done` | V01～V10、候选保护、共享权重、全局复位 | 建立 V 模式专项验收与性能基准方案，覆盖回放输入、共享并发和复位判定。 | [tasks/AIJARVISV2-11.md](tasks/AIJARVISV2-11.md) |
| AIJARVISV2-12 | 后处理与生命周期验收 | `done` | 配置锁、有界队列、Overlay、停止清理 | 建立发送、Overlay 与运行生命周期专项方案，覆盖边界、路由、显示、故障和资源清理。 | [tasks/AIJARVISV2-12.md](tasks/AIJARVISV2-12.md) |
| AIJARVISV2-13 | 回放语料与金标 | `done` | 许可脱敏、单调时间轴、事件金标、C10 | 定义 O/V 共用回放语料、许可审计、金标评分和 4/8 小时编排格式。 | [tasks/AIJARVISV2-13.md](tasks/AIJARVISV2-13.md) |
