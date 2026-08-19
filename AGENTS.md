# AI Jarvis V2 协作规则

长期记忆入口是 [`docs/v2/memory/README.md`](docs/v2/memory/README.md)。Dashi 项目固定为 `ai-jarvis-v2`；Dashi 命令不支持 `--project` 时，先用项目限定读取解析真实任务 UUID，再用最新版本锁写入。

事实按职责分工：Dashi 是任务状态、描述、依赖和评论的权威；Git、实际文件和测试记录是交付与验证的权威；`docs/v2/memory/` 只保存短摘要和入口。冲突时修正摘要，不用摘要覆盖事实。

Codex 是本项目技术负责人、四方审计执行者和实际开发者；不设置第二个 ChatGPT 审核流程。任务验收和 Dashi `done` 仍需遵守本文件及用户明确确认。

## 最小恢复与开发原则

新会话默认只读：

1. 本文件；
2. [`PROJECT_CURRENT_STATE.md`](docs/v2/memory/PROJECT_CURRENT_STATE.md)；
3. 当前 Git branch/HEAD/status；
4. 当前 Dashi 任务、直接评论和任务明确命中的文件。

已知任务编号和依赖时，不必再读 memory 索引；禁止批量打开全部 `docs`、`requirements`、`memory` 或任务卡。普通任务采用最小改动、最短正确路线、针对性验证和精简报告；计划默认只留在当前会话，不额外创建 plan/design/spec 文档，也不长期保存完整终端日志。不为文档完整、覆盖率或流程形式增加工作。

只有跨任务决定才更新 [`DECISIONS.md`](docs/v2/memory/DECISIONS.md)。只有阶段、主任务、活动路线、阻塞状态或唯一下一步变化时才更新当前状态。普通 commit、聊天、重复测试和临时失败不写入长期记忆。

大型模型/runtime 制品只在首次取得/准入、来源或版本或字节数变化、复制到正式位置、最终测试包/发布包组装时计算一次 SHA-256；普通启动和重复推理只检查路径、文件名和字节数。小型 fixture/结果可按证据需要哈希。Dashi 版本锁和运行互斥锁继续保留，它们不等于大文件内容哈希。

## 四方审计与 Official-First

涉及架构、Bug、runtime、session、streaming、server、adapter、模型、构建、Windows/CUDA、测试、性能或技术选型时，必须按以下顺序判断：

1. 正式冻结需求：先确认产品行为和验收边界；
2. 当前官方成熟实现：检查实际源码、文档、构建和测试，锁定 revision，并登记到 [`OFFICIAL_BASELINE_INDEX.md`](docs/v2/memory/OFFICIAL_BASELINE_INDEX.md) 或对应 lock；
3. 当前原作者成熟实现：只有官方不能满足时采用；
4. 已验证项目资产：仅复用仍兼容且有证据的代码、测试、构建、CI 或资产；
5. V2 最小自研增量：前四项均不能满足且正式需求确实需要时才新增。

判断标签统一使用：`DIRECT`、`MODIFY`、`DUPLICATE`、`CONFLICT`、`V2-ONLY`、`UNCONFIRMED`、`MISSING`。已完成、已投入或已有测试不能压过更高优先级事实；只有 upstream、模型、runtime、API、环境或证据发生实质变化时才重审。

V 代码必须独立于 O Runtime、Harness、Session、Worker 和产品语义；不得为复用而把 O 改成通用框架。详细边界按需读取 [`DECISIONS.md`](docs/v2/memory/DECISIONS.md) 中的 V 独立决定。

准备新增或重写 Runtime、Harness、Session Manager、Streaming boundary、Server、Adapter、Scheduler、Process Manager、测试框架或构建体系前，必须先证明成熟实现和项目资产均不能满足正式需求。确需 Reference Harness 时，只保留参数转换、资源安全、原始结果和 instrumentation，不承载产品状态机、IPC 或 Worker 业务策略。

## 执行、验证与远程操作

默认一轮完成：读取命中需求和事实、完成四方判断、实施最小修改、运行相关验证、检查 diff/status、提交本地并报告证据。测试和构建优先复用官方方案，其次原作者、已验证资产，最后才补 V2 增量；不得平行重建已有 Runtime/Session/Streaming/Media/Build 测试框架。

默认本地优先：可以直接本地修改、验证和 commit；只有用户或当前任务明确要求时才 `git push` 或触发远程 workflow。远程长任务取得 run ID 后停止，不 watch、不高频轮询、不自动重试；远程失败只报告最短人工命令。

只有冻结需求矛盾、成熟方案取舍会改变正式产品行为、需要改变冻结需求/整体架构，或缺少无法自行取得的外部资源时，才暂停请求用户决定。

重要任务报告只写实际执行的正式需求、采用路线、复用情况、修改、验证、Git、未验证项、结论和唯一下一步。未执行的验证不能写成 PASS。任务结论使用 `READY`、`BLOCKED`、`PASS` 或 `FAIL`。

## 任务与记忆收口

一个 Codex 线程原则上只处理一个 Dashi 主任务及其必要修复。任务进入 `in_review` 或 `done` 时，创建/更新短任务卡、同步必要状态和索引；用户确认后才能从 `in_review` 改为 `done`。任务仍 `in_progress` 时只记录改变下一步的重要里程碑。

任务卡使用 [`TASK_TEMPLATE.md`](docs/v2/memory/TASK_TEMPLATE.md)，文件名使用真实任务编号；文档任务通常 200～400 字，复杂任务最多 800 字。禁止记录聊天、推理过程、重复需求或无证据结论。不得新增自动同步脚本、数据库、向量检索、知识图谱、Hook、Skill 或新的记忆层级。
