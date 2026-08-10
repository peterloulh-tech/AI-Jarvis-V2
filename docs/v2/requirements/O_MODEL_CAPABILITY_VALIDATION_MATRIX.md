# Local O 模型能力验证矩阵

> 任务：AIJARVISV2-93
>
> 正式功能基线：`AI_Jarvis_V2_总需求_功能需求正式冻结版_v1.0.md`，SHA-256 `270e0b1f225ecd0f20d34a480a14845bcebab19708b873178c196837c8fd3c90`
>
> 正式非功能基线：`AI_Jarvis_V2_非功能需求_正式冻结版_v1.0.md`，SHA-256 `f65950be98e56217d5e0472316ca7531d46227b00cfe5560186de7147ab8b7b5`
>
> Locked 组合：MiniCPM-o 4.5 GGUF Q4_K_M + `llama.cpp-omni@b9d15b83ee353b2eaeee4d9318c98a35a1347486` + 项目锁定 patch；TTS/参考音频关闭。

本矩阵只回答 Local O 基础模型/runtime 能力是否足以支撑冻结 V1。Online、Local V、UI、采集设备管理、发送池、Overlay、安装器和普通配置保存不进入模型能力结论。既有 Task23 证据只按 `Legacy Diagnostic PoC` 使用；Task92 Mock/dry-run 只证明 Harness 外围链，不冒充模型动态证据。

## 1. 判定口径

- `PROVEN`：同一 Locked 组合已有直接、可复核动态证据；若证据来自 Legacy Harness，Task93 仍须在 Reference Harness 做回归，但不把已证明能力退回未知。
- `PARTIAL`：已有真实片段、静态接口或外围链证据，但当前 Reference Harness、完整组合或客观 gold 尚未闭环。
- `UNCONFIRMED`：存在间接线索或输入覆盖意图，尚不能给出能力 PASS/FAIL。
- `NOT_TESTED`：没有满足该能力最小条件的合格动态场景。
- `CORE-GATE`：若在排除 `HARNESS`、`LOCKED_RUNTIME`、`PROMPT_CONTRACT` 和 `PRODUCT_DELTA` 后确认能力不成立，不应继续其上层正式产品逻辑。
- `FEATURE-GATE`：只阻断依赖该能力的对应功能，不自动否定其他 Local O 能力。

一次失败不得直接写成“模型不支持”。每次失败至少保留 official profile 与 V2 contract profile、原始结果、输入时间轴、runtime boundary、prompt/profile、模型/runtime SHA、资源与 cleanup；先区分 `HARNESS`、`LOCKED_RUNTIME`、`PROMPT_CONTRACT`、`PRODUCT_DELTA`，最后才归因 `MODEL_CAPABILITY`。

## 2. 能力总表

