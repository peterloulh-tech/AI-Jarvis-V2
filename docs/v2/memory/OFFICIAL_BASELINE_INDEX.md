# Official Baseline Index

> 审计日期：2026-08-09。对应 Dashi 任务：`AIJARVISV2-23`。本文件只覆盖当前 Local O 路线，不代表未来模型选型。

> Task93 于 2026-08-11 按已批准的 Official-First 架构锁定当前维护基线：`tc-mb/llama.cpp-omni master@09f5c3f1b484759f17b06fc63574f749c89c8761` 与 `OpenBMB/MiniCPM-o-Demo main@d0a002093615b7f1d4d0f87a03fc01cb39bef3f6`；Demo 当前 C++ backend 默认取 `master/origin/master` 并构建 `llama-omni-server`。精确来源、许可与使用组件见 [`tools/o-official-reference/upstream-lock.json`](../../../tools/o-official-reference/upstream-lock.json)；下文 `b9d15b8` 与 `feat/web-demo@5202b7b2...` 只保留为 Legacy/冲突路线历史。

## 0. 使用规则

- 这是 MiniCPM-o 与 `llama.cpp-omni` 的第三方官方行为基线，不是官方文档镜像，也不是新的需求或实现规范。
- 执行事实优先使用本项目锁定的 repo、revision、文件哈希和实际源码；官网后续变化不能自动覆盖 Locked Baseline。
- 相同锁定版本下，后续任务默认先读本文件，不重复全量联网研究。只有第 5 节的触发条件成立时才重新查第一方来源。
- 标记 `CURRENT-OFFICIAL-ONLY` 的内容只代表 2026-08-09 当前官网、当前分支或当前示例，不能推定锁定 revision 或 V2 已具备。
- 第一方资料之间不一致时保留差异，不自行拼成一个“理想接口”。本文件只提炼以后开发、联调和排障会重复使用的信息。
- 复用类型：`DIRECT` 为可直接复用，`MODIFY` 为最小修改复用，`REFERENCE` 为只参考结构/时序，`V2-ONLY` 为 V2 当前专有实现。

## 1. MiniCPM-o 4.5

### 项目用途

Local O 的唯一在测模型：持续接收画面与音频，由模型自身决定 `LISTEN` 或 `SPEAK`，V2 只消费文字结果；当前 PoC 明确关闭 TTS，不用参考音频，不以业务触发壳替代模型自主决策。

### Locked Baseline

| 项目 | 锁定值 |
|---|---|
| 模型仓库 | [`openbmb/MiniCPM-o-4_5-gguf`](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf/tree/502eec5b03eaee9d0d2ce17a176e3490103c9a63) |
| revision | `502eec5b03eaee9d0d2ce17a176e3490103c9a63` |
| 量化组合 | Q4_K_M LLM + F16 vision projector + F16 audio projector |
| LLM | `MiniCPM-o-4_5-Q4_K_M.gguf`；`5,026,714,400` bytes；SHA-256 `1237a97ee081b8abebc47aa7dad565701e8f5f904cdc92f6723ac4281bbc0932` |
| Vision | `vision/MiniCPM-o-4_5-vision-F16.gguf`；`1,095,113,184` bytes；SHA-256 `1453678cc4e4fe18de241952962e234f265cb8dda780773526103ab8ba82f421` |
| Audio | `audio/MiniCPM-o-4_5-audio-F16.gguf`；`660,167,904` bytes；SHA-256 `d5b188ac7feaf98e17175c3f9bd14bf269301bfd187439fdaa3e3a494fc32ef7` |
| 总大小 | `6,781,995,488` bytes |
| 当前使用部分 | 画面、音频、双工控制和文字输出；`use_tts=false` |
| 明确排除 | TTS projector、token2wav、参考音频、语音输出 |

锁定依据为 Task22、Task23 provenance/manifest、现场包 README 与当前 runner 参数；不能用官网的新文件替换上述三件套。

### Current Official Reference

本次核对日期为 2026-08-09，主要第一方入口：

