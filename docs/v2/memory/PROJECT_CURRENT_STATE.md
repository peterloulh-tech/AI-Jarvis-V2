# AI Jarvis V2 当前状态

> 快照日期：2026-08-12。任务状态以 Dashi 项目 `ai-jarvis-v2` 的当前回读为准。

## 当前阶段与进度

项目已完成 **03 V1/开源资产审计** 阶段并进入 **04 O/V 模型与运行时选型** 阶段。AIJARVISV2-1～15 已完成需求/NFR 与验收规划；AIJARVISV2-15 已冻结验收基线。AIJARVISV2-1～15 当前均为 `done`。

AIJARVISV2-16 已固化原作者提交 `dd8fbf9` 的 3,276 文件只读快照、模块/资产/vendor 边界及整体与关键文件哈希并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-16.md)。

AIJARVISV2-17 已完成 21 个源码边界的 `D/M/R/W` 复用分级、依赖/许可门、提取前置条件和重写缺口，当前为 `done`，见[任务卡](tasks/AIJARVISV2-17.md)。

AIJARVISV2-18 已完成 V1 UI、资源、配置、脚本和测试资产复用/禁用矩阵并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-18.md)。

AIJARVISV2-19 已分离审计 V1 代码、vendor、MiniCPM 权重和桌面依赖的商业/离线分发条件并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-19.md)。

AIJARVISV2-20 已定义五类依赖准入、来源锁定、CycloneDX SBOM、vendor/patch、许可与漏洞门及替换策略并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-20.md)。

AIJARVISV2-21 已合并源码、UI/资源、许可与依赖审计，冻结 3 个直接复用候选符号、修改/参考/重写清单、黑名单、许可门及 12 类 V2 缺口并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-21.md)。

AIJARVISV2-22 已筛选 4 个 O 模型/运行时组合，唯一准入任务 23 的 PoC 组合为固定 MiniCPM-o 4.5 GGUF 与固定 `llama.cpp-omni` TTS 关闭双工路径；Qwen2.5-Omni 保持候补、不进 PoC，当前为 `done`，见[任务卡](tasks/AIJARVISV2-22.md)。

AIJARVISV2-23 已冻结为 `Legacy Diagnostic PoC / 2026-08-09 Real-machine Baseline` 并完成：RTX 5070 Ti 16GB Windows/NVIDIA 完整运行确认 73/73 result `ok:true`、69 LISTEN/4 SPEAK，连续 4 个 SPEAK fragment 拼接为未闭合 multi-batch JSON 前缀；同时保留 Locked 官方基线、四方 Delta、33×1 秒输入与零 GPU fixture/hash 验证。新任务链为 AIJARVISV2-23 → AIJARVISV2-92 Reference Harness 离线重建 → AIJARVISV2-93 Windows/NVIDIA 动态验收 → AIJARVISV2-24；任务 24 保持 `backlog`，见[任务卡](tasks/AIJARVISV2-23.md)。

AIJARVISV2-25 已完成 V 候选 Official-First 静态筛选并经用户验收为 `done`。测试候选为两个独立 profile：`V-C01` Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj，以及 `V-C02` MiniCPM-V-4.6 Q4_K_M + F16 mmproj，均复用 `llama-server b10369@6e62ba5...`；任务 26 动态纠正 V-C01 精确 GGUF 为同一官方模型的 `1cd86af...`（`qwen3vl`），候选方向不变。最终产品模型仍未冻结，见[任务卡](tasks/AIJARVISV2-25.md)。

AIJARVISV2-26 已交付独立 V 多图测试包并经用户验收为 `done`。普通/高光 `required` schema 主动强制完整输出，只有平静 `allow_silence`；fixture 修正单图运动误标和高光主体遮挡。Mac/Metal 严格顺序实测 V-C01 JSON/schema、完整契约、emit、level 均 9/9，硬门 `PASS`；V-C02 required 6/6，但智能沉默 0/3，整体 6/9、硬门 `FAIL`。两候选各 9 次调用、修复调用 0，未同时驻留；验收复核将硬门收紧为结构、emit 与 level 必须同时正确，26/26 单测通过。Windows/NVIDIA、8/12GB、真实许可语料、双人金标和质量阈值保持 `UNCONFIRMED`，任务 27/28 未启动，见[任务卡](tasks/AIJARVISV2-26.md)。

