# AI Jarvis V2 协作规则

本仓库的长期项目记忆入口为 [`docs/v2/memory/README.md`](docs/v2/memory/README.md)。Dashi 项目固定为 `ai-jarvis-v2`；Dashi 子命令支持 `--project` 时必须显式传入，不支持时先从项目限定读取中解析真实任务 UUID，再用版本锁写入。

事实优先级按内容区分：Dashi 负责真实任务状态、描述、依赖和评论；Git 提交、实际文件和测试记录负责真实交付与验证结果；`docs/v2/memory/` 只作摘要索引。记忆与事实冲突时必须修正记忆，不得用记忆覆盖事实。

## Context & Planning Efficiency（上下文与规划效率）

新 Codex 会话恢复上下文时只确认当前事实：

1. 本文件 `AGENTS.md`；
2. [`PROJECT_CURRENT_STATE.md`](docs/v2/memory/PROJECT_CURRENT_STATE.md)；
3. 当前 Git branch、HEAD 和 status；
4. 当前 Dashi 任务、相关评论和直接依赖（当前任务确实需要时）。

上下文恢复后直接进入当前任务相关文件和证据；不重复总结历史、重新审计已经完成的工作，或进行与当前任务无关的重复准备、审计和联网。再根据任务编号、链接或实际需要，按需读取命中的少量任务卡、需求文件和代码。

[`docs/v2/memory/README.md`](docs/v2/memory/README.md) 是条件读取的轻量索引：已经知道当前任务编号、直接依赖和相关文件时，不要求每次强制读取；需要查找历史任务、定位来源任务、根据关键词寻找相关摘要，或者当前任务缺少明确依赖时才读取。读取索引后，只打开实际命中的少量任务卡，不批量读取全部任务卡。

如果 Superpowers 或其他流程要求 planning，默认只保留最小会话内 plan；除非用户或当前任务明确要求，不额外创建 plan、design 或 spec 文档。

普通任务遵循“三加二原则”：尽量少改动、最大化复用、避免不必要返工和复杂度，同时保证能用和节省 Token；使用最小交付、针对性验证和精简报告。高价值、高风险任务可为了准确性适度增加必要分析，阶段门、架构或协议冻结、集成及发布验收使用严格模式，但不得以“更完整”为由无边界扩大范围。普通 Codex 指令不得重复 Dashi 中已有的完整任务要求。只有跨任务重要决定才更新 [`DECISIONS.md`](docs/v2/memory/DECISIONS.md)。

## Reuse-First（三层固定规则）

开发或修改功能前，只读取当前任务相关模块，并按以下三层顺序决策：

1. **已有资产**：V2 当前实现，以及 AIJARVISV2-17/18 已确认的原作者复用结论；已完成的专项审计优先直接使用其结论和源码索引，例如现有 O Runtime 四方 Delta 审计。能直接满足就直接复用，能最小修改满足就修改复用，不新增平行实现。
2. **官方基线**：第三方官方行为优先使用 [`OFFICIAL_BASELINE_INDEX.md`](docs/v2/memory/OFFICIAL_BASELINE_INDEX.md) 的项目锁定 revision。
3. **V2 当前需求**：比较原作者已有实现、官方标准实现、V2 当前实现和本任务需求，只实现真正缺失的 Delta；只有前两层都不能满足时才允许新增实现。

只有当前任务所需信息在已有资产中缺失，model、runtime 或 API 版本/revision 改变，实际行为与已有结论冲突，或当前判断需要 source-level 证据才能可靠完成时，才继续深入源码或重新查询官方。

禁止为了“更漂亮、更规范、更先进”重写已经够用的代码，也禁止为执行 Reuse-First 重复审计整个项目。

### Reference Harness & Proven Infrastructure

外部 model/runtime 正式产品接入前，优先依据 Locked Official Baseline、原作者可复用实现和已有真实运行证据建立最小 Reference Harness，先确认 model/runtime 正确行为，再实现 V2 Product Adapter。Reference Harness 只保留必要参数转换、资源安全、原始结果和测试 instrumentation，不提前承载产品状态机、session 语义、IPC 或 Worker 业务策略。

探索型 PoC 保留有效真机证据与已证明稳定的工程基础设施；其模型语义、adapter、session 和测试专用逻辑必须经 Official/Reuse 对齐后再决定是否进入 Reference Harness 或正式产品。已经真实跑通的 build、CI、portable、Windows Runner、CUDA/runtime 准备、artifact 和测试基础设施默认优先复用；模型/runtime 语义重建与工程基础设施重建分开判断，只修改真实存在的 Delta。

### Official-First Runtime Rule

模型、runtime、session 或 streaming 已有锁定且成熟的官方实现时，默认直接以官方实现为基础，不得为“参考实现”或测试方便另建独立 Runtime/Harness；AI Jarvis 只实现正式需求 Delta。只有官方能力确实缺失且存在明确 Requirement ID 时才允许自研。

## 禁止上下文膨胀

1. 禁止批量打开整个 `tasks`、`requirements`、`memory` 或 `docs` 目录。
2. 禁止每次任务启动时读取全部任务卡、全部需求文档或全部历史摘要。
3. 禁止递归加载完整依赖链；只读取当前任务明确列出的直接依赖，后续来源按实际需要命中。
4. 禁止因为某个文件存在，就自动将其全文加入上下文。
5. 禁止把所有任务摘要拼接成一个大文件后统一加载。
6. 禁止为了查找一个历史信息而扫描和读取全部历史任务；应先用编号、链接或轻量索引定位。
7. 禁止将完整终端日志、完整测试输出或大段报错长期保留在上下文中；只保留当前任务必要的关键结果。

## Codex 线程规则

1. 一个 Codex 对话线程原则上只处理一个 Dashi 主任务及其必要修复。
2. 同一主任务中的代码修改、测试、失败修复和复核可以继续使用当前线程。
3. 当前主任务进入 `in_review` 或完成态后，先同步 `PROJECT_CURRENT_STATE.md`、当前任务卡和 README 任务索引。
4. 开始下一个 Dashi 主任务时，新建 Codex 对话线程。
5. 不在同一个已经积累大量上下文的线程中连续推进多个主任务。
6. 单个任务线程因大量日志、代码读取或反复测试而明显膨胀时，可以先生成精简交接摘要，再新建线程继续同一任务；不得依赖完整旧线程维持项目记忆。

## 状态与记忆同步

1. 任务进入 `in_review` 时创建或更新任务卡，并同步 README 索引中的状态、简短摘要和任务卡路径。
2. 任务进入完成态（Dashi `done`）时，只做必要更新，并再次同步 README 索引中的状态、简短摘要和任务卡路径。
3. `PROJECT_CURRENT_STATE.md`、当前任务卡和 README 索引中的任务状态必须保持一致。
4. 任务记忆未收口时，不得将对应 Dashi 任务改为 `done`。
5. 记忆必须与 Dashi、Git、实际代码和测试记录一致；禁止记录冗长聊天、推理过程和重复需求。
6. 状态同步只通过现有文件和 Dashi 完成，不增加自动同步脚本、数据库、向量检索、知识图谱、Hook、Skill 或新的记忆层级。

任务卡必须使用 [`TASK_TEMPLATE.md`](docs/v2/memory/TASK_TEMPLATE.md)，文件名使用真实任务编号且不补零。文档任务卡通常控制在 200～400 字，复杂架构、协议或代码任务最多 800 字。
