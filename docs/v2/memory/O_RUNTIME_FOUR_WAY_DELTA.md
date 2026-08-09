# O Runtime Four-Way Delta

> 审计日期：2026-08-09；Dashi：`AIJARVISV2-23`。本文件只审计 Local O 的 14 段端到端数据链；未运行模型、CUDA、构建或打包，也未修改产品行为。

## 1. Scope / Locked Baseline

本轮判断当前实现是否正确，只使用以下 `LOCKED` 事实：

- 模型：`openbmb/MiniCPM-o-4_5-gguf@502eec5b03eaee9d0d2ce17a176e3490103c9a63`，固定 LLM Q4_K_M + Vision F16 + Audio F16，TTS 关闭、无参考音频。
- runtime：`tc-mb/llama.cpp-omni@b9d15b83ee353b2eaeee4d9318c98a35a1347486`，加项目锁定 patch `cc8b1c4a...`。本地 `third_party/runtime/vendor/` 是该 revision 的真实源码快照；patch 只增加 CMake alias 和 simplex text prefill，不改变本轮 duplex/session/result 语义。
- 原作者：`LYiHub/pub-local-jarvis@dd8fbf97a3e0f96239a0a465398654be68e88e15`。`git diff --quiet dd8fbf9 -- native third_party/runtime/{src,include}` 为真，因此当前正式 native 链在本轮相关范围内就是原作者锁定实现，没有独立的 V2 产品代码 Delta。

`CURRENT-OFFICIAL-ONLY` 只作参考：MiniCPM-o 当前 Python Demo 的约 1 秒 push/pull、当前 server/Comni 协议及其 `is_listen` 字段不能反推 Locked C API 已升级。幸运的是，决定本轮结论的 1:1 push/decode、前三次 LISTEN、`is_speak`、prompt 分支、FIFO consume 和 drain 均已在 Locked runtime 源码中直接核对，不依赖 current main。

关键 Locked 源码定位：

- `tc-mb/llama.cpp-omni@b9d15b8 → tools/omni/omni.h → omni_context, OmniDuplexFrameResult, omni_duplex_*`
- 同 revision → `tools/omni/omni.cpp → duplex_do_decode, DuplexSession, duplex_session_*_worker_func, omni_duplex_session_begin/push_frame/wait_next_frame/session_end, stream_prefill, omni_free`
- 同 revision → `tools/omni/test/test-duplex.cpp → duplex_test_case`（真实流式建议 `1000 ms`）
- 同 revision → `tools/server/server-omni.cpp → /decode SSE formatter`（`__IS_LISTEN__ → is_listen=true`）

## 2. Four Parties

| 方 | 实际链路 | 本轮定位 |
|---|---|---|
| Original | DXGI/GDI + WASAPI → downmix/resample → `Worker` → `IOmniRuntime`/`RealOmniRuntime` → vendored C API → callback/named pipe | Task17 的 `D/M/R/W` 结论与 `dd8fbf9` 真实源码 |
| Official Locked | `omni_init` → `session_begin` → 每 push 一帧进入 prefill FIFO → 每帧一次 decode/decision → result FIFO → `session_end` drain → `omni_free` | `llama.cpp-omni@b9d15b8` vendored snapshot |
| Task23 | O-IN-07 的 JPG/WAV → `poc_main.cpp` 直接构造 `omni_context` 和 `OmniDuplexFrame` → C API → JSONL/CSV | 独立 PoC harness，不使用 `IOmniRuntime` |
| V2 current | named pipe → `Worker` → 原作者 capture/adapter → C API → `duplex.decision` JSON → named pipe → Python `NativeClient`/`OrchestrationService` | 当前仓库 `native/`；相关内容与 `dd8fbf9` 相同 |

正式链路的真实符号流：

