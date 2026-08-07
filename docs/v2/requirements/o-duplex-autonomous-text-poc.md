# AI Jarvis V2 O 持续全双工与自主文字输出 PoC 记录

> Dashi：AIJARVISV2-23
>
> 记录日期：2026-08-07
>
> 候选：`O-C01`，MiniCPM-o 4.5 GGUF Q4_K_M + `llama.cpp-omni@b9d15b83ee353b2eaeee4d9318c98a35a1347486`
>
> 结论：`阻塞`；未形成模型能力通过或失败结论，AIJARVISV2-24 不得启动

本记录执行任务 22 定义的 P-01 前检，并把无法进入 P-02～04 的原因、空输出和风险出口保留下来。它不修改冻结需求，不把静态源码能力当作模型实测，也不使用 V1 provider、默认参考音频、TTS 或候补模型替代 O-C01。

## 1. 实验身份与前检结果

运行 `O10-P23-20260807-MAC-01` 基于应用提交 `20a44eeceb996714750f1af24d60148a84c968fd`。执行机为 macOS Darwin arm64、Apple M1 Pro 16 核 GPU、32 GiB 统一内存；不存在 Windows 11 x64、NVIDIA 16GB、NVIDIA 驱动、`nvidia-smi`、MSVC、CUDA 或 `nvcc`。该环境不满足 O10 强制真机条件，不能用 Metal 或统一内存结果替代。

| 前检项 | 实际证据 | 结论 |
|---|---|---|
| 固定运行时 | `VENDOR.json` revision 为 `b9d15b83ee353b2eaeee4d9318c98a35a1347486`；patch SHA-256 为 `cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e`；本地与上游 MIT 文本哈希均为 `94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d` | `通过` |
| 固定模型 | 三项要求的 GGUF 在仓库和本机默认 Hugging Face 缓存中均为 `0/3`；因此没有本次运行可回放的逐文件完整哈希 | `阻塞` |
| 模型包许可 | 固定模型卡声明和预期哈希已有任务 22 静态证据，但本机没有与三项制品共同保存的 Apache-2.0、模型卡、revision、归属及 NOTICE 记录 | `阻塞` |
| TTS/参考音频隔离 | 固定源码支持 `use_tts=false`/`--no-tts`，但现有 `test-duplex` 默认引用 `default_ref_audio.wav`；未产生构建清单或文件访问日志，不能把“未执行”记作 TTS 调用 0 | `阻塞` |
| O-IN-07 输入 | 仓库没有经授权、脱敏并带时间轴/金标的 O-IN-07 资产；vendor 测试音画与默认参考音频没有本任务所需权利记录，未使用 | `阻塞` |
| 强制环境 | 当前为 Apple M1 Pro/macOS arm64，不是 Windows 11 x64/NVIDIA 16GB 独占环境 | `阻塞` |

前检在模型下载、构建和推理前终止，避免产生约 6.78 GB 未配套许可材料的模型副本，也避免把不合格平台数据混入任务 24 的 Windows/NVIDIA 基线。

## 2. 接口调用与输出记录

固定源码静态确认 `omni_duplex_session_begin`、`omni_duplex_push_frame`、`omni_duplex_wait_next_frame`、`omni_duplex_session_end` 共 `4/4` 个接口，以及 `user_seq/frame_id/is_speak/text/ms_prefill_submit/ms_decode/ms_total` 结果字段。现有 producer 与 consumer 分线程，具备在 decode 等待期间继续 push 的代码入口；这只是接口可测试性，不是生成期间输入未中断的运行证明。

本次在 P-01 停止，四个接口的动态调用均为 `0`。原始输出样本如下；它明确表示无模型输出，不能作为智能沉默、三批结构或 TTS 关闭的通过样本：

```json
{"run_id":"O10-P23-20260807-MAC-01","status":"blocked","model_calls":0,"session_begin_calls":0,"push_frame_calls":0,"wait_next_frame_calls":0,"session_end_calls":0,"tts_calls":null,"extra_model_calls":0,"input_chunks":0,"raw_response":null,"batches":null}
```