| ID | Requirement ID / 短标题 | 类型 / 门槛 | 冻结需求与所依赖的 O 能力 | 当前证据 / 状态 | Task24 前真机 / O-IN-07 | 剩余测试、PASS 后允许继续、FAIL 优先区分 |
|---|---|---|---|---|---|---|
| O-CAP-01 | FR-04.07、FR-05.01、FR-20、FR-21、FR-23.03；NFR-02.01、NFR-05.02：Locked 离线加载与 no-TTS 文字 | `RUNTIME_BASE` / `CORE-GATE` | Windows/NVIDIA 16GB 上离线加载唯一模型，以 no-ref/no-TTS 路径取得文字 LISTEN/SPEAK 结果。 | Task23 RTX 5070 Ti 16GB 真实运行确认 Locked 模型/runtime 加载、73/73 `ok:true`、69 LISTEN/4 SPEAK、no-TTS 文字、VRAM/cleanup。`PROVEN` | **是，做当前 Reference Harness 回归**；O-IN-07 **覆盖**加载、输入、文字与 TTS 0 的 smoke。 | official-1hz 动态回归即可。PASS 后允许继续评估更高层组合能力；FAIL 先查 `HARNESS`/portable/model identity/CUDA，再查 `LOCKED_RUNTIME`，不得先判模型退化。 |
| O-CAP-02 | FR-05.01、FR-05.06、FR-10.02；NFR-05.01：单实例、单会话、单文字流与 streaming fragment | `RUNTIME_BASE` / `CORE-GATE` | 同一模型实例和持续会话内，一次只存在一个文字生成流；SPEAK 可跨结果 fragment 延续并被真实聚合。 | Locked 源码一入一出、独立输入/结果线程已核对；Legacy 真机得到连续 4 个真实 SPEAK fragment；Task92 聚合/边界 Mock 已通过，Reference Harness 动态未执行。`PARTIAL` | **是**；O-IN-07 **覆盖** LISTEN→SPEAK、generation/sequence、fragment 与 input exhaustion 主路径。 | official-1hz + legacy-3s-replay 当前 binary 对照。PASS 后允许基于真实 fragment 设计薄 Product Adapter；FAIL 区分 `HARNESS` 聚合、`LOCKED_RUNTIME` fragment/boundary 和 `PROMPT_CONTRACT` 输出长度。 |
| O-CAP-03 | FR-05.01、FR-05.06、FR-07.02、FR-23.04：生成期间持续音画与最新上下文 | `RUNTIME_BASE` / `CORE-GATE` | 画面和音频持续进入同一会话；生成文字时仍 prefill/更新上下文，下一次输出能使用生成期间出现的新证据。 | producer/consumer 并行和持续 push 有源码证据；Legacy 运行有 context 增长和连续输入，但未用语义 gold 证明“生成期间新事件被下一轮理解”。`PARTIAL` | **是**；O-IN-07 **部分覆盖**生成前/中/后输入标记，只证明时间轴，不证明新语义被使用。 | 需要 TSN-05。PASS 后允许开发持续输入与生成并行的产品 Delta；FAIL 区分 `HARNESS` 时序、`LOCKED_RUNTIME` KV/prefill、`PROMPT_CONTRACT` 未引用证据、`MODEL_CAPABILITY` 时序理解。 |
| O-CAP-04 | FR-04.03、FR-05.02、FR-08、FR-23.03：模型自主 SPEAK/LISTEN 与智能沉默 | `RUNTIME_BASE` / `CORE-GATE` | 不靠帧差、音量、句末或额外模型，Locked 模型基于连续上下文自主决定 SPEAK/LISTEN；显著事件可说，平静场景可沉默。 | Legacy 真机在默认 startup guard 后出现真实自主 SPEAK，证明不是“永远 LISTEN”；但当前 official-1hz 尚未动态复核，且没有平静负样本/误触发率。`PARTIAL` | **是**；O-IN-07 **部分覆盖**单一正向触发机会，不覆盖应沉默负样本和 paired decision。 | 需要 TSN-01。PASS 后允许继续自主触发/智能沉默上层逻辑；FAIL 区分 `PROMPT_CONTRACT` 对 SPEAK 概率的压制、`LOCKED_RUNTIME` guard/cadence、`MODEL_CAPABILITY` 主动决策。 |
| O-CAP-05 | FR-05.03、FR-05.04、FR-05.08、FR-07.01、FR-09.04、FR-10.02、FR-23.03：单次三批结构化中文文字 | `V2_CONTRACT` / `CORE-GATE` | TTS 关闭时，同一次输出产生一个事件信封和恰好 3 个有序风格批次；内容为简短 `zh-CN`，共享主要事件/人格/上下文，不补调用。 | Legacy 真机已生成符合 `{batches...}` 的多批 JSON 前缀但未闭合；Mock 可证明完整三批的聚合/validator，不证明模型稳定产出。`PARTIAL` | **是**；O-IN-07 **部分覆盖**固定 3 style_id 和 compact contract，没有完整真实模型 payload，也不覆盖人格/长度/数量边界。 | 需要 TSN-06。PASS 后允许实现薄 contract adapter/validator；FAIL 区分 `HARNESS` completion、`PROMPT_CONTRACT` schema/长度、`LOCKED_RUNTIME` token/fragment、`MODEL_CAPABILITY` 指令遵循。 |
| O-CAP-06 | FR-05.08、FR-05.09、FR-17.04～17.06、FR-22；NFR-03.01、NFR-05.01、NFR-08.01：session/drain/rebuild/release | `RUNTIME_BASE` / `CORE-GATE` | session_end 有界 drain；失败/超时后可建立干净新上下文；停止后进程、显存与孤儿清理，不把旧结果带入新代次。 | Locked RAII/session_end 源码、Legacy 正常 cleanup、Task92 timeout/drain/重复 cleanup Mock 均存在；当前 Reference Harness 的真实 drain、强杀、干净重启和 VRAM 回基线未执行。`PARTIAL` | **是**；O-IN-07 **未单独覆盖**，输入可复用但必须增加生命周期编排。 | 需要 TSN-07。PASS 后允许开发产品 lifecycle/恢复 Delta；FAIL 区分 `HARNESS` 结束顺序、`LOCKED_RUNTIME` drain/context reset、`PRODUCT_DELTA` 进程监管。 |
| O-CAP-07 | FR-03.02、FR-07.01～FR-07.04、FR-09.04、FR-14：游戏/通用场景事件与高光 grounding | `V2_CONTRACT` / `CORE-GATE` | 从真实音画选择一个最值得评论的事件，区分 ordinary/highlight，给出 event_type、摘要、重要度/置信度，并生成不编造事实的相关弹幕。 | O-IN-07 只有“开始/BOSS/几何图形/计时”等合成卡片，gold 未定义事件、高光或弹幕相关性；Legacy 输出前缀也未形成语义 PASS。`UNCONFIRMED` | **是**；O-IN-07 **不覆盖语义质量**。 | 需要 TSN-02。PASS 后允许继续事件信封、高光路由和风格产品逻辑；FAIL 区分 `PROMPT_CONTRACT` 标签定义、gold/`HARNESS`、`MODEL_CAPABILITY` 视觉/音画 grounding。 |
| O-CAP-08 | FR-05.07、FR-07.02、FR-23.02：15/20/30 秒连续上下文与摘要 | `V2_CONTRACT` / `CORE-GATE` | 能理解跨时间发展的事件；约 20 秒窗口及 15/20/30 秒对比可保留必要前因，随正常输出生成当前场景和主要事件摘要，不额外调用。 | O-IN-07 有 15/20/30 秒位置标记，但没有需要记住前因的 semantic gold；Legacy 只证明 context 增长。`UNCONFIRMED` | **是，先证明最低可行性；分布数据留给 Task24**；O-IN-07 **部分覆盖时长，不覆盖记忆语义**。 | 需要 TSN-05。PASS 后允许 Task24 测上下文窗口/资源曲线；FAIL 区分 `HARNESS` 时间轴、`LOCKED_RUNTIME` KV/window、`PROMPT_CONTRACT` 摘要、`MODEL_CAPABILITY` 长时关联。 |
| O-CAP-09 | FR-04.02～FR-04.06、FR-07.01、FR-07.03、FR-09.02：主播语音、来源角色与触发开关 | `V2_CONTRACT` / `FEATURE-GATE` | 能把主播语音作为辅助上下文；开启时可因相关发言自主输出，关闭时不能仅因发言触发；不同音频来源需保持可区分语义。 | 现有 O-IN-07 只有单路 WAV/帧，没有麦克风与游戏/系统音频的角色对照，也没有开关 A/B。`NOT_TESTED` | **是，至少完成 paired 可行性；否则不开发该功能上层逻辑**；O-IN-07 **不覆盖**。 | 需要 TSN-03。PASS 后允许主播语音触发/接话互动的产品 Delta；FAIL 区分 `PRODUCT_DELTA` source tagging/mixing、`PROMPT_CONTRACT` 角色说明、`MODEL_CAPABILITY` 语音理解。 |
| O-CAP-10 | FR-04.06、FR-04.08、FR-05.01：全部音频不可用时纯画面降级 | `RUNTIME_BASE` / `FEATURE-GATE` | 同一 Locked O 路线可在无音频或音频中途失效后继续处理画面，不要求另一模型或自动切换模式。 | 当前 fixture 每个 chunk 都有 WAV；静音 WAV 不等同音频输入缺失/失效，未验证 audio-less ABI 与后续 SPEAK/LISTEN。`NOT_TESTED` | **是；否则不开发自动纯画面降级上层逻辑**；O-IN-07 **不覆盖**。 | 需要 TSN-04。PASS 后允许产品实现音频失效降级；FAIL 区分 `HARNESS` 缺失输入表达、`LOCKED_RUNTIME` audio-less path、`PRODUCT_DELTA` 采集切换、`MODEL_CAPABILITY` 纯视觉理解。 |
| O-CAP-11 | FR-05.03、FR-05.04、FR-05.09、FR-10.02、FR-21、FR-23.02；NFR-04.02、NFR-05.02：输出规模、硬超时与 16GB 边界 | `V2_CONTRACT` / `CORE-GATE` | 在 16GB 模型独占环境至少能完成冻结的 3 批结构；覆盖 3～15 条与 225/350/500 字预算，分别接受 12/16/20 秒硬超时，并记录首片段/完整时延与 VRAM。 | Legacy 只有未闭合短 JSON 前缀和单次资源数据；没有三个预算边界的完整 payload 或成功分母。`NOT_TESTED` | **是，Task93 先证明代表性边界可运行；P50/P95 与完整矩阵由 Task24 完成**；O-IN-07 **不覆盖输出规模**。 | 需要 TSN-06。PASS 后允许 Task24 进入系统性能基线；FAIL 区分 `PROMPT_CONTRACT` 冗长度、`LOCKED_RUNTIME` token/timeout、`MODEL_CAPABILITY` 长结构生成和真实硬件容量。 |

