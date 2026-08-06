# AI Jarvis V2 协作规则

本仓库的长期项目记忆入口为 [`docs/v2/memory/README.md`](docs/v2/memory/README.md)。Dashi 项目固定为 `ai-jarvis-v2`；Dashi 子命令支持 `--project` 时必须显式传入，不支持时先从项目限定读取中解析真实任务 UUID，再用版本锁写入。

事实优先级按内容区分：Dashi 负责真实任务状态、描述、依赖和评论；Git 提交、实际文件和测试记录负责真实交付与验证结果；`docs/v2/memory/` 只作摘要索引。记忆与事实冲突时必须修正记忆，不得用记忆覆盖事实。

## 会话与记忆规则

1. 每个新的 Dashi 任务使用一个新的 Codex 会话；同一任务的评审、返工和中断恢复继续原会话。
2. 新任务开始时只读取 [`PROJECT_CURRENT_STATE.md`](docs/v2/memory/PROJECT_CURRENT_STATE.md)、当前 Dashi 任务和直接依赖任务卡；其他历史按需读取。
3. 任务进入 `in_review` 时创建或更新任务卡；正式通过时只做最小状态更新。
4. 普通任务使用额度节省模式：最小交付、针对性验证、精简报告。
5. 阶段门、架构或协议冻结、集成及发布验收使用严格模式。
6. 普通 Codex 指令不得重复 Dashi 中已有的完整任务要求。
7. 只有跨任务重要决定才更新 [`DECISIONS.md`](docs/v2/memory/DECISIONS.md)。
8. 禁止记录冗长聊天、推理过程和重复需求。
9. 记忆必须与 Dashi、Git、实际代码和测试记录一致。
10. 任务记忆未收口时，不得将对应 Dashi 任务改为 `done`。

任务卡必须使用 [`TASK_TEMPLATE.md`](docs/v2/memory/TASK_TEMPLATE.md)，文件名使用真实任务编号且不补零。文档任务卡通常控制在 200～400 字，复杂架构、协议或代码任务最多 800 字。
