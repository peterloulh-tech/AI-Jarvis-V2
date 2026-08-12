# AI Jarvis V2 V 模型与运行时候选筛选

> Dashi：AIJARVISV2-25；静态审计日期：2026-08-12
>
> 正式基线：功能 `270e0b1f...c90`、非功能 `f65950be...7b5`、验收 `2fa89eb5...f66`；完整值见 [baseline-manifest](baseline-manifest.md)。Dashi 创建时记录的旧哈希已被当前正式 manifest 替代。
>
> revision 锁：[v-model-runtime-candidate-lock.json](v-model-runtime-candidate-lock.json)

本文件只筛选进入任务 26/27 的 Local V 候选，不冻结最终产品模型、分辨率、显存、延迟、吞吐或发布资格。经 2026-08-12 用户复核，测试候选锁定为 Qwen3-VL-4B-Instruct 与 MiniCPM-V-4.6 两个固定量化 profile；二者必须在同一 V 测试包、同一输入与协议下分别实测，再按证据决定最终产品模型，不以静态筛选预选胜者。当前为 macOS，无 Windows/NVIDIA 真机；文中 `DIRECT/MODIFY/V2-ONLY` 只表示静态能力归属，所有动态项目均为 `UNCONFIRMED`，不得写作真机 PASS。

## 1. 正式门与四方审计结论

按 [V01～V10](v-mode-acceptance-and-benchmark-plan.md) 和故障矩阵，准入组合必须同时满足：Windows 11 x64/NVIDIA 可构建；预置后核心完全离线；同一服务、同一已加载的一份权重提供 1～3 个槽位；每组 1～3 图只调用模型一次；同次推理产生一个主要事件、`ordinary/highlight`、一个风格批次、智能沉默及可选不超过 30 个中文字的摘要；可约束结构化输出；支持独立完成、取消和全局复位；来源与许可可追溯。多份模型进程、OCR/分类/摘要补模型、第二次整理调用及在线核心服务直接淘汰。

| 顺序 | 证据与判断 | 标签 |
|---|---|---|
| 1 正式冻结需求 | V01/V05～V10、FAULT-005～007/012～014 是行为与验收边界；不从现有实现反推需求 | `DIRECT` |
| 2 当前官方 | `llama.cpp server b10369` 已有单模型 inference mode、多 slot、continuous batching、multimodal、JSON Schema、Windows CUDA release 与取消任务原语；无需另造 runtime/server/scheduler | `DIRECT` |
| 3 当前原作者 | V1 的 O runtime/session/调度不具备 V 的共享权重多 slot、乱序代次与一次多图契约；原样迁移会与任务 21 黑名单冲突 | `DUPLICATE` / `CONFLICT` |
| 4 已验证项目资产 | 复用任务 3/4/11 的基准与故障模板、任务 14 的 8/12GB 分组、任务 19～21 的许可/SBOM 门；Task93 的 O 路线、模型和 session 不参与 V | `DIRECT` / `REFERENCE` |
| 5 V2 最小增量 | 只补提交时风格快照、`task_id/captured_at/run_generation`、等比留边预处理、结果校验及一进程全局复位；不承载第二 runtime | `V2-ONLY` |

## 2. 固定官方证据