`main::make_real_omni_runtime → Worker::start/start_monitoring/start_duplex → RealOmniRuntime::start_duplex/push_duplex/wait_duplex → omni_duplex_* → Worker::emit_monitoring_event → NamedPipeServer::set_completion → NativeClient::_parse_native_event → OrchestrationService::_on_native_event`

Task23 只共享下层 `jarvis::runtime_provider`/locked vendor，不共享上面任何 adapter、capture、worker、IPC 或产品 result consumer。

## 3. End-to-End Four-Way Matrix

| # / 段 | Original | Official Locked | Task23 | V2 current | 对齐、分类、复用与 SPEAK=0 影响 |
|---|---|---|---|---|---|
| 1 Screen / Vision capture | `DxgiDesktopCapture` 捕获桌宠所在显示器，失效重建并可退 GDI | C API只消费可解码图片路径；每个 push 可带一张图 | 读取固定 JPG；无屏幕采集 | 与 Original 相同 | PoC 合理绕过采集；正式接入复用 DXGI/GDI 但需显式源选择，`MODIFY`。不可能直接导致本次 PoC 的 SPEAK=0。证据：`native/src/windows/dxgi_capture.cpp::DxgiDesktopCapture`；`omni.h::OmniDuplexFrame.img_fname` |
| 2 Audio capture | `WasapiLoopbackCapture` 只抓默认 render loopback | C API消费音频文件路径 | 固定 WAV；无设备采集 | 与 Original 相同 | PoC fixture 合理；正式接入复用 WASAPI COM/拉流，补来源/失效，`MODIFY`。不影响本次 PoC。证据：`native/src/windows/wasapi_capture.cpp::WasapiLoopbackCapture`；`poc_main.cpp::load_manifest` |
| 3 Audio conversion | `downmix_mono` 可直接复用；逐块 `resample_linear` 无跨块相位 | `audition_audio_preprocess` 通过 miniaudio 解码、下混并重采样到 16 kHz mono，再按 100 ms 补齐 | 不自行转换，交给 Locked runtime 解码 3 秒 WAV | 先 downmix/resample，再写 16 kHz float WAV；runtime 再解码 | Task23 路线是官方直接能力，非缺失；正式实时采集仍应 `DIRECT` 复用 downmix/window、`MODIFY` 为有状态 resampler。只有音频 decode 日志失败时才可能影响 SPEAK=0，当前 `UNCONFIRMED`。证据：`audio.cpp`；`audition.cpp::decode_audio_from_buf/audition_audio_preprocess` |
| 4 Frame / audio packaging | `RealOmniRuntime` 将 BGRA/float PCM 临时落盘 BMP/WAV | Locked frame ABI 就是 WAV/JPG/BMP 路径 + `max_slice_nums` + `user_seq` | 直接传已打包 JPG/WAV，`max_slice_nums=-1` | 与 Original 相同，生成临时 BMP/WAV并按 result 删除 | Task23 对 Locked ABI 对齐；正式临时原始媒体落盘有隐私/异常清理风险，`MODIFY`。不是本次 PoC SPEAK=0 候选。证据：`omni_runtime.cpp::write_bgra_bmp/write_float_wav/push_duplex`；`poc_main.cpp::run_session` |
| 5 Runtime / model initialization | `RealOmniRuntime::load` 校验布局，加载 simplex context；duplex 时共享 model、新建 context | `omni_init(params, media_type=2, use_tts=false, duplex=true)`；特殊 token 从 vocab 解析 | 直接 `omni_init`；固定 ctx/batch、GPU layers=99、seed=42 | 经 adapter；GPU layers=-1，duplex context复用已加载 model | Task23 证明 locked model/runtime/CUDA 底层能加载，但绕过 adapter/layout/product参数；独立 runtime wrapper 属 `DUPLICATE`，PoC期 `KEEP`、产品代表性测试时 `REPLACE`。初始化成功本身不能证明产品链。证据：`poc_main.cpp::load_model`；`omni_runtime.cpp::load/start_duplex`；`omni.cpp::omni_init` |
| 6 Prompt / template / session setup | Adapter写入带 `<|audio_start|>/<|audio_end|>` 的 system prompt，并可能加载默认/环境参考音频；force listen 改为 1 | `stream_prefill(index=0)` 有明确 no-ref/no-TTS plain-system 分支；随后 `eval_prefix(<|im_start|>user\n)`，只初始化一次并设置 `n_keep` | plain system + `<|im_end|>\n`，无 audio slot、无 reference audio；session begin 只做一次 index 0 | 使用 audio slot/ref audio 路线，且与 Task23 no-ref约束非等价 | Task23 对 Locked no-ref结构为 `EQUIVALENT`；其强约束三批 prompt 对主动发言分布是否等价为 `UNCONFIRMED`。V2 对 Task23/O-C01 是 `NON-EQUIVALENT/CONFLICT`。TTS=false 本身不能解释 SPEAK=0。证据：`omni.cpp::stream_prefill` 10364附近；`poc_main.cpp::build_prompt/run_session`；`omni_runtime.cpp::start_duplex` |
| 7 Continuous audio/video input | capture thread 默认 1 秒聚合 16k 音频和最新画面；单 pending 槽会覆盖旧帧 | `omni_duplex_push_frame` 入 64 上限 FIFO；prefill/decode worker 严格 1:1 | producer 按 manifest offset push，consumer 同时 wait；固定槽间隔 3 秒 | 约每秒生成一帧，但当产品 input thread 处理慢时 latest-only pending 会丢旧帧 | Task23 连续输入确实成立，但 cadence 与产品/官方参考不同，`MODIFY`。对 SPEAK=0 有高潜在影响。证据：`worker.cpp::start_monitoring/start_duplex`；`omni.cpp::DuplexSession`；`poc_main.cpp::run_session` |
| 8 Duplex decision cadence | V2/Original capture 默认 1 秒，通常一 push 一 decision | C API文档和实现是“一 push → 一 prefill → 一 decode/result”；locked test 明说真实流式建议 `1000 ms`，没有内部把 3 秒音频再切成 1 秒决策 | manifest offset 为 `0,3000,6000...`，所以真实 decision cadence 约 3 秒/次（0.33 Hz） | 默认约 1 秒/次；pending 覆盖可能降低实际 push 数 | Task23 属题设 B，不是 A。Locked 是建议/参考而非 ABI 硬拒绝，故判 `MODIFY` 而非强行 `CONFLICT`；这是当前 SPEAK=0 的 #1 候选。证据：`omni.h` 521附近；`test-duplex.cpp::duplex_test_case`；`o-in-07-manifest.template.json`；`poc_main.cpp:producer` |
| 9 LISTEN / SPEAK decision | Adapter直接传 `result.is_speak`；Worker true→speak、false→listen | 默认 `force_listen_count=3`；前三个 decode直接返回 LISTEN；第四次起进入 token sampling。C result `is_speak=!ended_with_listen` | 未覆盖默认值，前三次被保护；后续走模型自主采样 | 强制把 count 改成 1；随后同样直接映射 | Task23 没有一直卡在 guard；单 case 内无 reset。C API→Task23→V2 无语义反转或 double-negation，`DIRECT`。但 Task23 把 `ok=false` 的默认 `is_speak=false` 也统计成 LISTEN，属 `MISSING`。证据：`omni.cpp::duplex_do_decode/duplex_session_decode_worker_func`；`poc_main.cpp` 427附近；`worker.cpp` 738附近 |
| 10 Async output consumption | Worker独立 result thread，200 ms 持续 wait | input/result 解耦；done FIFO；每 push 恰好一个 result；wait 可阻塞/超时 | producer 与 consumer 并行，按 selected 数持续 wait；不是“每 push 只 poll 一次” | 独立线程持续消费 | 正常路径与官方正确模式一致，`DIRECT`；一个 input 不会在其唯一 result 后再产生第二个迟到 SPEAK。只有 wait 超时后立刻 session_end 时未消费 drain 后 done FIFO，属低概率 `MISSING`。证据：`omni.cpp::omni_duplex_wait_next_frame/session_end`；`poc_main.cpp` 405–470；`worker.cpp` 720–757 |
| 11 Text / result extraction | Adapter取 C result；Worker仅在 speak 时发 text；Python再清洗/去重 | runtime token层解析 LISTEN/SPEAK，剥离控制 token；no-TTS仍填 text queue/result text | speak 时解析一次 JSON，校验三批；原始 text 与 `ok` 都写 JSONL | 直接传 text；下游 `_clean_duplex_message` 和相似去重可抑制已发生的 speak | Task23/V2没有按空文本推断 LISTEN，mapping `DIRECT`。Task23缺少 `ok` gate；V2后处理可能丢已发生的 speak，但不可能影响 Task23 的 `speak_count`。证据：`omni.cpp` 9976/11471附近；`service.py::_on_native_event` |
| 12 Worker / result path / IPC | Worker callback → named pipe frame/CRC → Python client/event bus | Locked C API只定义本进程 result，不提供 V2 IPC schema | JSONL/CSV直出，无 Worker、named pipe或产品 event consumer | 完整走 Original 路径；`duplex.decision` 作为 request id `UINT64_MAX` 的 JSON result过 pipe | Task23 对该段代表性低；JSONL是合理 `V2-ONLY` fixture，不是产品 IPC。产品 IPC/handler应 `MODIFY` 复用 CRC/transport边界。证据：`named_pipe_server.cpp::run`；`client.py::_parse_native_event`；`service.py::_on_native_event` |
| 13 Session end | Adapter stop 调 `session_end` 后 free context；Worker先 join再 stop | `session_end` 等 `in_flight=0`，是 drain 非 cancel；调用方仍负责取空 done FIFO | producer/expected results完成后 end；rebuild mode在同一 `omni_context` 再 begin | 正常 stop配对；自动 recycle 调 `start_duplex`，会先 stop并建立新 context | Task23正常 end `DIRECT`；所谓 rebuild 不清 KV/system prompt/force counter，只重建高层 session worker，故不是“干净 context rebuild”，`MISSING`。它不会令前三次保护反复归零。证据：`omni.cpp::omni_duplex_session_end`；`poc_main.cpp::run/rebuild`；`omni_runtime.cpp::stop_duplex/start_duplex` |
| 14 Runtime/process/resource lifecycle | RAII unload、Worker join；但临时媒体异常残留与 V1职责混合 | `omni_free` 先 session drain，再停 duplex线程并释放 vision/audio/model/context；process kill是上层责任 | try/catch `omni_free`；每 case新进程/新 context；另有 hard-kill fixture | Worker/adapter RAII；每 24 个 completed frame主动重建真实 duplex context | Task23进程级 cleanup可验证底层资源，但不能证明正式 Worker/IPC cleanup，`PARTIAL/MODIFY`。V2 24帧重建与 Locked 已有滑窗/持续 session冲突并重复 lifecycle轮子，`CONFLICT/DUPLICATE`。证据：`omni.cpp::omni_free`；`poc_main.cpp::run`；`worker.cpp::kDuplexRecycleCompletedFrames` |