- [OpenBMB/MiniCPM-o 当前源码与 README（main `0dbb566d...`）](https://github.com/OpenBMB/MiniCPM-o/tree/0dbb566de090067266abb76e702fb289f09934c5)
- [MiniCPM-o 4.5 Technical Report](https://github.com/OpenBMB/MiniCPM-o/blob/0dbb566de090067266abb76e702fb289f09934c5/docs/MiniCPM_o_45_technical_report.pdf)
- [MiniCPM-o 4.5 官方 Model Card](https://huggingface.co/openbmb/MiniCPM-o-4_5)
- [MiniCPM-o 4.5 GGUF 官方 Model Card](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf)

当前官方源码 main 为 `0dbb566de090067266abb76e702fb289f09934c5`；它和锁定 GGUF revision 是不同仓库、不同时间点，只作当前参考。

### 官方能力

- Vision：视频/连续帧环境感知，与音频共享时间轴。
- Audio：连续环境音频和语音理解；官方 Python 示例以 `16 kHz` 单声道为输入。
- Realtime / continuous input：按时间片连续送入画面和音频，推理期间继续感知环境。
- Full duplex：模型可以一边接收新输入一边输出；不是“先完整听完再回答”的半双工回合。
- Proactive interaction：用户请求只是环境事件之一，模型自行判断是否、何时以及说什么；V2 不应另造关键词触发器代替该判断。
- Text / speech output：官方完整路线可同时输出文字与语音；V2 Locked Baseline 只启用文字。
- Context / session：同一个 streaming/duplex 上下文累积 KV 和连续输入，不能把每个时间片当作独立聊天请求。

### 官方输入/输出与关键格式

- 技术报告把每个时间片组织成视觉、音频、输出三条同步流；未输出时产生专门的 listen 控制状态。
- Listen-Speak 机制先预测二元 `listen/speak` 控制，再在 `speak` 时生成内容。官方报告认为这种控制与内容分离比把 listen 当普通文本更稳定。
- 官方报告和 Demo 以约 `1.0 s` 时间片、约 `1 Hz` 决策为主要实时口径；0.1/0.2 秒切片在报告消融中更差。
- 当前 Python 示例以 16 kHz 单声道音频和同时间片视频帧调用 `streaming_prefill`，再调用 `streaming_generate` 得到 listen 或输出。
- Locked V2 runtime 接口不是内存 PCM/JPEG 协议：每次 push 传入 WAV/JPG 文件路径、`max_slice_nums` 和 `user_seq`；格式转换责任仍在上游。
- Locked V2 输出为控制状态加文字；TTS 关闭时仍可返回文字。不能把空文字直接等同于失败，必须同时看 listen/speak 控制和错误状态。

### 初始化与生命周期

Locked V2 使用三个模型文件初始化 `omni_context`，设置 async/duplex 和 prompt 后建立一次持续 session。固定 Task23 关键参数：

- `n_ctx=4096`、`n_batch=512`、`n_ubatch=256`、`n_predict=1024`、`n_gpu_layers=99`、seed `42`；
- `media_type=2`、`use_tts=false`、`async=true`、`duplex_mode=true`；
- 无参考音频；同一 context 内 begin → 多次 push/wait → end。

`CURRENT-OFFICIAL-ONLY`：当前官方 PyTorch 示例使用 `model.as_duplex()`，再以 `prepare(...)` 初始化 system prompt/可选参考音频，循环 `streaming_prefill` 与 `streaming_generate`。这不是 V2 当前 C API。

### Duplex / proactive 行为

- 技术报告的核心不是外部“轮到助手”信号，而是每个时间片由模型预测 listen/speak。
- Locked runtime 默认 `force_listen_count=3`、`listen_prob_scale=1.0`；前三次 decode 的强制 listen 是启动保护，之后应回到模型自主决定。它不能解释无限期 LISTEN。
- Locked runtime 默认 `max_new_speak_tokens_per_chunk=26`。该值约束单片 speak 输出，不等同于 V2 三批业务预算。
- 当前官方 Demo 同样把 `force_listen_count=3` 描述为最初约三秒的启动保护，并允许按片显式覆盖；后续由模型决定。
- 模型可以在说话期间继续接收环境输入。V2 未来排障不能在出现首个 speak 后默认停止输入。

### Prompt / role / session 关键约定

- 当前官方 Demo 的完整语音参考模板为：`<|im_start|>system\n{system text}\n<|audio_start|>` + 参考音频 + `<|audio_end|><|im_end|>`；processor 会把普通 system 文本包装成该结构。
- Locked `llama.cpp-omni` 对“无参考音频、无 TTS”存在明确分支：直接 eval voice/system prompt 与 assistant prompt，再固定 prefix/KV；因此 V2 的纯文字 system prompt 不是仅凭模板差异即可判错。
- Locked begin 负责 index `0` 的 system 初始化，后续媒体时间片必须使用连续输入路径；同一 session 不应重复注入 system prompt。
- `system_prompt_initialized` 和 `n_keep` 用于避免重复初始化并保护 system prefix。结束 session 后上下文不能无条件当成新 session 继续复用。
- 尚无第一方证据证明“当前 Demo 的带 audio-slot 模板”和“Locked runtime 的无 TTS 纯文字分支”在主动发言概率上完全等价，保留为未确认项。

### 官方限制

- 官方 Model Card 明确 full-duplex 基础能力仍有提升空间，语音可能误读，中文/英文混杂场景可能不稳定。
- 官方 Web Demo 可能有延迟和输出碎片；Demo 行为不是产品级时延承诺。
- 当前完整 PyTorch/CUDA Demo 与 GGUF/C++ 路线的显存、依赖和输出链不同，不能互换其性能结论。
- `CURRENT-OFFICIAL-ONLY`：当前完整 C++ 示例通常包含 TTS projector、token2wav 和参考音频，并给出 12 GB 最低、16 GB 推荐等说明；V2 锁定三文件 no-TTS 包未因此升级或扩包。

### 对 V2 有价值的官方示例入口

- [官方 Model Card 的 full-duplex Python 示例](https://huggingface.co/openbmb/MiniCPM-o-4_5)
- [官方 Hugging Face 模型实现](https://huggingface.co/openbmb/MiniCPM-o-4_5/blob/main/modeling_minicpmo.py)
- [官方 Demo](https://github.com/OpenBMB/MiniCPM-o-Demo)
- [官方 README 指向的 MiniCPM-o 4.5 Cookbook](https://github.com/OpenSQZ/MiniCPM-V-CookBook)

只按具体问题打开命中的示例，不复制整套仓库或 Cookbook。

### 当前仍未确认的问题

- 锁定三文件 no-TTS 组合在当前 system prompt 下，是否与官方训练/演示使用的 proactive prompt 分布一致。
- Locked runtime 与锁定 GGUF 对 3 秒媒体槽位的实际行为；官方主参考是 1 秒时间片。
- listen/speak 长期失衡时，究竟是 prompt、媒体节奏/格式、模型量化还是 runtime 控制路径造成；本轮不作修复归因。

## 2. MiniCPM-o-Demo

### 定位与当前版本

MiniCPM-o-Demo 是 OpenBMB 模型团队提供的官方参考实现，不是 V2 的锁定运行依赖。2026-08-09 核对：

- [main `d0a00209...`](https://github.com/OpenBMB/MiniCPM-o-Demo/tree/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6)：当前 PyTorch/CUDA realtime 实现和新 backend/runtime 协议；
- [Comni `9af4308a...`](https://github.com/OpenBMB/MiniCPM-o-Demo/tree/9af4308a93ca889ddf5c7c7bde1bcfbb6ff9b147)：与 `llama.cpp-omni` HTTP/SSE server 对接的 C++ backend 参考。

两者不是同一提交，均标记为 `CURRENT-OFFICIAL-ONLY`，不可写成 Locked V2 行为。

### 官方 Demo 架构与数据流

PyTorch 主路径：

`WebSocket gateway / session affinity → GPU-exclusive Worker → prepare → 每秒 audio + optional video → streaming_prefill → streaming_generate → is_listen 或 text/audio → WebSocket result`

- Gateway 负责路由、排队和 session affinity；一个 Worker 在完整 session 内独占一张 GPU。
- Worker 保存 duplex active/paused、模型 KV、输入时序和输出队列；结束时 stop/cleanup 并释放 GPU cache。
- 每个时间片先 prefill，再 generate；上一片的 deferred finalize 必须在下一次 prefill 前完成。
- 持续输入以约 1000 ms、16 kHz 单声道音频为基准，并附带同时间片的零或多帧画面。
- 输出包含 `is_listen`、text、可选 audio、end-of-turn 和耗时/KV 指标；主动输出由模型结果到达，不靠 gateway 触发。

### Backend / worker / session

- [`core/schemas/duplex.py`](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/core/schemas/duplex.py) 固化当前示例的 1000 ms/16 kHz、prompt 包装、初始 force-listen 和 LS 参数。
- [`worker.py`](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/worker.py) 和 [`runtime/session.py`](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/runtime/session.py) 保存 Worker/session 生命周期；暂停超时默认约 60 秒，finally 路径负责清理。
- 当前 main 把 Transport、Runtime、InferenceBackend、Engine 分层，协议原语为 push/pull/close；这是值得参考的职责边界，不是要求 V2复制整套服务。
- `CURRENT-OFFICIAL-ONLY`：main 的 backend 协议以每个 push 一个 time slice，音频为 base64 raw float PCM（当前实现为 native-endian float32、16 kHz、mono），视觉为 base64 JPEG 数组，并可带 `force_listen`。该格式尚不能覆盖 Locked V2 的 WAV/JPG 路径接口。

### Realtime API 与主动输出

- PyTorch Demo 的客户端入口是 `/ws/duplex/{session_id}`；session 创建后 prepare，随后不断发送媒体片并接收异步结果。
- listen 是合法结果，不是空响应；speak 才包含文字/音频增量。调用端必须持续读输出队列，不能只在 push 后同步取一次。
- 初始 `force_listen_count=3` 后，模型预测 `<|listen|>` 或 `<|speak|>`。特别 token 和输出结束 token由模型实现解析，不应当作普通正文上传。
- mode switching、pause/resume 和主动发言都属于 session 状态，不是为每个片段重新初始化模型。

### Comni / C++ backend 连接方式

`CURRENT-OFFICIAL-ONLY` 的 Comni 路径：

`WebSocket gateway → Demo Worker → llama-omni-server /backend → session.init / input.append / session.close → session/output events`

当前 `llama-omni-server` 也保留供薄集成直接使用的 HTTP/SSE 接口：

- `POST /v1/stream/omni_init`
- `POST /v1/stream/update_session_config`
- `POST /v1/stream/prefill`
- `POST /v1/stream/decode`（SSE）
- `WebSocket /backend`
- `POST /sessions/:session_id/close`

参考入口：

- [当前 C++ backend compose](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/docker-compose.cpp.yml)
- [当前 C++ backend Dockerfile](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/docker/Dockerfile.cpp-worker-backend)
- [当前 Worker](https://github.com/OpenBMB/MiniCPM-o-Demo/blob/d0a002093615b7f1d4d0f87a03fc01cb39bef3f6/worker.py)

当前 server 的 `/backend` session close 会停止推理并通过 `omni_prepare_for_reuse` 清理/复用官方 context。Task93 活动路线只直接复用 `/backend` 的 SessionManager、协议事件和 close/reuse 生命周期，不另建 Session Manager；HTTP/SSE 仅作为上游现存接口记录，不进入活动链。

### 官方实现中的已知差异/限制

- Demo 容器入口检查完整 TTS/projector/token2wav 布局；Task93 活动 profile 固定 `use_tts=false`，当前 server 源码实际只要求 LLM/audio/vision 三文件，因此不把可选 TTS 文件误报为活动缺口。
- Demo main 通过 `LLAMA_OMNI_REFSPEC=master`、`LLAMA_OMNI_REF=origin/master` 跟随 runtime；Task93 以两仓当前 HEAD 精确锁定来获得可复现性。

## 3. llama.cpp-omni

### Locked Baseline

| 项目 | 锁定值 |
|---|---|
| runtime repo | [`tc-mb/llama.cpp-omni`](https://github.com/tc-mb/llama.cpp-omni/tree/b9d15b83ee353b2eaeee4d9318c98a35a1347486) |
| commit | `b9d15b83ee353b2eaeee4d9318c98a35a1347486`（2026-07-07 UTC） |
| archive SHA-256 | `f8505a9179ff4b8e3ca648c4d462ad46edcc7698507ab3717bc3ee840f45710c` |
| V2 patch | `third_party/runtime/patches/0001-text-input-runtime.patch` |
| patch SHA-256 | `cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e` |
| V2 执行入口 | vendored C API `tools/omni/omni.h/.cpp`，Task23 runner 直接调用；不是 HTTP Demo |

本地 `third_party/runtime/VENDOR.json` 是锁定来源事实。固定 patch 是 Locked Baseline 的组成部分，比较官网源码时必须保留。

### Current Official Reference

- [当前 master `09f5c3f1...`](https://github.com/tc-mb/llama.cpp-omni/tree/09f5c3f1b484759f17b06fc63574f749c89c8761)（2026-08-07 UTC）
- [当前 README](https://github.com/tc-mb/llama.cpp-omni/blob/09f5c3f1b484759f17b06fc63574f749c89c8761/README.md)
- [README 所指 web-demo 分支 `5202b7b2...`](https://github.com/tc-mb/llama.cpp-omni/tree/5202b7b2f4d11f50b9f996161e7a2f8b8571b890)

`feat/web-demo@5202b7b2...` 只保留为冲突路线历史；Task93 当前活动接口以 `master@09f5c3f1...` 的 `llama-omni-server` 为准。

### 模型目录

- Locked V2 no-TTS：LLM GGUF、vision projector、audio projector 三个明确路径；不要求 TTS projector/token2wav/ref audio。
- `CURRENT-OFFICIAL-ONLY`：当前完整 CLI/server 示例通常把 LLM、audio、vision、TTS projector、token2wav 放在同一模型目录，并可配置参考音频。
- 当前 server 可从 LLM 路径推导同目录文件；V2 不能依赖该推导覆盖 manifest 中的精确路径和哈希。

### 初始化

Locked C API 顺序：

1. 填充模型路径、context/batch/GPU 参数并 `omni_init`；
2. 设置 `async=true`、`duplex_mode=true`、no-TTS 与 prompt；
3. `session_begin` 初始化 index `0` system prefix；
4. 启动输入 push 和结果 wait；
5. `session_end` 排空 in-flight 后停止；
6. 释放 context。

双工依赖 async；不能在已经开始媒体输入后反复重建 prompt/KV。

### Audio / vision

- Locked `omni_duplex_frame` 接收音频和画面文件路径、切片参数和序号。上游必须提供 runtime 可解码的 WAV/JPG，而不是直接传 PCM 指针。
- 官方实时参考是 16 kHz 单声道、约 1 秒音频片，同时间片附带画面；current server/Comni 负责把网络输入写成/转换成 runtime 所需媒体。
- Vision 可按帧持续输入；无画面片与含画面片要通过明确字段表达，不能靠错误路径隐式表示。

### Continuous input

- Locked runtime 的 push 通常立即入队；pending queue 上限为 64，满时阻塞等待空位以避免无界增长。prefill worker 与 decode worker 分离，但通过 sequence/KV 保持严格 FIFO。
- 每次 push 需要唯一、单调的 `user_seq`；wait 从结果 FIFO 取下一结果。输入生产和结果消费应长期并行。
- `session_end` 是 drain，不是立即 cancel：它等待已接收片段完成。紧急中断需要使用专门中断/清理语义，不能把 end 当取消。
- `CURRENT-OFFICIAL-ONLY`：Comni Worker 采用小队列并丢旧片以保实时；这不属于 Locked runtime 本身。

### Session / lifecycle

- 一个 duplex session 持有 context/KV、system prefix、pending input、result queue 和 worker 线程。
- 正常生命周期必须配对 begin/end；end 后再复用同一 context 前需要确认 KV 和线程已经清理。
- 当前 HTTP server 增加 session close/reuse 清理路径；V2 Task23 未采用它，不能用 HTTP close 的行为替代 C API 验证。

### Realtime / duplex

- 当前官方 README 将实时路径描述为：index `0` prefill system/ref audio，index `>0` 连续 prefill 媒体，decode 返回 listen/speak；建议约每 1000 ms 一片。
- Locked C API 在 session 内并行处理 push/wait，允许模型说话期间继续 prefill。
- 默认初始 force-listen 为 3；它只保护启动阶段。若更多时间片持续 LISTEN，应检查实际控制 token、prompt、输入节奏/格式和模型行为，而不是无限增加补调用。

### Output / result

- Locked `DuplexResult` 包含 sequence、成功状态、`is_speak`、文字和延迟；上层应按 sequence 关联输入与结果。
- Locked runtime 把内部 `ended_with_listen` 映射为 `is_speak`，并从正文剥离 `__IS_LISTEN__`、`__END_OF_TURN__` 等控制标记。
- TTS 关闭不关闭文字；speech/audio drain 是另一条可选输出链。
- 当前 HTTP/SSE 示例使用 `content`、`is_listen`、`stop` 并以 `[DONE]` 收尾；这是 API 表达层，不是 Locked C struct。

### LISTEN / SPEAK 或等价机制

- 模型先生成 listen/speak 控制，再决定是否生成内容；runtime 必须在 token 层解析，不能只用“文本是否为空”推断。
- Locked runtime 的 `is_speak` 与 server 的 `is_listen` 方向相反；适配时必须显式映射，避免布尔值直传造成语义反转。
- 初始三次强制 LISTEN 后仍无限 LISTEN，不符合“启动保护后自主决策”的官方定义，但不自动证明 runtime 有 bug。
- 当前 Task23 已观测到 push 成功和 context 增长，只能证明输入进入并推进 KV；不能证明媒体格式、时间节奏或 prompt 已与官方分布完全对齐。

### CLI / API / config 关键参数

Locked V2 当前直接相关参数：模型三路径、`n_ctx/n_batch/n_ubatch/n_predict`、GPU layers、seed、async、duplex、use_tts、system/voice prompt、assistant prompt、`force_listen_count`、`listen_prob_scale`、每片最大 speak token、媒体路径、slice 数和 sequence。

`CURRENT-OFFICIAL-ONLY` 的 CLI/server 主要入口：`llama-omni-cli`、`llama-omni-server`，模型目录、ctx、GPU layers，以及 HTTP omni_init/prefill/decode SSE 和 `/backend` session 协议。Task93 已固定准确 commit 与活动请求 schema。

### 与官方 MiniCPM-o-Demo 的连接方式

官方 Demo main 由 Worker 转发 runtime WebSocket 到 `llama-omni-server /backend`；Task93 的极薄 reference route 直接使用同一 `/backend` 协议与 HTTP session close，复用官方 SessionManager 和 `omni_prepare_for_reuse`，不复制 Demo gateway/worker/session 层。V2 只转换固定 WAV/JPEG 为 `input.append` 所需 float32 PCM/JPEG base64，并收集官方事件用于三批契约和证据。

### 官方限制与当前未确认项

- 当前仓库快速迭代；README、master、web-demo 和 Demo Comni 分支存在版本指向差异，必须锁定后才能采用。
- 当前服务端 model directory、session config 和清理行为未在 V2 Locked C API 路线上验证。
- Locked runtime 的控制 token解析与锁定 GGUF 是否在所有输入格式下稳定，仍需真机证据。
- Task23 O-IN-07 使用 3 秒槽位，而官方参考为约 1 秒时间片；这是与后续 LISTEN/SPEAK 排查直接相关的疑似差异，本任务只记录不修改。

## 4. 原作者复用对应关系

本节只索引 AIJARVISV2-17/18 的既有结论，不重新审计 V1。详细分级仍以 [`v1-source-reuse-matrix.md`](../requirements/v1-source-reuse-matrix.md) 和 [`v1-ui-resource-config-test-reuse-matrix.md`](../requirements/v1-ui-resource-config-test-reuse-matrix.md) 为准。

| 官方能力 / runtime 行为 | 原作者对应模块 | V2 当前对应模块 | 类型与使用规则 |
|---|---|---|---|
| 16 kHz mono 音频预处理 | `audio::downmix_mono`、`ExactWindowAssembler` | Task23 使用固定 WAV 资产 | `DIRECT`；真实采集接入时优先提取，不重写 |
| 有状态音频重采样 | V1 linear resampler | 当前 PoC 无在线转换 | `MODIFY`；补跨块状态后复用 |
| WASAPI 持续音频采集 | V1 WASAPI capture | 当前 PoC 无设备采集 | `MODIFY`；只按任务需要迁移 |
| DXGI/GDI 持续画面采集 | V1 desktop capture | 当前 PoC 使用固定 JPG | `MODIFY`；保留 fallback，避免整套 UI 迁移 |
| runtime 公共边界 | `IOmniRuntime` | Task23 直接用 locked C API | `MODIFY`；接口可复用，产品语义以后按 V2 Delta 对齐 |
| 模型初始化/布局校验 | `RealOmniRuntime` + model layout | Task23 manifest/provenance + runner | `MODIFY`；复用校验思路，不复用临时落盘副作用 |
| duplex begin/push/wait/end | `RealOmniRuntime` | Task23 producer/consumer/session guard | `MODIFY` / `V2-ONLY`；以 Locked C API 时序为准 |
| 持续输入调度 | V1 capture/input/result workers | Task23 时间轴 producer + result consumer | `REFERENCE`；V1 LatestOnlyScheduler 不直接迁移 |
| session / lifecycle | V1 Worker、runtime context | Task23 单持续 session | `REFERENCE`；V2 自己承担代次、停止、排空和清理 |
| listen/speak 结果回传 | `DuplexResult` 与 Worker callback | Task23 JSONL/CSV 结果链 | `MODIFY` / `V2-ONLY`；显式映射 `is_speak`/`is_listen` |
| IPC frame/CRC | V1 named pipe + `ipc::crc32` | Task23 当前无产品 IPC | CRC `DIRECT`，frame/named pipe `MODIFY`；schema 冻结后再用 |
| backend 进程生命周期 | V1 backend process manager | Task23 同进程 runner | `REFERENCE`；以后按 V2 进程边界实现 Delta |
| 原始音画临时文件 | `RealOmniRuntime` 写 BMP/WAV | Task23 固定回放文件 | `REFERENCE`；因隐私/生命周期风险不得原样迁移 |
| Overlay/UI/安装包 | Task18 对应模块 | 与本基线无关 | 不纳入本数据链，不为 Reuse-First 重审 |

原作者实际链路摘要：Worker 从 DXGI/WASAPI 取画面和 PCM，音频 downmix/resample/window 后交给 `IOmniRuntime`；duplex 输入 worker 调 `push_duplex`，结果 worker 调 `wait_duplex`，同一 runtime context/KV 保持 session，结果经 callback/event/IPC 上返。与 O 接入最直接的入口是 `native/include/jarvis/runtime.hpp`、`native/src/omni_runtime.cpp`、`native/src/worker.cpp` 和 locked `tools/omni/omni.h/.cpp`。

## 5. Re-check Triggers

只有以下情况重新联网核对第一方官方来源：

1. model revision 改变；
2. runtime revision 或本地 patch 改变；
3. API、协议或依赖版本改变；
4. 当前任务需要的信息在本基线中不存在；
5. 实际行为与本基线冲突；
6. 有具体理由怀疑官方已修复或改变某个直接相关行为。

其余情况默认使用本文件和锁定源码，只读取当前任务相关模块；不得为了执行 Reuse-First 再做一次全项目或全官网审计。