状态统计：`PROVEN 1`、`PARTIAL 5`、`UNCONFIRMED 2`、`NOT_TESTED 3`，共 11 项。

O-IN-07 保持 `Smoke + Regression Baseline`：它完整承担 O-CAP-01/02 的回归目标，部分覆盖 O-CAP-03/04/05/08/11 的技术路径，不覆盖 O-CAP-06/07/09/10，也不能替代上述部分覆盖项的 semantic/boundary gold。

## 3. Test Scenario Needs

本节只提出 O-IN-07 之后的素材需求，不创建 WAV/JPG/视频/manifest，也不预分配 O-IN-08+ 编号。

### TSN-01 — 显著事件与平静段的自主决策对照

- **Requirement IDs / 能力**：FR-05.02、FR-08、FR-23.03；O-CAP-04。
- **为什么 O-IN-07 不够**：只有一个标记为 trigger opportunity 的正向卡片，没有长平静负样本、paired 输入或误触发判定。
- **视觉/音频**：先是稳定、无事件画面和低信息环境音，随后出现单一清晰事件并配套同步声音；避免文字直接命令模型“说话”。
- **长度/事件数/类型**：45～60 秒；1 个显著事件；`positive + negative`。
- **期望动作**：平静段 `SHOULD_LISTEN`，显著事件窗口 `SHOULD_SPEAK`。
- **expected/gold**：可客观定义决策窗口、禁止外部触发、输入连续性；具体文案只做相关性 gold，不固定逐字。
- **失败区分**：guard/cadence 的 `LOCKED_RUNTIME`、决策偏置的 `PROMPT_CONTRACT`、时序/窗口的 `HARNESS`、最后才是 `MODEL_CAPABILITY`。

