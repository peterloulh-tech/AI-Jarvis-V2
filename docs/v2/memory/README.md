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

恢复规则以仓库根目录 `AGENTS.md` 为准。默认读取 `AGENTS.md`、[`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)、当前 Dashi 任务和直接依赖；只有需要查找历史或定位来源时才打开本索引和少量任务卡。

任务卡只在进入 `in_review` 或 `done` 时维护；跨任务决定才进入 [`DECISIONS.md`](DECISIONS.md)。

## 文档分类

- `DAILY`：入口和当前快照；默认只读 `AGENTS.md`、`PROJECT_CURRENT_STATE.md` 和当前 Dashi 任务。
- `TASK-SPECIFIC`：命中当前任务后才读取的需求、验收、模型、runtime、Windows、隐私或测试资料。
- `FROZEN`：冻结需求、编号、决定、官方基线和正式验收规则；不得因整理文档而改写。
- `REFERENCE`：历史审计、Legacy 资产和已完成任务的证据；只在需要追溯时读取。

分类只用于控制上下文，不豁免适用任务的正式需求、四方审计、Official-First 或证据核对。

## 文件职责

- [`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)：当前有效阶段、冻结基线、公共约定、开放风险和下一步注意事项。
- [`OFFICIAL_BASELINE_INDEX.md`](OFFICIAL_BASELINE_INDEX.md)：当前 Local O 锁定版本、第一方官方行为及原作者/V2 数据链复用入口。
- [`DECISIONS.md`](DECISIONS.md)：已批准且会约束多个后续任务的决定。
- [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md)：唯一任务卡模板。
- [`tasks/`](tasks/)：只收录已进入 `in_review` 或 `done` 的真实任务；历史任务按需从 Dashi 和对应卡片读取。

## 活动任务入口

| 任务编号 | 模块 | 状态 | 一句话摘要 | 任务卡 |
|---|---|---|---|---|
| AIJARVISV2-93 | O 动态验收 | `in_progress` | Official-First O Reference Harness Windows/NVIDIA 动态验收。 | — |
| AIJARVISV2-27 | V 并发基线 | `backlog` | 候选 V 共享权重 1～3 路并发基线，等待前置条件。 | — |
| AIJARVISV2-24 | O 性能基线 | `backlog` | O 16GB 模型独占性能基线，等待 Task93。 | — |

## 最近关键完成项

- AIJARVISV2-94：基础规则、状态摘要和最小读取路径完成精简；证据见 [任务卡](tasks/AIJARVISV2-94.md)。
- AIJARVISV2-92：Reference Harness v2 离线重建完成，动态验收由 Task93 承接。
- AIJARVISV2-26：V-C01/V-C02 共同 v3 功能硬门完成，Windows/NVIDIA 和正式语料仍待验证。
- AIJARVISV2-23：Legacy Diagnostic PoC 与 2026-08-09 Windows 基线完成，不能替代正式 Product Adapter。

更早任务不在本索引重复展开；需要历史证据时按任务编号读取 Dashi 和对应任务卡。