## 4. DIRECT

- `audio::downmix_mono` 与 `ExactWindowAssembler`：Task17 已批准按符号直接复用；Task23固定 WAV 不需要再造在线音频工具。
- Locked `omni_duplex_session_begin/push_frame/wait_next_frame/session_end`：Task23直接使用正确的高层 C API；没有重写内部 prefill/decode pipeline。
- `OmniDuplexFrame.user_seq`/FIFO关联：Task23 generation+sequence 和 V2 sequence 都直接复用官方回传字段。
- `is_speak` token语义：Locked C API、Task23、`DuplexResult`、Worker 的方向一致。
- no-TTS文字结果：`use_tts=false` 只关闭 TTS链，官方 text queue/C result仍有效。

## 5. MODIFY

- 原作者 DXGI/GDI、WASAPI、capture interface 可保留底层实现，但要补显式源、代次、错误/失效和独立降级语义。
- 原作者逐块 linear resampler 应改为跨块有状态；不得再写第二套 downmix/window。
- Task23 runtime push cadence 应从“3 秒素材=一次 push”改成官方 Locked 参考的约 1 秒决策单元；保留同一素材、模型、prompt和 C API，做单变量验证。
- 正式 adapter可复用模型隔离、RAII和 C API映射，但应统一 no-ref/no-TTS prompt策略、清理临时原始媒体风险。
- IPC保留 CRC/帧和本地 pipe骨架，业务 schema/代次/背压按 V2 最小契约适配。

