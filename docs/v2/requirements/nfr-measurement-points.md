# AI Jarvis V2 非功能测量点与日志字段清单

> 任务：AIJARVISV2-2
> 基线：非功能需求正式冻结版 V1.0
> 说明：下列是逻辑测量点和最小可观测字段，不决定最终 IPC、编程语言类型或存储格式。

## 1. 时钟与关联规则

- 每条测量记录同时包含单调时钟和 UTC 时间；耗时只使用同一机器的单调时钟差。
- 所有记录至少关联 `run_id`、`run_generation`、`mode` 和只读配置快照哈希。
- O/V、模型版本、量化、运行时、硬件和驱动变化后必须开启新的统计分组。
- 任务、事件和批次分别使用稳定关联 ID；缺失关联 ID 的样本标记为无效，不静默并入分位数。
- 日志采用滚动或定长边界，默认不记录原始截图、录音、游戏音频或系统混合音频。

## 2. 逻辑测量点（24）

| ID | 事件名 | 触发时机 | 主要用途 | 必要关联字段 |
|---|---|---|---|---|
| MP-01 | `app_process_started` | 主进程创建并初始化单调时钟 | MET-T01 起点 | process_id、app_version |
| MP-02 | `config_ui_interactive` | 配置页完成初始化且可响应用户操作 | MET-T01 终点 | restored_config_version、validation_result |
| MP-03 | `control_requested` | 开始、暂停、恢复、停止或退出请求被控制器接受 | MET-T04/T05/T11 起点 | control_action、request_source |
| MP-04 | `new_work_blocked` | 暂停/停止后已禁止新分析与发送任务 | 响应性、停止阶段 | control_action、pending_counts |
| MP-05 | `model_load_started` | 当前所选 O/V 模型开始加载 | MET-T02/T03 起点 | model_id、model_version、quantization、runtime_version |
| MP-06 | `model_service_ready` | 模型服务可接受输入或任务 | MET-T02/T03 终点 | service_id、process_id、loaded_weight_count |
| MP-07 | `input_observed` | 系统确定主要观察时间 | MET-T08/T10 起点 | event_id、source_window、source_types |
| MP-08 | `frame_or_audio_captured` | 画面帧或音频块进入采集缓冲 | 采集链路诊断 | source_id、source_type、capture_sequence |
| MP-09 | `model_task_submitted` | 编排器提交 V 任务或 O 生成请求 | 提交等待与任务关联 | task_id、trigger_type、image_count、style_ids |
| MP-10 | `inference_started` | 服务实际开始推理或生成 | MET-T06/T07/T13 起点 | task_id、service_id、slot_id、budget_chars |
| MP-11 | `model_first_output` | 首个模型输出片段可见 | O 首字延迟辅助数据 | task_id、output_kind |
| MP-12 | `model_result_completed` | 完整结构化结果结束或明确失败 | MET-T06/T07/T13 终点 | task_id、result_status、error_code |
| MP-13 | `result_validated` | 解析、字段补齐与文本规则处理完成 | 模型与后处理拆分 | task_id、event_id、valid_batch_count、valid_message_count |
| MP-14 | `batch_enqueued` | 批次进入发送池、等待队列或高光路径 | MET-T09 起点 | batch_id、route、queue_depth、limit |
| MP-15 | `batch_dequeued_or_dropped` | 等待批次被领取或淘汰/过期 | MET-T09 终点、MET-T10 判定 | batch_id、exit_reason、content_age_ms、queue_depth |
| MP-16 | `batch_send_started` | 发送器开始执行本批发送窗口 | 发送链路拆分 | batch_id、send_window_ms、message_count |
| MP-17 | `danmaku_first_displayed` | 第一条有效弹幕确认提交 Overlay | MET-T04/T05/T08 终点 | batch_id、message_id、event_id、route |
| MP-18 | `danmaku_last_displayed` | 本批最后一条实际显示弹幕提交 | 发送窗口核验 | batch_id、displayed_count、dropped_count |
| MP-19 | `fault_detected` | 主程序确认已有显式故障信号 | MET-T12 起点 | component、fault_type、error_code、process_id |
| MP-20 | `recovery_started` | 冻结规则允许的恢复动作开始 | 恢复阶段拆分 | component、recovery_action、attempt_index |
| MP-21 | `recovery_ready` | 恢复完成并回到允许的可操作/可运行状态 | MET-T12 终点 | component、recovery_result、new_generation |
| MP-22 | `resource_sampled` | 资源采样器记录一次同源快照 | MET-R01～R09 | vram_mib、ram_mib、handle_count、gpu_percent、bounded_depths |
| MP-23 | `cleanup_completed` | 模型、显存及相关子进程完成清理 | MET-T11 终点、MET-R03/S06 | remaining_processes、vram_after_mib、cleanup_result |
| MP-24 | `diagnostic_export_completed` | 手动诊断包生成并完成清单核验 | MET-C06 | package_version、included_sections、user_text_opt_in |

