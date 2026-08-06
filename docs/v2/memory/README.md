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

新任务只读取：

1. [`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)；
2. Dashi 中当前任务的完整内容与评论；
3. 当前任务的直接依赖卡片；
4. 仅在上述入口指向时读取相关需求、代码或测试记录。

任务进入 `in_review` 时，用 [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md) 创建或更新卡片；用户正式通过后只更新状态等必要字段。跨任务决定才进入 [`DECISIONS.md`](DECISIONS.md)。

## 文件职责

- [`PROJECT_CURRENT_STATE.md`](PROJECT_CURRENT_STATE.md)：当前有效阶段、冻结基线、公共约定、开放风险和下一步注意事项。
- [`DECISIONS.md`](DECISIONS.md)：已批准且会约束多个后续任务的决定。
- [`TASK_TEMPLATE.md`](TASK_TEMPLATE.md)：唯一任务卡模板。
- [`tasks/`](tasks/)：只收录已进入 `in_review` 或 `done` 的真实任务。

## 已收录任务

| 任务 | 当前 Dashi 状态 | 最终交付提交 |
|---|---|---|
| [AIJARVISV2-1](tasks/AIJARVISV2-1.md) | `done` | `cfd553912de8acf35b9308cf234ccecd4c57c33b` |
| [AIJARVISV2-2](tasks/AIJARVISV2-2.md) | `done` | `a2258691720ee503b67895b9b21e1d89d4f07035` |
| [AIJARVISV2-3](tasks/AIJARVISV2-3.md) | `done` | `898c0d9d6bf18b2aaf41c4d40650fd03c7afcda0` |
| [AIJARVISV2-4](tasks/AIJARVISV2-4.md) | `done` | `2ca8637f405d16bee8f04b40666208547850fe76` |
| [AIJARVISV2-5](tasks/AIJARVISV2-5.md) | `done` | `e10bbdc90f0cc619b1064b2515a3be384c1a715e` |
| [AIJARVISV2-6](tasks/AIJARVISV2-6.md) | `done` | `11b2c111e4a98181a73e4ed4146b3a5e4f333589` |
| [AIJARVISV2-7](tasks/AIJARVISV2-7.md) | `done` | `c6d74dcd970e71b790f4c84d66d0ddeabb1169cf` |
| [AIJARVISV2-8](tasks/AIJARVISV2-8.md) | `done` | `b433f9dbfac5c074086a8d84ce73693670a3bd89` |
| [AIJARVISV2-9](tasks/AIJARVISV2-9.md) | `done` | `2c1177ad35d638b2a40daf5136a4fd7166bf6689` |
| [AIJARVISV2-10](tasks/AIJARVISV2-10.md) | `done` | `ba28c363e44b986812a619620649bea390e5008b` |