## 6. MISSING

1. **Task23 result success gate**：Locked `OmniDuplexFrameResult.ok=false` 明确表示 prefill/decode失败，而 `is_speak` 默认 false。Task23当前仍把它计入 `listen_count`。至少必须把 ERROR 与 LISTEN 分开，且 session summary 不得把 failed result 当模型决策。
2. **Task23 clean rebuild proof**：`session_end → session_begin` 在同一 context 上不清 KV、`system_prompt_initialized` 或 `force_listen_used`。P03若声称“会话重建”，需要显式区分 worker-session rebuild 与 clean context rebuild。
3. **Timeout后的 result drain**：正常一入一出路径完整；若 wait timeout/break，当前先 `session_end` 后无法再读取已 drain 到 done FIFO 的结果，可能漏掉迟到 SPEAK。只在失败路径成立。

未把 audio slot、reference audio 或 TTS列为 Task23缺失：Locked `stream_prefill` 已有明确 plain no-ref/no-TTS分支。

## 7. DUPLICATE

| 项 | 已有轮子 | 当前自研必要性 | 建议 |
|---|---|---|---|
| Task23 的 `load_model/run_session` 平行 adapter | Original/V2 `RealOmniRuntime` + Worker；Locked high-level C API | 为固定参数、原始结果和 P02–P04 取证合理；但会绕过正式 adapter，不能长期代表产品 | `KEEP` 本轮 fixture；根因收敛后 `REPLACE` 为正式 runtime integration test |
| V2 每 24 result重建 context | Locked runtime已有持续 session、KV滑窗和 drain | 会丢持续上下文并重复 startup guard，没有证据表明必须存在 | `DELETE-LATER`，先用长会话证据验证 Locked lifecycle再移除 |