### TSN-02 — 真实游戏普通事件→高光事件 grounding

- **Requirement IDs / 能力**：FR-03.02、FR-07.01～FR-07.04、FR-09.04、FR-14；O-CAP-07。
- **为什么 O-IN-07 不够**：合成卡片没有真实游戏状态、动作连续性、ordinary/highlight 对照或事件信封 gold。
- **视觉/音频**：授权或自制游戏片段，先发生可辨认普通事件，后发生单一高光；游戏音频与视觉时间同步，不叠加解释性字幕。
- **长度/事件数/类型**：45～75 秒；2 个事件；`positive + boundary`。
- **期望动作**：两处均 `SHOULD_SPEAK`；其余过渡段 `EITHER_ACCEPTABLE`。
- **expected/gold**：可客观定义 event_type、ordinary/highlight、source_window、关键可见事实和禁止编造项；importance/confidence 只验证类型/范围，不设质量阈值。
- **失败区分**：gold/时间窗的 `HARNESS`、标签与 schema 的 `PROMPT_CONTRACT`、真实音画理解的 `MODEL_CAPABILITY`。

### TSN-03 — 主播语音角色与触发开关 paired A/B

- **Requirement IDs / 能力**：FR-04.02～FR-04.06、FR-07.03、FR-09.02；O-CAP-09。
- **为什么 O-IN-07 不够**：只有单路 WAV，不能区分麦克风与游戏/系统音频，也没有相同素材下触发开关对照。
- **视觉/音频**：相同游戏画面；独立麦克风轨含一条与画面相关发言和一条无关闲聊，独立游戏音轨含对应事件声；source role 必须保留。
- **长度/事件数/类型**：30～45 秒；2 条主播发言 + 1 个画面事件；`positive + negative + boundary`，同素材运行开关 ON/OFF 两次。
- **期望动作**：相关发言且 ON 为 `SHOULD_SPEAK`；仅无关闲聊或 OFF 下仅因发言触发为 `SHOULD_LISTEN`；真实画面事件仍 `EITHER_ACCEPTABLE/SHOULD_SPEAK` 由 gold 窗口区分。
- **expected/gold**：可定义轨道角色、发言文本/时间、开关、允许触发原因；不固定弹幕逐字。
- **失败区分**：source tagging/mixing 的 `PRODUCT_DELTA`、输入承载的 `HARNESS/LOCKED_RUNTIME`、角色/开关说明的 `PROMPT_CONTRACT`、语音 grounding 的 `MODEL_CAPABILITY`。

