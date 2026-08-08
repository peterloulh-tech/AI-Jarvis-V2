# AI Jarvis V2 当前状态

> 快照日期：2026-08-09。任务状态以 Dashi 项目 `ai-jarvis-v2` 的当前回读为准。

## 当前阶段与进度

项目已完成 **03 V1/开源资产审计** 阶段并进入 **04 O/V 模型与运行时选型** 阶段。AIJARVISV2-1～15 已完成需求/NFR 与验收规划；AIJARVISV2-15 已冻结验收基线。AIJARVISV2-1～15 当前均为 `done`。

AIJARVISV2-16 已固化原作者提交 `dd8fbf9` 的 3,276 文件只读快照、模块/资产/vendor 边界及整体与关键文件哈希并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-16.md)。

AIJARVISV2-17 已完成 21 个源码边界的 `D/M/R/W` 复用分级、依赖/许可门、提取前置条件和重写缺口，当前为 `done`，见[任务卡](tasks/AIJARVISV2-17.md)。

AIJARVISV2-18 已完成 V1 UI、资源、配置、脚本和测试资产复用/禁用矩阵并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-18.md)。

AIJARVISV2-19 已分离审计 V1 代码、vendor、MiniCPM 权重和桌面依赖的商业/离线分发条件并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-19.md)。

AIJARVISV2-20 已定义五类依赖准入、来源锁定、CycloneDX SBOM、vendor/patch、许可与漏洞门及替换策略并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-20.md)。

AIJARVISV2-21 已合并源码、UI/资源、许可与依赖审计，冻结 3 个直接复用候选符号、修改/参考/重写清单、黑名单、许可门及 12 类 V2 缺口并完成评审，当前为 `done`，见[任务卡](tasks/AIJARVISV2-21.md)。

AIJARVISV2-22 已筛选 4 个 O 模型/运行时组合，唯一准入任务 23 的 PoC 组合为固定 MiniCPM-o 4.5 GGUF 与固定 `llama.cpp-omni` TTS 关闭双工路径；Qwen2.5-Omni 保持候补、不进 PoC，当前为 `done`，见[任务卡](tasks/AIJARVISV2-22.md)。

AIJARVISV2-23 已完成 O-C01 PoC 前检并触发 `O-RISK-23-01`；现已补齐 GitHub Actions 预编译便携 Artifact 工作流、单入口 Windows 现场包、固定资产/输入校验及 P-02～04 JSONL/CSV 采集。最新云端工作流已通过 Windows/MSVC/CUDA 编译链接，portable 打包对 `CUDA_PATH` 内 EULA 的错误假设已改为构建前获取并锁定 NVIDIA 官方 `cuda_cudart` 与 `libcublas` redistributable 许可；完整 Artifact 尚待该修复后的工作流生成。三项模型许可包、O-IN-07 授权输入和 Windows 11/NVIDIA 16GB 正式验收真机仍缺，未产生动态证据，当前为 `in_review`，见[任务卡](tasks/AIJARVISV2-23.md)。

## 冻结基线

| 基线 | 状态 | SHA-256 |
|---|---|---|
| 功能需求 V1.0 | 正式冻结；唯一功能范围；Local O / Local V / Online | `270e0b1f225ecd0f20d34a480a14845bcebab19708b873178c196837c8fd3c90` |
| 非功能需求 V1.0 | 正式冻结；正式质量约束 | `f65950be98e56217d5e0472316ca7531d46227b00cfe5560186de7147ab8b7b5` |
| 验收清单 V0.1 | 候选规划基线；不得扩展功能 | `2fa89eb557e0f638bd4a5430cf9d86e63b17773000bf657409bc6ef287ee5f66` |

完整登记见 [`baseline-manifest.md`](../requirements/baseline-manifest.md)。AIJARVISV2-3～7 的 25 个 NFR 工程附录已由 AIJARVISV2-8 登记为 `NFR-ENG-APPENDIX-V1.0`；它不是第二份正式 NFR。阶段门已获用户批准，收口提交为 `b433f9dbfac5c074086a8d84ce73693670a3bd89`。

当前业务交付基线为 AIJARVISV2-23 Windows 便携 PoC 包；最新云端记录已证明 Windows/MSVC/CUDA 编译链接通过，本次继续修正其 portable 许可收集链。项目记忆只记录事实，不改变业务交付。

## 关键决定

