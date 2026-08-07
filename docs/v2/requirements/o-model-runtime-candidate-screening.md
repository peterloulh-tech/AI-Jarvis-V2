# AI Jarvis V2 O 模型与运行时候选筛选

> Dashi：AIJARVISV2-22
>
> 评审日期：2026-08-07
>
> 功能基线：`AI_Jarvis_V2_总需求_功能需求正式冻结版_v1.0.md`，SHA-256 `2b9f2bd67bcd4d0e1c510b35b961411c0445e0e4bc9f4da768f237c9073f6d46`
>
> 非功能基线：`AI_Jarvis_V2_非功能需求_正式冻结版_v1.0.md`，SHA-256 `3f04ecaa48298517692a814d1e0004a042e853b35a825fb360ad987f835084dd`

本文件只筛选进入 O10 PoC 的模型与运行时组合，不冻结最终模型、量化、运行时或性能门槛。PoC 通过也不等于最终选型、可分发安装包或同机高负载游戏承诺；后续判定继续复用 [O 模式方案](o-mode-acceptance-and-benchmark-plan.md) 与既有记录模板。

## 1. 证据与判定规则

### 1.1 固定证据

| ID | 原始或项目内证据 | 本任务使用范围 |
|---|---|---|
| E-01 | `openbmb/MiniCPM-o-4_5-gguf@502eec5b03eaee9d0d2ce17a176e3490103c9a63` 的[固定模型卡](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf/blob/502eec5b03eaee9d0d2ce17a176e3490103c9a63/README.md)及 [`model_download.py`](../../../src/jarvis_backend/model_download.py) | Apache-2.0 声明；三项模型文件的 revision、字节数与 SHA-256 |
| E-02 | [`VENDOR.json`](../../../third_party/runtime/VENDOR.json)固定 `tc-mb/llama.cpp-omni@b9d15b83ee353b2eaeee4d9318c98a35a1347486`、归档 SHA-256 与 patch；[固定上游许可](https://github.com/tc-mb/llama.cpp-omni/blob/b9d15b83ee353b2eaeee4d9318c98a35a1347486/LICENSE) | MIT 运行时源码边界和可复现来源 |
| E-03 | 固定源码 [`omni.h`](../../../third_party/runtime/vendor/tools/omni/omni.h) 与 [`test-duplex.cpp`](../../../third_party/runtime/vendor/tools/omni/test/test-duplex.cpp) | `session_begin/push_frame/wait_next_frame/session_end`、有界队列、`SPEAK/LISTEN` 决策、文本结果和 `--no-tts` 接口 |
| E-04 | [任务 19 四层许可审计](v1-runtime-model-third-party-license-audit.md)的 `LIC-01～03` 与[任务 21 阶段门](v1-open-source-asset-reuse-final-audit.md) | 当前 V1 provider、参考音频、随包 notice 与模型包材料的阻断边界 |
| E-05 | Qwen 官方仓库固定提交 [`d8a31ca`](https://github.com/QwenLM/Qwen2.5-Omni/tree/d8a31ca56c0456b6edfcbcbf4bdbb6ae2200ef42)的 [README](https://github.com/QwenLM/Qwen2.5-Omni/blob/d8a31ca56c0456b6edfcbcbf4bdbb6ae2200ef42/README.md) 与 [Apache-2.0 LICENSE](https://github.com/QwenLM/Qwen2.5-Omni/blob/d8a31ca56c0456b6edfcbcbf4bdbb6ae2200ef42/LICENSE) | 官方代码接口、量化路径、TTS 关闭方法和厂商显存数据；不替代权重仓库许可与 revision |
| E-06 | [离线安装 NFR](offline-install-update-nfr.md)、[Windows NFR](windows-compatibility-nfr.md)、[性能场景](performance-benchmark-scenarios.md) | Windows 11 64 位/NVIDIA、自包含离线、16GB 独占与 P1 记录口径 |

仅把有固定模型与运行时身份、模型/代码许可均清楚、核心推理可断网、单模型可同时接收音画并输出文字的组合标为 `POC`。`HOLD` 表示有价值但任一硬证据未闭环，不得进入 PoC；`REJECT` 表示违反冻结范围或硬门。厂商数据只决定是否值得实测，不记为本项目通过证据。

### 1.2 八项筛选门

| 门 | PoC 准入要求 | 最终选型追加要求 |
|---|---|---|
| G-01 许可与来源 | 模型、运行时代码有固定 revision、原始许可和哈希/归属入口；权利不明项为 0 | 最终模型包、运行时及依赖 notice/SBOM 完整回放 |
| G-02 核心离线 | 权重和运行时可预置，断网执行不需要账号、API 或下载 | 干净目标机完整安装后 NET 外连与下载为 0 |
| G-03 单模型结构 | 同一模型权重承担持续音画理解、触发决策和文字生成 | 单实例、单持续会话、单文字生成流有运行日志 |
| G-04 持续音画 | 有持续/分块音频和画面输入接口；生成期间输入是否继续可测 | O-IN-07 生成前/中/后输入标记完整且不断流 |
| G-05 自主触发 | 模型原生决策或可评审等效接口明确；不得另加检测模型或业务触发壳 | 同一会话原始结果证明模型决定输出或沉默 |
| G-06 文字与 TTS | 可关闭音频生成并取得文字；三批结构可由一次生成请求验证 | TTS 调用为 0，三个批次一次生成、逐批校验，不补调用 |
| G-07 16GB/Windows | 有 Windows 11 x64/NVIDIA 构建路径，制品规模允许进行 16GB 探索 | 16GB 独占真机与自包含安装均有实际证据 |
| G-08 停止与隔离 | 会话可结束、模型可释放，且能置于可终止子进程 | 取消、硬超时、重建、强制终止、显存释放和孤儿 0 均实测 |

## 2. 候选矩阵与淘汰理由

| ID | 模型 + 运行时 | 许可/离线证据 | 接口与 16GB/Windows 证据 | 结论 |
|---|---|---|---|---|
| O-C01 | MiniCPM-o 4.5 GGUF Q4_K_M + 固定 `llama.cpp-omni` CUDA 源码构建，TTS 关闭 | E-01/E-02：权重 Apache-2.0、运行时 MIT；三项权重共 `6,781,995,488` 字节且可预置；离线模型包材料仍受 `LIC-03` 约束 | E-03：双工 `push_frame` 与并行结果等待，模型返回 `SPEAK/LISTEN + text`；`use_tts=false`；固定源码含 MSVC/Windows 与 CUDA 分支。16GB 实占、取消和自包含包待测 | `POC`：唯一进入任务 23；只批准验证，不批准 V1 provider、模型包或最终选型 |
| O-H01 | Qwen2.5-Omni-7B GPTQ-Int4 + Transformers `4.52.3`/gptqmodel `2.0.0` | E-05 证明官方代码 Apache-2.0、可本地加载及 4-bit 路径；本次未固定权重仓库 revision、权重许可副本、文件清单与哈希 | 官方接口支持音画输入、`disable_talker()`/`return_audio=false`；厂商数据为 15 秒 `11.64 GB`、30 秒 `17.43 GB`，20 秒与 Windows 自包含包未知；只见显式 `generate`，无模型自主触发接口证据 | `HOLD`：G-01/G-05/G-07 未闭环，不进入 PoC；缺口全部关闭后重新评审，不能自动替补 |
| O-X01 | Qwen2.5-Omni-3B BF16 + Transformers | E-05 只证明官方代码许可，权重仍未在本项目固定 | 官方 15 秒最低显存 `18.38 GB`，并注明实际通常至少为理论值的 1.2 倍；已超过 16GB 独占边界 | `REJECT`：G-07 失败，不因参数量较小保留 |
| O-X02 | V1 当前 MiniCPM provider/桌面包原样复用 | 模型和主代码许可已知，但 `LIC-01～03` 证明参考音频、随包 notice 与模型包材料未闭环 | 会复制默认参考音频，当前构建仍编入 TTS/token2wav；临时 BMP/WAV、调度和生命周期不满足 V2 | `REJECT`：G-01/G-02/G-06/G-08 失败；任务 21 黑名单保持不变 |

联网 API 因 G-02、视觉/音频/LLM 多模型拼接因 G-03、纯视觉或纯音频模型因 G-03/G-04 在长名单入口直接排除，不再扩成候选资产。浮动 `main/latest`、无权重哈希、仅有模型名称或厂商宣称的组合均不得进入矩阵。

## 3. O-C01 PoC 契约

### 3.1 固定身份与许可前检

1. 只取得 E-01 的三项文件并逐项验证完整 SHA-256；不得下载 TTS/projector/参考音频。模型包同时保存 Apache-2.0 文本、固定模型卡、revision、归属、量化和“上游无独立 NOTICE”记录，否则 PoC 结论为`阻塞`。
2. 运行时只从 E-02 的归档和固定 patch 构建独立 Windows x64 CUDA 测试进程。构建清单与文件访问证据必须证明 `use_tts=false`，未加载 TTS/token2wav 权重且未读取 `default_ref_audio.wav`；当前 V1 provider/安装包不得作为替代。
3. 断网启动前记录模型、运行时、依赖、驱动和输入资产哈希；执行期间任何账号、DNS、HTTP 或在线下载需求都使核心离线判定失败。

### 3.2 自主触发与组合能力验证

持续输入线程只按 O-IN-07 时间轴提交音频/画面 chunk，不提交“现在说话”的业务请求。每帧由同一模型在双工会话内返回 `SPEAK` 或 `LISTEN`；只有该控制决策可记为原生自主触发。定时调用独立 `generate`、帧差/音量/句末触发、额外检测模型或外部规则均不合格。

当模型返回 `SPEAK` 时，同一次文字生成必须按提示输出可解析对象 `{batches:[{style_id,items}, ...]}`，且恰有三个批次；解析器只校验、截断或丢弃，不补调用。TTS 开关、线程/模块加载和输出调用计数均须为 0。结构失败保留原始响应并判失败，不能用二次整理伪装通过。

生产线程必须在一次文字生成前、生成中和生成后继续提交带序号 chunk；消费线程记录 `user_seq/frame_id/is_speak/text/ms_*`。队列阻塞、丢帧、磁盘中转和上下文停更都如实记录。`session_end` 的 drain 不等于取消；PoC 另以独立子进程验证会话关闭、超时终止、进程退出、重新加载和停止后显存/PID，不能沿用 V1 生命周期结论。

### 3.3 执行与出口

| 步骤 | 复用入口 | 必须交付的结果 |
|---|---|---|
| P-01 固定与构建 | E-01～04、G-01/G-02 | 模型/源码/patch/构建哈希、许可材料清单、TTS/参考音频排除证据、断网构建后运行说明 |
| P-02 组合闭环 | O-IN-07、O10 第 4 节 | 单实例/会话/生成流，持续音画时间轴，原生 `SPEAK/LISTEN`，三批文字，TTS 0；每项给出通过/失败/阻塞 |
| P-03 停止恢复 | O09、任务 4 既有故障记录 | 会话结束、取消差距、硬超时进程终止、重建、旧代次、显存释放和孤儿进程证据 |
| P-04 数据记录 | BENCH-001～005、既有 CSV | 16GB 独占、三档、自定义预算、忙碌单槽、15/20/30 秒上下文的原始数据与 P50/P95 |

只有 P-01～04 均完成，且持续音画、自主触发、TTS 关闭、三批文字与停止清理没有 P0 失败，O-C01 才可提交后续 16GB 基线任务。失败或阻塞时保留原始证据并触发选型风险评审；不得在本任务启用 O-H01、修改冻结行为或启动后续任务。

## 4. P1 数据计划

不新增模板。每个 `model + revision + quantization + runtime + runtime revision + Windows build + GPU/driver + context_seconds + tier/budget` 建立独立 `sample_group`，填写既有 [`performance-sample-record.csv`](templates/performance-sample-record.csv)；显存、GPU、内存、句柄、队列和停止后基线写入 [`resource-trend-record.csv`](templates/resource-trend-record.csv)。

| 数据组 | 场景/校准项 | 记录重点 | 结论边界 |
|---|---|---|---|
| 身份与加载/停止 | CAL-002、CAL-005；BENCH-020/023 | 加载、首次就绪、停止、卸载、显存释放、PID/孤儿 | 清理结果可判；耗时门槛待校准 |
| 16GB 独占 | CAL-006；BENCH-001 | 初值/峰值/末值、P50/P95、GPU busy、失败/超时分母 | 不外推同机游戏能力 |
| 三档与忙碌 | CAL-007/008；BENCH-002/003 | 12/8/6 秒、3～6/6～9/9～15 条、首输出/完整结果、单槽覆盖 | 冻结结构逐轮判；性能只留数据 |
| 自定义与上下文 | CAL-009/010；BENCH-004/005 | 225/350/500 字与 12/16/20 秒；15/20/30 秒对比 | 不修改超时或约 20 秒默认目标 |
| O10 组合能力 | CAL-026/027；O-IN-07 | 生成前/中/后输入、`SPEAK/LISTEN`、三批原文、TTS/额外调用数 | 只判可行性和证据完整性 |

4 小时正式与 8 小时内部窗口仍复用 BENCH-019；本筛选任务不执行也不推定通过。所有未校准延迟、吞吐、资源峰值/斜率、恢复耗时和质量结果均保持`待实测/待评审`。

## 5. 风险、缺口与覆盖

| 风险/缺口 | 当前处理 |
|---|---|
| R-01 固定 upstream 的普通 `omni` 目标仍含 TTS/token2wav 源，V1 打包还复制无权利参考音频 | O-C01 仅在专用 TTS 关闭测试构建和文件访问检查通过后运行；不得发布或沿用 V1 包 |
| R-02 双工 API 使用音频/图片路径，可能产生原始 BMP/WAV 落盘 | PoC 仅使用已许可测试夹具并记录 FS；最终选型前必须提供内存输入和异常退出清理证据 |
| R-03 `session_end` 是 drain，不是生成取消 | 进程边界验证硬终止/重建；正式取消契约仍由后续实现任务冻结 |
| R-04 三批 JSON 是提示与校验目标，不是受约束解码保证 | PoC 保留格式失败率与原始响应，不补调用、不提前宣称通过 |
| R-05 6.78 GB 是磁盘制品和哈希事实，不是 16GB 显存通过证据 | 任务 23/24 在 Windows 11 NVIDIA 16GB 真机记录实际峰值与稳定性 |
| R-06 模型包、运行时 notice/SBOM、自包含 Windows 包均未形成 | PoC 通过不解除 `LIC-01～06` 或发布门；最终选型需独立证据 |
| R-07 O-H01 的权重许可/revision、自主触发、20 秒 16GB 与 Windows 包未知 | 保持 `HOLD`，不得以厂商 15 秒数据或 Linux 命令替代 |

验收覆盖：模型/运行时组合 4/4 给出证据与结论（`POC/HOLD/REJECT=1/1/2`）；八项筛选门 8/8；任务交付物候选矩阵、淘汰理由、PoC 方案、风险假设 4/4；O10 组合能力面持续音画、自主触发、TTS 关闭、三批文字、单实例/会话/流、停止清理、16GB/Windows 7/7；O 相关 P1 校准项 CAL-002/005～010/026/027 共 9/9 有复用记录入口。以上均为静态筛选和执行计划，不是模型、性能、Windows、离线包或稳定性实测通过。