### TSN-04 — 音频缺失与运行中失效后的纯画面降级

- **Requirement IDs / 能力**：FR-04.06、FR-04.08、FR-05.01；O-CAP-10。
- **为什么 O-IN-07 不够**：每个 chunk 都携带 WAV，静音文件不能证明缺失音频字段或运行中断流路径。
- **视觉/音频**：视觉包含可单独识别的事件；三变体为从开始无音频、前半有音频后明确失效、正常音频对照。
- **长度/事件数/类型**：每变体 25～35 秒；1 个视觉事件；`boundary + positive`。
- **期望动作**：事件窗口 `SHOULD_SPEAK`，其余 `EITHER_ACCEPTABLE`；不得因音频缺失导致普通 runtime failure。
- **expected/gold**：可定义失效边界、后续 frame 接受、决策/结果仍可产生；文案验证视觉事实相关性。
- **失败区分**：manifest/ABI 的 `HARNESS`、audio-less decode 的 `LOCKED_RUNTIME`、降级切换的 `PRODUCT_DELTA`、纯视觉理解的 `MODEL_CAPABILITY`。

### TSN-05 — 生成期间新事件与 15/20/30 秒前因关联

- **Requirement IDs / 能力**：FR-05.01、FR-05.06、FR-05.07、FR-07.02、FR-23.02；O-CAP-03/08。
- **为什么 O-IN-07 不够**：虽有 during-generation 和 15/20/30 秒标记，但卡片之间没有必须依赖早期前因才能正确解释的语义关系。
- **视觉/音频**：事件 A 建立明确前因，长生成窗口期间出现事件 B，随后事件 C 只能结合 A/B 才能正确总结；音频提供同步但非唯一答案线索。
- **长度/事件数/类型**：40～55 秒；3 个关联事件；`positive + boundary`，以 15/20/30 秒窗口三次运行。
- **期望动作**：B/C 窗口 `SHOULD_SPEAK`，过渡段 `EITHER_ACCEPTABLE`。
- **expected/gold**：可定义 A→B→C 事实关系、生成中输入必须接收、下一输出必须包含的关系点、摘要长度/schema；不固定修辞。
- **失败区分**：时钟/生成窗口的 `HARNESS`、KV/window/prefill 的 `LOCKED_RUNTIME`、摘要/引用要求的 `PROMPT_CONTRACT`、长时关联的 `MODEL_CAPABILITY`。