弹幕速度分布和卸载默认行为已正式确定，见 [`DECISIONS.md`](DECISIONS.md)。这些决定约束后续 Overlay、Windows 真机校准、安装器和验收任务；不得由模型或实现任务擅自改写。

## 当前公共约定

- 追踪 ID 统一使用 `FR-*`、`NFR-*`、`AC-*`、`OOS-*`、`CAL-*`；候选 AC 只作测试入口，不是需求来源。
- 度量统一复用任务2的 `TERM-*`、`MET-*`、`MP-*`、P50/P95 nearest-rank 和采样口径；不得为同一指标另建第二套定义。
- 验收结论只允许 `通过`、`失败`、`阻塞`、`不适用`；证据通道为 `UI`、`LOG`、`RES`、`FS`、`NET`。P0 失败阻止阶段通过，P1 必须记录但未校准值不得写成承诺。
- O 模式固定 225/350/500 字预算与 12/16/20 秒硬超时；O 始终单模型、单持续会话、单文字生成流。V 共享一个服务和一份权重；变化分数只用于候选调度，不直接等于高光；V 超时和重启保护仍待实测/评审。
- 程序包、模型包、个人配置和运行诊断保持逻辑分离；只允许用户主动更新，失败不得破坏原可运行组合。
- V1 模型模式为 Local O / Local V / Online；Local 完全离线且原始音画不上传，Online 只在用户主动选择后使用用户 API Key 上传必需音画，停止或切回 Local 后停止上传。
- 当前仅冻结协议与验收规划，尚未冻结具体业务架构、IPC 消息 schema、安装目录或更新实现技术。

## 开放风险与待实测项

- O-C01 仍是唯一 PoC 准入组合；任务 23 已准备三批完整记录入口，但模型/许可包、O-IN-07 和 Windows 11/NVIDIA 16GB 环境仍缺，O10 的持续音画、自主触发、结构化三批输出与 TTS 关闭没有动态通过证据。Qwen2.5-Omni 候补还缺权重 revision/许可材料、自主触发、20 秒 16GB 与 Windows 自包含包证据。
- V 候选模型和原生多图能力、许可回放/变化标注/事件高光金标、8GB/12GB+ 真机，以及 1～3 路延迟、吞吐、显存和 GPU 数据尚无实测证据。
- O/V 共用语料、许可、脱敏、时间轴和金标格式已定义，但实际授权资产与双人标注尚待制作；事件、高光、相关性和质量阈值仍待选型后校准。
- 真机代表组合和记录入口已编排，但 Windows 11/NVIDIA 8/12/16GB 机器、1080P/2K/4K × 五档缩放、音频设备、Overlay 点击穿透、系统电源事件、断网及英雄联盟同机负载均待执行；英雄联盟与主机完全断网的兼容执行方式尚未确认。
- 4 小时是 P0 正式稳定性窗口；8 小时只是内部压力目标。加载、首弹幕、P50/P95、吞吐、资源峰值/斜率、恢复/停止耗时和 V 并发数据未形成最终门槛。
- V1 根代码 MIT 与三份固定 MiniCPM 权重 Apache-2.0 已确认；当前 vendor provider 因参考音频权利和随包 notices 不明而阻塞，桌面包还缺 npm/Python/CUDA 固定来源及完整许可清单，均不得视为可分发。
- 依赖治理和 SBOM 字段已定义，但尚无 V2 仓库、真实锁文件、构建产物或漏洞扫描批次；规划资产不得当作实际准入或发布通过。
- V1 runtime 会把原始画面/音频写入临时 BMP/WAV；V1 调度、生命周期和发送还不满足 O/V 代次、槽位、清理、高光流规则，且存在冻结范围禁止的语义相似去重，均不得原样迁移。
- [`nfr-stage-gate-review.md`](../requirements/nfr-stage-gate-review.md) 与 [`nfr-open-risks-and-pending-validation.md`](../requirements/nfr-open-risks-and-pending-validation.md) 末尾的任务状态是交付时历史快照；当前状态必须回读 Dashi，不能据此推断。

## 下一步注意事项

AIJARVISV2-23 下一步只允许在同一任务从可写 GitHub Actions 仓库生成固定便携 Artifact，现场另行放置固定模型许可材料和 O-IN-07，并在合格 Windows/NVIDIA 真机执行单入口；或退回任务 22 重审候选。12GB～不足 16GB 的结果只作补充证据，不能替代正式 16GB 最低环境。`O-RISK-23-01` 关闭前不得宣称 O-C01 可行，不得启动 AIJARVISV2-24。