上游 `test-duplex` 使用固定 system prompt，且控制台只保留最多 60 字的文本预览；V1 `native/src/omni_runtime.cpp` 的双工提示要求单句文本并会查找默认参考音频，且已被任务 22 明确禁止作为 O-C01 替代。任务 23 未修改这些受保护实现，而是在 [`tools/aijarvisv2-23/`](../../../tools/aijarvisv2-23/) 增加独立现场入口，提供三批 JSON 提示、完整原文、逐批校验与资源/故障采集。

## 3. 停止、恢复与性能记录

由于模型进程未创建，`session_end` drain、取消差距、硬超时终止、会话重建、旧代次、显存释放和孤儿进程均为`阻塞`，不是`通过`。BENCH-001～005 的 N、P50/P95、首输出、完整耗时、吞吐、显存/GPU/内存/句柄也没有样本；没有向既有 CSV 写入伪造的零值或不适用值。

已准备 Windows 现场包；当前 macOS 环境未执行其构建或模型调用。合格环境复跑时按以下入口执行，任一失败即保留原始日志并停止：

1. 在 Windows 11 x64/NVIDIA 16GB 独占机准备固定三项 GGUF，逐文件匹配任务 22 的大小与 SHA-256，并把许可材料和 O-IN-07 授权记录与运行 ID 绑定。
2. 单命令从固定 vendor 副本应用固定 patch 并构建独立 CUDA 子进程；入口生成完整 JSONL/既有 CSV，硬关闭 TTS、空参考音频，并在加载前排除 TTS/token2wav/默认参考音频制品。
3. 以同一模型实例、持续会话和文字生成流调用四个 duplex 接口；生产线程按序提交生成前/中/后 chunk，消费线程记录完整结果，不使用业务触发壳或补调用。
4. 复用 `performance-sample-record.csv`、`resource-trend-record.csv` 和既有故障记录完成 BENCH-001～005、取消/硬终止/重建；结束后核对 PID、孤儿和显存基线。

## 4. 候选比较与风险出口

| 候选 | 本次处置 | 依据 |
|---|---|---|
| O-C01 | 保持唯一可复跑候选，但任务 23 当前为`阻塞` | 固定身份、四接口和专用三批记录入口静态成立；模型/许可包、O-IN-07、合格硬件及动态证据缺失 |
| O-H01 | 保持 `HOLD`，不得替补 | 权重许可/revision、自主触发、20 秒 16GB 与 Windows 自包含证据仍缺 |
| O-X01 | 保持 `REJECT` | 官方 15 秒最低显存已越过 16GB 边界 |
| O-X02 | 保持 `REJECT` | 参考音频、TTS、许可、临时媒体与生命周期继续违反任务 21/22 门槛 |

选型风险 `O-RISK-23-01` 已触发：当前仓库与执行环境不能形成“持续音画 + 生成中继续输入 + 原生自主触发 + 单次三批文字 + TTS 0”的动态闭环。评审只能选择在同一任务补齐合格 Windows/NVIDIA 执行资源和一次性记录入口后复跑，或退回任务 22 重新评审候选；在风险关闭前不得宣称 O-C01 可行、不得冻结最终模型，也不得启动 AIJARVISV2-24。

## 5. 验收覆盖

| 任务 23 要求 | 覆盖 |
|---|---:|
| 唯一候选身份与固定来源 | 1/1 静态通过 |
| P-01 前检项 | 6/6 有结论；1 通过、5 阻塞 |
| 双工接口可测试性 | 4/4 静态确认；0/4 动态调用 |
| 持续输入、自主触发、三批文字、TTS 关闭、停止恢复 | 5/5 有明确阻塞原因；0/5 动态通过 |
| 接口调用记录、输出样本、失败模式、候选对比 | 4/4 已交付；输出样本明确为未执行空样本 |
| Windows 现场执行入口 | 1/1 已准备；当前环境 0 次构建、0 次模型调用 |
| 候选 | 4/4 保持 POC/HOLD/REJECT 边界并触发 1 个选型风险 |

本次没有运行模型、性能、长稳或无关测试；没有把缺失值计算为零，也没有把 macOS 静态检查外推为 Windows/NVIDIA 结论。