### TSN-06 — 三批风格与 225/350/500 字预算边界

- **Requirement IDs / 能力**：FR-05.03、FR-05.04、FR-05.08、FR-07.01、FR-09.01～FR-09.04、FR-10.02、FR-21、FR-23.02；O-CAP-05/11。
- **为什么 O-IN-07 不够**：只要求 compact 三批且 Legacy payload 未闭合；没有 3～15 条、人格/风格差异、225/350/500 字与 12/16/20 秒边界。
- **视觉/音频**：单一、清晰、可多角度评论的事件；音频与事件同步且不引入第二事件。媒体保持不变，仅切换三组 contract/budget。
- **长度/事件数/类型**：每组 20～30 秒；1 个事件；`positive + boundary`。
- **期望动作**：`SHOULD_SPEAK`。
- **expected/gold**：schema、三批顺序、style_id、条数、字符上限、同一事件、TTS 0、额外调用 0、适用硬超时均可客观判定；具体文案只判相关性/风格方向。
- **失败区分**：聚合/completion 的 `HARNESS`、fragment/token/timeout 的 `LOCKED_RUNTIME`、schema/风格/冗长度的 `PROMPT_CONTRACT`、长结构遵循的 `MODEL_CAPABILITY`。

### TSN-07 — session_end、干净新会话与旧上下文隔离

- **Requirement IDs / 能力**：FR-05.08、FR-05.09、FR-17.04～FR-17.06、FR-22；NFR-03.01、NFR-05.01、NFR-08.01；O-CAP-06。
- **为什么 O-IN-07 不够**：单次输入只验证正常耗尽，没有两个语义相反会话、timeout/incomplete boundary 后的新 context 或 stale-result gold。
- **视觉/音频**：会话 A 明确呈现状态 A；在 session_end、正常重建和 timeout/incomplete 三种边界后，会话 B 呈现相反状态 B，且 B 不含 A 的提示。
- **长度/事件数/类型**：每个会话 20～30 秒；A/B 各 1 个事件；`boundary + negative`。
- **期望动作**：B 的事件窗口 `SHOULD_SPEAK`；任何引用 A 或旧代次输出均不接受。
- **expected/gold**：可定义 PID/context/session/generation、drain 结果、旧结果为 0、B 必须/禁止事实、cleanup/VRAM/orphan；文案不固定。
- **失败区分**：结束/消费顺序的 `HARNESS`、context reset/drain 的 `LOCKED_RUNTIME`、进程监管的 `PRODUCT_DELTA`；只有新会话干净且仍混淆时才考虑 `MODEL_CAPABILITY`。

## 4. Task24 入口

Task24 只能在 O-CAP-01～08、O-CAP-11 的 `CORE-GATE` 已由当前 Reference Harness 给出动态 PASS，且 O-CAP-09/10 至少有明确 PASS 或限定性 FAIL 决策后开始。Task93 只证明代表性可行性和归因；Task24 继续完成 15/20/30 秒、3～15 条、225/350/500 字、P50/P95、显存/GPU 和忙碌比例的正式性能矩阵。