## 3. 通用日志字段

| 字段 | 含义 | 记录规则 |
|---|---|---|
| `schema_version` | 日志逻辑结构版本 | 必填；与最终协议实现解耦 |
| `monotonic_timestamp` | 本机单调时钟 | 必填；耗时计算依据 |
| `utc_timestamp` | UTC 墙上时间 | 必填；只用于跨文件人工关联 |
| `event_name` | `MP-*` 对应逻辑事件 | 必填 |
| `run_id` | 当前运行会话 ID | 必填；再次开始创建新值 |
| `run_generation` | 当前运行代次 | 必填；暂停恢复或全局复位后变化 |
| `mode` | `O`、`V` 或 `common` | 必填 |
| `config_snapshot_hash` | 只读配置快照指纹 | 运行记录必填；不得包含原始音画 |
| `app_version` | 程序版本 | 必填 |
| `model_id/model_version` | 当前模型及版本 | 模型相关事件必填 |
| `runtime_version` | 模型运行时版本 | 模型相关事件必填 |
| `hardware_profile_id` | 测试硬件概要引用 | 性能与稳定性测试必填 |
| `driver_version` | NVIDIA 驱动版本 | 性能与兼容测试必填 |
| `task_id` | O 生成或 V 推理任务 ID | 任务相关事件必填 |
| `event_id` | 统一事件信封 ID | 有事件结果后必填 |
| `batch_id` | 弹幕批次 ID | 发送相关事件必填 |
| `component` | 主程序、模型、采集、Overlay 等组件 | 故障/恢复/清理事件必填 |
| `outcome` | success、failure、timeout、canceled、expired、degraded | 每个终点事件必填 |
| `error_code` | 稳定错误类别 | 失败事件必填；正文不得包含原始音画 |
| `sample_group` | 固定测试条件分组键 | 进入 P50/P95 统计的样本必填 |

## 4. 指标所需最小字段

| 指标组 | 最小字段集合 |
|---|---|
| MET-T01～T03 | 对应起止 MP、单调时间、版本、硬件、sample_group、outcome |
| MET-T04～T08 | 起止 MP、run/task/event/batch 关联 ID、模式、配置快照、outcome |
| MET-T09～T10 | observed_at、enqueued_at、判定时点、route、queue depth/limit、exit_reason |
| MET-T11～T12 | control/fault/recovery/cleanup 时点、组件、动作、attempt、outcome |
| MET-T13 | inference_started_at、result_completed_at、档位、预算区间、timeout_limit_s、outcome |
| MET-R01～R07 | resource_sampled、进程集合、GPU、模式、模型、配置、窗口 ID |
| MET-R08～R09 | 结构名、配置上限、当前值、峰值、淘汰/滚动次数、磁盘大小 |
| MET-S01～S09 | 窗口起止、崩溃/故障/恢复/清理事件、PID 清单、原因与结果 |
| MET-C01～C08 | 环境矩阵、操作步骤版本、期望结果、实际结果、证据引用 |

## 5. P50/P95 与失败样本处理

1. 对每个 `sample_group` 独立排序并计算，禁止把 O/V、不同模型、不同 V 并发或不同图数混合。
2. 超时样本不把超时上限伪装成真实完成时延；在成功延迟分位数之外单独报告超时数和超时率。
3. 取消、旧代次、格式损坏、过期、智能沉默空结果和降级必须使用不同 `outcome`，不得统一记为成功或失败。
4. 首次运行与稳态运行分别标识；是否排除预热样本由后续具体测试方案声明，原始样本均保留。
5. 所有报告必须能从聚合值追溯到去标识化的单次测量记录。

## 6. 数据最小化与边界

- 测量只记录完成指标所需元数据，不新增原始音画持久化。
- 度量采集不得增加模型调用、模型副本或在线服务；资源采样频率由后续测试方案在不造成显著测量扰动的前提下确定。
- 诊断和测试记录中的弹幕文字遵守用户勾选规则；性能统计不依赖弹幕原文。
- 硬件概要只记录测试所需型号、容量、驱动和系统版本，不要求账号或在线身份。
- 日志容量、滚动规则和保留期限必须由后续任务给出明确上限；在上限确定前不得使用无限追加实现。
