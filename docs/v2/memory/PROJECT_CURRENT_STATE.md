# AI Jarvis V2 当前状态

> 更新日期：2026-08-27。任务状态以 Dashi 项目 `ai-jarvis-v2` 当前回读为准；本文件只保留当前快照，不替代 Dashi、Git 或实际验证证据。

## 当前阶段与活动任务

- 当前阶段：**04 O/V 模型与运行时选型**。
- `AIJARVISV2-93`：`in_progress`，O Reference Harness v2 Windows/NVIDIA 动态验收。
- `AIJARVISV2-27`：`blocked`，V 共享权重 1～3 路基准工具已实现并通过本地回归；等待真实 Windows/NVIDIA 8GB 与 12GB+ 双候选完整矩阵。
- `AIJARVISV2-24`：`backlog`，O 16GB 模型独占性能基线；等待 Task93。
- AIJARVISV2-1～26、92、94 的已完成摘要和证据入口见 [`memory/README.md`](README.md)、Dashi 与对应任务卡。

## 活动技术路线

- **O**：活动路线为官方 `llama.cpp-omni` `llama-omni-server /backend` 与薄适配层；正式首版禁用 TTS。Task93 的 Windows/NVIDIA Runtime、Session、LISTEN/SPEAK、延迟、显存、复用和清理仍为 `DYNAMIC_ONLY`，未形成产品 PASS。
- **V**：V-C01 Qwen3-VL 与 V-C02 MiniCPM-V 保持独立 profile 和独立运行路线。Mac/Metal 共同 v3 功能硬门已通过；单 `llama-server`/单权重的 1/2/3 slots 基准与取消/复位证据工具已就绪。Windows/NVIDIA 8GB/12GB+ 动态矩阵、正式许可语料、吞吐和质量阈值仍未确认。
- `tools/o-reference-harness-v2` 保持 `LEGACY / RETIRED-PENDING-NEW-ROUTE-VALIDATION`，不进入活动实现。

## 冻结基线

| 基线 | 状态 | SHA-256 |
|---|---|---|
| 功能需求 V1.0 | 正式冻结；唯一功能范围；Local O / Local V / Online | `270e0b1f225ecd0f20d34a480a14845bcebab19708b873178c196837c8fd3c90` |
| 非功能需求 V1.0 | 正式冻结；正式质量约束；Local 离线 / Online 条件联网 | `f65950be98e56217d5e0472316ca7531d46227b00cfe5560186de7147ab8b7b5` |
| 验收清单 V0.1 | 候选规划基线；不得扩展功能 | `2fa89eb557e0f638bd4a5430cf9d86e63b17773000bf657409bc6ef287ee5f66` |

完整登记见 [`baseline-manifest.md`](../requirements/baseline-manifest.md)。V1/原作者资产审计、官方 runtime 锁定和模型制品来源见 [`OFFICIAL_BASELINE_INDEX.md`](OFFICIAL_BASELINE_INDEX.md) 及 `docs/v2/requirements/` 对应证据；这些入口不构成第二套需求基线。

## 关键决定与公共约定

- 跨任务决定统一见 [`DECISIONS.md`](DECISIONS.md)，不得由普通实现任务擅自改写。
- 追踪 ID 使用 `FR-*`、`NFR-*`、`AC-*`、`OOS-*`、`CAL-*`；候选 AC 只作测试入口，不是需求来源。
- 度量复用 `TERM-*`、`MET-*`、`MP-*`、P50/P95 nearest-rank 和既有采样口径，不建立第二套指标。
- 验收结论只允许 `通过`、`失败`、`阻塞`、`不适用`；证据通道为 `UI`、`LOG`、`RES`、`FS`、`NET`。
- O 固定 225/350/500 字预算和 12/16/20 秒硬超时；O 为单模型、单持续会话、单文字流。V 共享一份权重和一个服务，最终并发边界仍待实测。
- 程序包、模型包、个人配置和运行诊断逻辑分离；当前只冻结协议与验收规划，未冻结完整产品架构、IPC schema、安装目录或更新实现。

## 开放风险

- O 的 Windows/NVIDIA 动态 Runtime/Session、自主 LISTEN/SPEAK、延迟、显存、session reuse 和 process cleanup 尚无 PASS。
- V 的 Windows/NVIDIA 8GB/12GB+ 双候选矩阵、真实 b10369 CUDA 日志/清理、正式许可回放、双人金标、吞吐和质量阈值尚无完整证据；Mac fake-server 回归不能替代动态证据。
- O/V 授权语料、脱敏、时间轴、金标和断网执行方式仍有缺口。
- 4 小时是正式稳定性窗口，8 小时是内部压力目标；性能、资源斜率、恢复/停止耗时和 V 并发门槛尚未最终校准。
- vendor provider、桌面依赖、CUDA/npm/Python 来源和完整发布许可材料仍未全部准入；规划资产不得当作发布通过。

## 唯一下一步

- O：继续执行 `AIJARVISV2-93` RTX 5070 Ti 16GB Windows/NVIDIA 动态验收；动态 PASS 前不得启动 Task24、删除 Legacy Harness 或宣称 O-C01 正式可行。
- V：在真实 Windows/NVIDIA 8GB 与 12GB+ 环境分别执行 Task27 的 V-C01/V-C02 1/2/3 slots × 1/2/3 图矩阵和故障组；证据完整前保持阻塞，不得启动 Task28 或产品开发。

## 新会话恢复

遵循根目录 `AGENTS.md` 的最小恢复路径；本文件只提供当前事实，不重复任务流程、历史摘要或完整需求。

## 维护

只有阶段、主任务、活动路线、阻塞状态或唯一下一步变化时更新本文件；普通 commit、临时失败、重复测试和聊天不写入长期状态。