AIJARVISV2-92 已完成独立 Reference Harness v2、两个分离 profile、manifest 驱动的 33×1 秒/11×3 秒固定输入、streaming aggregation 与 completion 分层、三批 validator、离线 fixture/unit/static/dry-run、薄 Locked C API shim，以及既有 Windows/CUDA 构建链的最小接入准备，当前为 `done`，见[任务卡](tasks/AIJARVISV2-92.md)。

AIJARVISV2-93 当前为 `in_progress`，活动架构锁定 `llama.cpp-omni master@09f5c3f1...` 的官方 `llama-omni-server /backend`，与 `MiniCPM-o-Demo main@d0a00209...` 当前 C++ backend 默认的 `master/origin/master` 关系一致；直接复用官方 SessionManager、协议事件、HTTP session close 与 `omni_prepare_for_reuse`。V2 仅保留 O-IN-07 WAV/JPEG payload 转换、1Hz 输入、三批契约、prompt 注入与证据薄层，见 [`tools/o-official-reference`](../../../tools/o-official-reference/)。正式需求首版禁用 TTS；LLM/audio/vision 三文件与当前官方 no-TTS 路径兼容，模型与哈希不变且继续外置。GitHub Actions run [`31500354700`](https://github.com/peterloulh-tech/AI-Jarvis-V2/actions/runs/31500354700) 已在提交 `d6a95b4` 成功完成官方 runtime、thin adapter、打包验证和 Artifact 上传，Task23 job 正确跳过；Artifact 为 `AIJARVISV2-93-o-official-reference-windows-x64-cuda`。旧 `tools/o-reference-harness-v2` 保持 `LEGACY / RETIRED-PENDING-NEW-ROUTE-VALIDATION`，不被活动 workflow 或新实现调用；Task24 保持 `backlog`。

四方审计与 Official-First Runtime Rule 已启用：按正式需求、当前官方、当前原作者、已验证项目资产的顺序判断，模型/runtime/session/streaming 优先直接使用成熟实现，AI Jarvis 只实现正式需求 Delta，不再为参考或测试建立独立 Runtime/Harness。

## 冻结基线

| 基线 | 状态 | SHA-256 |
|---|---|---|
| 功能需求 V1.0 | 正式冻结；唯一功能范围；Local O / Local V / Online | `270e0b1f225ecd0f20d34a480a14845bcebab19708b873178c196837c8fd3c90` |
| 非功能需求 V1.0 | 正式冻结；正式质量约束；Local 离线 / Online 条件联网 | `f65950be98e56217d5e0472316ca7531d46227b00cfe5560186de7147ab8b7b5` |
| 验收清单 V0.1 | 候选规划基线；不得扩展功能 | `2fa89eb557e0f638bd4a5430cf9d86e63b17773000bf657409bc6ef287ee5f66` |

完整登记见 [`baseline-manifest.md`](../requirements/baseline-manifest.md)。AIJARVISV2-3～7 的 25 个 NFR 工程附录已由 AIJARVISV2-8 登记为 `NFR-ENG-APPENDIX-V1.0`；它不是第二份正式 NFR。阶段门已获用户批准，收口提交为 `b433f9dbfac5c074086a8d84ce73693670a3bd89`。

当前真实运行基线为 AIJARVISV2-23 Windows 便携 Legacy Diagnostic PoC 包；其 Windows/MSVC/CUDA 构建链与 2026-08-09 真机证据保留供 Reference Harness 复用和解释，不作为正式 Product Adapter。

## 关键决定

弹幕速度分布和卸载默认行为已正式确定，见 [`DECISIONS.md`](DECISIONS.md)。这些决定约束后续 Overlay、Windows 真机校准、安装器和验收任务；不得由模型或实现任务擅自改写。

## 当前公共约定

- 追踪 ID 统一使用 `FR-*`、`NFR-*`、`AC-*`、`OOS-*`、`CAL-*`；候选 AC 只作测试入口，不是需求来源。
- 度量统一复用任务2的 `TERM-*`、`MET-*`、`MP-*`、P50/P95 nearest-rank 和采样口径；不得为同一指标另建第二套定义。
- 验收结论只允许 `通过`、`失败`、`阻塞`、`不适用`；证据通道为 `UI`、`LOG`、`RES`、`FS`、`NET`。P0 失败阻止阶段通过，P1 必须记录但未校准值不得写成承诺。
- O 模式固定 225/350/500 字预算与 12/16/20 秒硬超时；O 始终单模型、单持续会话、单文字生成流。V 共享一个服务和一份权重；变化分数只用于候选调度，不直接等于高光；V 超时和重启保护仍待实测/评审。
- 程序包、模型包、个人配置和运行诊断保持逻辑分离；只允许用户主动更新，失败不得破坏原可运行组合。
- 当前仅冻结协议与验收规划，尚未冻结具体业务架构、IPC 消息 schema、安装目录或更新实现技术。

## 开放风险与待实测项

- O-C01 仍是唯一 PoC 准入组合；Official-First `llama-omni-server` Windows/CUDA binary、thin adapter 和便携 Artifact 已构建并通过 workflow/package/static 门，但 GitHub hosted runner 无 NVIDIA 真机能力。官方 Runtime/Session、startup LISTEN、自主 LISTEN/SPEAK、延迟、显存、session reuse 与 process cleanup 仍为 `DYNAMIC_ONLY`，尚无 Windows/NVIDIA PASS；Qwen2.5-Omni 候补边界不变。
- 2026-08-09 已批准的 Online V1 需求已同步为当前正式基线（功能 `270e0b1f...c90`、非功能 `f65950be...7b5`）；Task93 已据此建立 Local O 能力矩阵。Task90/91 原有新 SHA 引用保持不变，未批量改写历史 Dashi 任务。
- V-C01 已在 Mac/Metal 通过任务 26 单次 1～3 图结构硬门，但合成图词项诊断仅 5/11，不能代替真实英雄联盟语料质量；V-C02 的 required 输出可被约束，但智能沉默仍失败。Windows/NVIDIA 8GB/12GB+、正式许可回放/双人金标、乱序/取消/复位、吞吐、显存和 GPU 数据仍无证据。
- O/V 共用语料、许可、脱敏、时间轴和金标格式已定义，但实际授权资产与双人标注尚待制作；事件、高光、相关性和质量阈值仍待选型后校准。
- 真机代表组合和记录入口已编排，但 Windows 11/NVIDIA 8/12/16GB 机器、1080P/2K/4K × 五档缩放、音频设备、Overlay 点击穿透、系统电源事件、断网及英雄联盟同机负载均待执行；英雄联盟与主机完全断网的兼容执行方式尚未确认。
- 4 小时是 P0 正式稳定性窗口；8 小时只是内部压力目标。加载、首弹幕、P50/P95、吞吐、资源峰值/斜率、恢复/停止耗时和 V 并发数据未形成最终门槛。
- V1 根代码 MIT 与三份固定 MiniCPM 权重 Apache-2.0 已确认；当前 vendor provider 因参考音频权利和随包 notices 不明而阻塞，桌面包还缺 npm/Python/CUDA 固定来源及完整许可清单，均不得视为可分发。
- 依赖治理和 SBOM 字段已定义，但尚无 V2 仓库、真实锁文件、构建产物或漏洞扫描批次；规划资产不得当作实际准入或发布通过。
- V1 runtime 会把原始画面/音频写入临时 BMP/WAV；V1 调度、生命周期和发送还不满足 O/V 代次、槽位、清理、高光流规则，且存在冻结范围禁止的语义相似去重，均不得原样迁移。
- [`nfr-stage-gate-review.md`](../requirements/nfr-stage-gate-review.md) 与 [`nfr-open-risks-and-pending-validation.md`](../requirements/nfr-open-risks-and-pending-validation.md) 末尾的任务状态是交付时历史快照；当前状态必须回读 Dashi，不能据此推断。

## 下一步注意事项

O 路线继续只推进 AIJARVISV2-93 的 RTX 5070 Ti 16GB 动态验收，动态 PASS 前不得删除 Legacy Harness、宣称 O-C01 正式可行或启动 AIJARVISV2-24。V 路线唯一下一步是另开线程执行 AIJARVISV2-27，且只让通过硬门的 V-C01 进入共享权重 1～3 路并发基准。项目不再设置 ChatGPT 第二审核流程；不得提前启动任务 28 或产品开发。