| ID | 第一方固定证据 | 本任务结论 |
|---|---|---|
| E-01 | [`llama.cpp b10369@6e62ba5`](https://github.com/ggml-org/llama.cpp/tree/6e62ba538478202094edc6c100c782719e310aa3) 的 [`server README`](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/tools/server/README.md)、[`README-dev`](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/tools/server/README-dev.md) 与 [MIT LICENSE](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/LICENSE) | inference mode 的一个 `server_context` 持有一个主模型和全部 `server_slot`；`--parallel`/continuous batching 是共享加载，不是 router 多实例 |
| E-02 | 同 revision 的 [`server-common.cpp`](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/tools/server/server-common.cpp)、[`server-queue.cpp`](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/tools/server/server-queue.cpp)、[`test_vision_api.py`](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/tools/server/tests/unit/test_vision_api.py) | 多媒体数组与 JSON Schema 有源码/单测；reader 停止会投递高优先级 CANCEL；官方视觉单测仍有 multiple-images TODO，因此 1～3 图动态闭环留给任务 26 |
| E-03 | [b10369 release](https://github.com/ggml-org/llama.cpp/releases/tag/b10369) 的 Windows CUDA 12.4 x64 binary/cudart 资产 | 有官方 Windows/CUDA 制品与 digest；目标 GPU、驱动、便携依赖及完全断网仍未验证 |
| E-04 | [`Qwen3-VL@9658872`](https://github.com/QwenLM/Qwen3-VL/tree/96588727e44c78b25ba03ea03b8e12f7e64fd0da)、[4B base@ebb281e](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct/tree/ebb281ec70b05090aa6165b016eac8ec08e71b17)、[GGUF@1cd86af](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF/tree/1cd86afb9a95c410a6038ab3b40d8b578c892266) | Apache-2.0；官方示例原生多图；按 `min_pixels/max_pixels` 等比缩放，显式尺寸会舍入 32 的倍数；任务 26 已验证该官方 GGUF 的 `qwen3vl` metadata 可由锁定 b10369 加载 |
| E-05 | [`MiniCPM-V@0dbb566`](https://github.com/OpenBMB/MiniCPM-V/tree/0dbb566de090067266abb76e702fb289f09934c5)、[4.6 base@8169864](https://huggingface.co/openbmb/MiniCPM-V-4.6/tree/8169864629825dc1d755a5aa1cd8b5935dcbc83f)、[GGUF@78e02f0](https://huggingface.co/openbmb/MiniCPM-V-4.6-gguf/tree/78e02f066e9819a60573b78a4275df8a0c27f698)、[`llama.cpp` 4.6 guide](https://github.com/ggml-org/llama.cpp/blob/6e62ba538478202094edc6c100c782719e310aa3/docs/multimodal/minicpmv4.6.md) | Apache-2.0；这里是 **4.6（不是 4.5/8.2B）**：官方 4.6 base 文件树为 2.62GB，README 明示 Qwen3.5-0.8B 文本模型；官方 4.6 GGUF 文件树为 Q4_K_M 529MB + mmproj 1.11GB。原生单/多图且 b10369 已支持，但一次复杂中文判断质量风险高 |
| E-06 | [vLLM GPU installation](https://docs.vllm.ai/en/v0.15.0/getting_started/installation/gpu/)；[Gemma 3 model card](https://huggingface.co/google/gemma-3-4b-it) | vLLM 官方仍不原生支持 Windows；Gemma 权重需接受专有条款/门控，离线再分发门高于 Apache 候选 |

本地静态复核了 b10369 源码归档 SHA-256 `ef81cd...23d0e`，并以当前 master `89e0aa6...` 交叉检查相同 server 边界；实际采用仍锁定 release，不跟随 `master/latest`。

## 3. 候选矩阵

| ID | 模型 + runtime | 1～3 图/输入策略 | 共享并发、取消、复位 | 资源与许可风险 | 结论 |
|---|---|---|---|---|---|
| V-C01 | Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj + `llama-server b10369` | 模型卡原生多图；官方无单一推荐分辨率，按显存设 `min/max_pixels`。任务 26 先用 **896×512** 画布（均为 32 倍数）等比 fit + padding，一组 1/2/3 图一次请求；该尺寸只是 PoC 起点 | 一个 inference-mode 服务、同一权重、`--parallel 1/2/3`；独立响应允许乱序。客户端断开/reader stop 可取消；进程重启 + generation bump 才是产品全局复位 | 固定模型文件约 2.95GB 不是显存；权重 Apache-2.0、runtime MIT。8GB 为**高风险待测目标**，12GB+ 仅代表更有余量，不是 PASS | `POC`：质量/综合能力候选；必须与 V-C02 同场实测，尚非最终模型 |
| V-C02 | MiniCPM-V-4.6 Q4_K_M + F16 mmproj + 同一 server | 官方原生多图；记录 `max_slice_nums/use_image_id` 等模型特有参数。任务 26 使用与 V-C01 相同的原始 fixture、1/2/3 图分组和 896×512 等比留边起点；不能用不同输入掩盖差异 | 使用同一官方 slots/cancel/reset 边界；每轮只加载 V-C01 或 V-C02 之一 | 固定文件约 1.64GB，静态资源风险较低；官方“4GB GPU”是厂商口径，不是 Windows PASS。0.8B 文本头对事件/高光/风格/摘要一体输出风险高；两项 LFS SHA 已由任务 26 首次准入回放 | `POC`：低资源/效率候选；必须与 V-C01 同场实测，尚非最终模型 |
| V-X01 | Gemma 3 4B + llama.cpp | 原生视觉，官方固定 896×896 | runtime 能力同上 | 模型权重受 Gemma 条款、门控和 Prohibited Use Policy 约束；离线再分发审计成本高且无能力优势证据 | `REJECT`：存在 Apache 候选时不引入额外许可门 |
| V-X02 | Qwen/MiniCPM + vLLM、SGLang 或 Transformers 服务 | 模型可多图 | vLLM 官方不原生支持 Windows；未发现比 llama server 更直接的 Windows 单权重 1～3 slot 路线 | Python/CUDA 依赖与离线包更大 | `REJECT`：违反 Official-First 最短 Windows 路线 |
| V-X03 | V1/Task93 O runtime、多个模型进程或联网 API | 不满足 V 一次多图边界或引入在线核心 | 无共享单权重槽位，或用多副本伪装并发；Task93 O session 不得修改 | 与任务 21 黑名单、核心离线或用户边界冲突 | `REJECT`：`CONFLICT/DUPLICATE` |

### 3.1 两候选共同的一次推理契约

任务 26 对 V-C01、V-C02 使用同一请求契约：每组只用一个请求生成受 JSON Schema 约束的对象，包括 `emit`（智能沉默）、`event`（至多一个主要事件）、`level`（`ordinary/highlight`）、`comments`（当前提交时固定风格的一个批次）及可选 `summary`（`maxLength: 30`）。`emit=false` 时业务字段为空；变化分数不进入 `level` 判断。schema 负责语法/枚举/长度上界，V2 薄校验器负责中文字符计数、时效、代次和字段一致性；失败只丢弃并留原始哈希，不得 OCR、分类、摘要或格式修复补调用。

`style_id` 在提交时固定；每个请求携带 `task_id/captured_at/run_generation` 和最多一条最近有效客观摘要。各 slot 独立结束，消费者按 `task_id` 接收乱序结果；只有更晚 `captured_at` 的当前代次有效摘要可更新状态。全局复位终止唯一 server、清空所有 slot/缓冲并提升 generation，旧结果一律失效；不启动备用模型副本。

### 3.2 离线与再分发边界

核心运行只允许本地 `-m`、`--mmproj`、本地图片或 base64；禁用 `-hf`、URL 媒体、下载器、遥测和在线 API。Apache-2.0 模型与 MIT runtime 允许在履行许可证/版权/NOTICE 条件后再分发，但这不是安装包许可 PASS：任务 26 对首次取得或进入固定保存位置的实际文件校验一次 SHA 并保存记录；文件名、来源、版本和字节数未变时，后续普通启动不得重复计算。最终组包再回放一次，并登记所有嵌套依赖、CUDA redistributable/EULA、驱动前置、源码修改与 SBOM。未完成前只能用于验证，不能宣称可发布。

## 4. 任务 26/27 最小验证方案

### 任务 26：V 原生多图 PoC

1. 测试包同时包含 lock 中 V-C01、V-C02 两个独立 profile；首次取得或移入固定保存位置时补齐并校验实际文件 SHA，普通重复运行只核对路径、文件名和字节数，最终组包再回放一次。使用同一 b10369 官方 Windows CUDA 12.4 资产；每轮断网只启动一个 `llama-server --parallel 1`、只加载一个候选，不同时驻留、不混合结果、不写产品 adapter。
2. 复用 V-IN-04/05：同一许可事件分别生成 1/2/3 图组，统一以 896×512 等比留边画布为共同起点，每组一个 request/call id；保留原始尺寸、缩放、padding 和模型特有视觉参数记录。若某模型需不同输入参数才能正常工作，追加成可追溯子组，不替换共同对照组。
3. 两候选都执行相同的普通、高光、智能沉默、复杂/含糊场景和风格批次；保存 schema、prompt、原始响应哈希、解析结果、模型调用数、网络/进程/权重实例数。比较事件正确性、高光/沉默判断、弹幕质量与多样性、摘要事实性、结构有效率及失败类型。硬门仍是原生多图可解码、一次调用完成完整结构、无额外模型/调用/网络。
4. 在可取得的 8GB 与 12GB+ Windows/NVIDIA 分组，对两个候选分别记录加载、成功/失败/超时、峰值显存和 GPU；没有对应硬件就记 `BLOCKED/UNCONFIRMED`，不得用厂商数字代替。任一候选硬失败即记录为淘汰证据，不阻止另一个候选完成测试。

### 任务 27：共享权重并发基准

1. 对任务 26 通过硬门的每个候选，分别固定其量化、同一 server 与 896×512 共同输入策略并重启为 `--parallel 1/2/3`；每组确认始终一个 PID、一个 model load/权重标识，禁止 router mode、多进程及两个候选同时驻留。若某候选已在任务 26 硬失败，任务 27 不再为其制造无意义并发数据。
2. 复用 V-IN-01/06/07/08：长短任务交错以强制乱序；分别注入客户端取消、服务退出和全局复位，核对 slot 释放、旧 generation 丢弃、摘要与风格不回滚。
3. 每个 `vram_class × slots × image_count` 独立 sample group，记录成功/失败/超时/取消/过期分母、min/max/P50/P95、吞吐、显存/GPU 时序、加载次数和实例数。8GB/12GB+ 不设提前承诺，硬超时与连续重启保护只产出评审数据。

## 5. 结论与未验证项

锁定 `V-C01` 与 `V-C02` 共同进入 V 测试包：Qwen3-VL-4B 是质量/综合能力候选，MiniCPM-V-4.6 是低资源/效率候选；静态证据不指定最终产品模型。任务 26 负责同场功能与质量 PoC，任务 27 对通过硬门的候选分别完成共享权重 1～3 路动态基准，任务 29 再依据许可、质量、显存、延迟、吞吐和故障证据冻结唯一产品选型。已确认的是 revision、源码结构、发布资产、模型卡接口和许可证声明；**未验证**的是 Windows/NVIDIA 实际启动、1～3 图正确性、896×512 质量、稳定结构输出、智能沉默/高光准确率、取消/乱序/复位动态行为、8/12GB 显存、延迟、吞吐、长稳、完全离线包和最终再分发材料。任务 25 结论为双候选静态筛选 `READY FOR POC`，不是任一模型或产品 `PASS`。

### 任务 26 动态回写（2026-08-12）

任务 25 的候选方向不变，但精确 Qwen GGUF 锁改为同一官方模型的 `1cd86af...`：后续 `594171a...` 只改了 architecture metadata，却与锁定 b10369 冲突。Mac 顺序 PoC 中 V-C01 完整契约 9/9，通过任务 26 功能硬门；V-C02 仅 required 6/6，智能沉默 0/3，整体硬门失败。因此当前候选决策为 **V-C01 进入评审，V-C02 停在失败证据**；这仍不是 Windows/NVIDIA、真实语料质量或最终产品选型 PASS。