Task23 的 manifest replay、并行 producer/consumer、JSONL/CSV、三批 schema validator 都是测试 fixture责任，判 `KEEP`，不因与 Worker形状相似而误标重复。

## 8. CONFLICT

- **V2 startup guard**：`RealOmniRuntime::start_duplex` 把 Locked 默认 3 改成 1，没有本轮证据支持该 Delta。它不会造成 Task23 的 SPEAK=0，因为 Task23绕过 adapter。
- **V2 reference audio**：正式 adapter使用 audio-slot prompt并会从环境、模型目录、cwd或 vendored asset寻找参考音频；O-C01固定路线要求 no-ref/no-TTS。产品链与 Task23非等价。
- **V2 24帧自动 context rebuild**：与同一持续 session/KV上下文目标冲突；每次真实重建会把产品 guard重新归零（当前为 1），Task23没有此行为。
- **V2 result semantic dedup**：Python `_texts_are_similar` 可在模型已 SPEAK 后抑制产品消息；Task17已判其与 V2冻结范围冲突。它不影响 PoC JSONL中的 `speak_count`。

Task23 的 3 秒 cadence 只判 `MODIFY`：Locked源码明确建议 1000 ms且实现一 push一 decision，但 ABI并未拒绝 3000 ms；在动态 A/B前不升级为确定 runtime冲突。

## 9. V2-ONLY

- “一次理解 → 三个人设 → 三批弹幕”的 persona ID、三批业务 schema、条数/225/350/500字预算和发送策略。
- generation/slot/硬超时证据字段、产品 IPC schema、错误/取消/复位策略。
- 用户选择的屏幕/音频源、隐私与原始媒体生命周期。
- 产品结果清洗、路由和 Overlay/发送池（本轮不审计其 UI实现）。

三人设三批并非全部自研：

- Official 可复用：一个持续 shared context、一次 SPEAK文字流、同一 prompt注入风格说明、单次输出多个结构化 item。
- Original 可复用：一次模型输出多个 `barrage_candidates` 的 prompt/parse思路和 profile prompt injection；不能复制 V1 fallback/语义去重。
- V2 current 已有：单次 perception JSON、最多三个 candidate、一个 active profile和 result/IPC路径。
- 真正 `V2-ONLY`：同一次理解中固定三 persona、每 persona独立一批、批次顺序/预算/发送语义。Task23 `build_prompt/validate_batches` 可作 fixture参考，但不能直接冒充产品实现。

## 10. UNCONFIRMED

- Task23 plain no-ref/no-TTS prompt虽然走 Locked明确分支，但其“证据不足即 LISTEN + 必须一次输出严格三批 JSON”是否显著压低 proactive SPEAK概率，尚无单变量真机证据。
- 3 秒媒体单元相对约 1 秒官方参考对 Q4_K_M 的具体概率影响；源码只能证明决策次数减少，不能证明它必然产生全 LISTEN。
- 今日真机结果中每条 `duplex_result.ok` 的真实分布未进入仓库；因此不能确认是否存在 failure-as-LISTEN。

## 11. Task23 Representativeness

结论：`PARTIAL`。

共享部分：完全相同的固定 GGUF组合、`llama.cpp-omni@b9d15b8` + project patch、CUDA provider、高层 duplex C API、token-level LISTEN/SPEAK解析和 no-TTS文字结果。这些结果可以证明或否定底层模型/runtime在该机器上的加载、媒体 decode、KV推进、C API决策、文字返回和同进程释放能力。

未共享部分：`IOmniRuntime`、`RealOmniRuntime`、capture/conversion/temp-media、Worker的 1秒/latest-only调度、产品 prompt/ref audio/force count、24帧重建、named pipe、Python清洗/去重和最终事件路由。因此 Task23不能直接证明正式 V2 的 capture、adapter、IPC、产品 lifecycle或最终可见消息正确。

代码证据：`tools/aijarvisv2-23/CMakeLists.txt` 直接链接 `jarvis::runtime_provider`；`poc_main.cpp` 直接包含 `omni.h` 并调用 `omni_*`；没有任何 `IOmniRuntime`、`Worker` 或 named-pipe引用。

## 12. LISTEN → SPEAK Root-Cause Candidates

### Candidate #1 — 3 秒 input unit 导致真实决策只有约 0.33 Hz

- confidence: **HIGH**（差异确定；对概率影响仍需 A/B）
- evidence: Locked C API严格一 push一 decode/result；locked test建议真实流式 `1000 ms`。Task23 offset和素材时长均为 3000 ms。20 秒 case实际只选中 offset 0～18 秒的 7 个 push，其中前三个由 guard强制 LISTEN，只剩 4 个自主决策。
- affected layer: Task23 fixture timing / duplex cadence
- minimal validation/fix: 只把同一 O-IN-07切为 1秒 decision units，保持模型、prompt、seed、总时长、C API和机器不变，先跑单个 P02 A/B。

### Candidate #2 — failed result 被统计为 LISTEN

- confidence: **MEDIUM**
- evidence: C result默认 `is_speak=false`，`ok=false` 表示 prefill/decode失败；Task23未在计数前检查 `ok`。今日 JSONL的 `ok` 分布未纳入仓库。
- affected layer: Task23 result parsing / evidence truthfulness
- minimal validation/fix: 回读现有 JSONL的 `ok`；后续 parser把 ERROR、LISTEN、SPEAK三态分开。

### Candidate #3 — strict three-batch system prompt降低 proactive speak倾向

- confidence: **MEDIUM**
- evidence: prompt结构满足 Locked plain no-ref分支，但内容同时要求“无充分证据即 LISTEN”和复杂严格 JSON。没有 Locked证据证明它与默认 proactive prompt分布等价。
- affected layer: prompt semantics, not template mechanics
- minimal validation/fix: cadence对齐后仍全 LISTEN时，才做同 cadence的默认 prompt/三批 prompt单变量 A/B。

### Candidate #4 — wait失败路径漏收 drain后的迟到结果

- confidence: **LOW**
- evidence: 正常路径按 push数持续 wait，完全消费 1:1 FIFO；只有某次 wait timeout后 break，`session_end`才会完成但丢弃未 pop的 done结果。
- affected layer: Task23 failure-path consumption
- minimal validation/fix: 仅在证据出现 `result_wait_failed` 时补 drain/result accounting。

已排除为当前首因：前三次 guard无限循环、`is_speak/is_listen`取反、TTS关闭、每 push只消费一次、频繁 session重建。Task23单 case分别是默认 guard只用三次、映射正确、no-TTS text可用、按 push数持续消费、无重建。

## 13. Minimum Change Recommendation

`NEXT BEST ACTION`：只在 Task23 fixture把 O-IN-07 的 runtime decision unit从 3 秒对齐为约 1 秒，并在同一台真机只重跑一个 `p02-standard-context20` 单变量 A/B；不改 V2产品、不升级模型/runtime、不同时改 prompt。

理由：它是 source-level 已确认的最大行为 Delta；20秒窗口会从 7次决策提升到约20次，前三次保护由约9秒恢复为 Locked参考的约3秒，同时复用官方 high-level C API和 V2现有1秒采集节奏。若对齐后仍全 LISTEN，再按候选 #2、#3顺序验证，不能并行改多变量。

预计下一步只涉及 `tools/aijarvisv2-23/run-aijarvisv2-23.ps1`、`tools/aijarvisv2-23/o-in-07-manifest.template.json` 和外部 O-IN-07 1秒切片/manifest；若选择在 harness内切片才涉及 `poc_main.cpp`。产品 C++、`IOmniRuntime`、adapter和 prompt均不应在该动作中修改。

## 14. Reuse / Replace / Keep / Delete-Later

| 对象 | 决定 | 理由 |
|---|---|---|
| Locked high-level duplex C API及 token parser | `REUSE` | 官方已提供 session、内部双 worker、FIFO、decision和drain |
| 原作者 downmix/window、DXGI/GDI、WASAPI底层 | `REUSE` / `MODIFY` | 低层轮子已有；只补 V2契约 Delta |
| Task23 manifest replay、JSONL/CSV、batch validator | `KEEP` | 合理测试 fixture，不进入产品 runtime |
| Task23 direct C API adapter | `KEEP` 到根因收敛；之后 `REPLACE` | 便于底层定点诊断，但正式代表性只有 PARTIAL |
| V2 24帧强制 context rebuild | `DELETE-LATER` | upstream已有滑窗/持续 session；当前会丢上下文并重置 guard |
| V2 reference-audio duplex prompt | `REPLACE`（后续任务） | 与 O-C01 no-ref/no-TTS路线冲突；本轮不改 |
| V1 fallback barrage与 semantic dedup | `DELETE-LATER` | 不是模型自主输出，且与 V2冻结语义冲突 |
