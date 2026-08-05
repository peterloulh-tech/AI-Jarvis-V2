# AI Jarvis V2 安装更新与版本化可观测字段

> 任务：AIJARVISV2-7
> 追踪：FR-18.03/18.04/20/21；NFR-07.01/08.01；TERM-037；MP-24；MET-C04/C06/C07；AC-D01/D04～D06。

本文件补充安装、更新、回退、卸载和主页面性能提示所需的结构化元数据。它不修改 AIJARVISV2-2 的 `TERM-*`、`MET-*`、`MP-*` 定义，也不放宽 AIJARVISV2-6 的日志/诊断字段允许列表。

## 1. 字段治理规则

1. 每条记录包含 `schema_version`、UTC 时间和稳定关联 ID；耗时统计仍使用任务 2 的单调时钟与既有起止点。
2. 版本和清单身份来自 `package-layout-and-version-compatibility.md`，不得从展示文本或安装路径反推。
3. 字段只记录结构化元数据、计数、结果和摘要；不得记录凭据、原始音画、模型输入、提示词或未勾选弹幕文字。
4. 日志必须滚动或定长；具体容量与保留值由后续实现/实测确定，未确定时不得采用无限追加。
5. 安装/更新记录不得触发遥测、自动上传、远程版本查询或后台下载。
6. 新字段若不在本表或任务 6 允许列表中，先标记 `REVIEW_REQUIRED`，不得静默写入。

## 2. 通用版本身份字段

| Field ID | 字段 | 适用记录 | 必填条件 | 含义/最小化规则 |
|---|---|---|---|---|
| OBS-ID-001 | `schema_version` | 全部 | 必填 | 当前逻辑记录结构版本 |
| OBS-ID-002 | `operation_id` | 安装/更新/卸载 | 必填 | 本次用户操作稳定关联 ID，不含身份信息 |
| OBS-ID-003 | `event_name` | 全部 | 必填 | 本表第 6 节事件名或既有 MP 名称 |
| OBS-ID-004 | `monotonic_timestamp` / `utc_timestamp` | 运行期可测事件 | 按任务 2 规则 | 耗时只使用单调时钟；UTC 仅关联 |
| OBS-ID-005 | `app_package_id` / `app_package_version` | 全部 | 必填 | 当前或目标程序包身份 |
| OBS-ID-006 | `build_commit` | 全部 | 必填 | 程序构建提交 |
| OBS-ID-007 | `runtime_version` / `runtime_manifest_digest` | 安装、更新、运行、诊断 | 必填 | 运行时身份和清单摘要 |
| OBS-ID-008 | `model_id` / `model_version` / `quantization` | 模型相关 | 必填 | 当前或目标模型身份 |
| OBS-ID-009 | `model_manifest_digest` | 模型相关 | 必填 | 模型清单摘要；不是模型文件内容 |
| OBS-ID-010 | `config_schema_version` / `config_snapshot_hash` | 配置相关 | 必填 | schema 和去内容化快照摘要 |
| OBS-ID-011 | `package_manifest_schema_version` | 包操作 | 必填 | 解析清单的 schema 版本 |
| OBS-ID-012 | `log_schema_version` / `diagnostic_schema_version` | 日志/诊断 | 必填 | 支持离线排错与跨版本读取 |

## 3. 安装、更新与回退字段

| Field ID | 字段 | 适用阶段 | 规则 |
|---|---|---|---|
| OBS-UPD-001 | `operation_type` | 全部 | `install_program`、`update_program`、`install_model`、`replace_model`、`uninstall` |
| OBS-UPD-002 | `initiated_by_user` / `request_source` | `precheck` | 用户手动操作必须为 true，并记录本地 UI/本地命令类别 |
| OBS-UPD-003 | `source_kind` / `source_ref_hash` | `precheck/stage` | `local_offline_package` 或用户主动获取来源；不记录原始绝对路径 |
| OBS-UPD-004 | `network_used` / `dns_count` / `external_connection_count` | 全部 | 完整离线路径均为 0；手动联网路径另行明确 |
| OBS-UPD-005 | `phase` | 全部 | `precheck`、`stage`、`verify`、`activate`、`postcheck`、`rollback`、`cleanup` |
| OBS-UPD-006 | `from_identity` / `to_identity` | 更新/替换 | 使用版本身份元组的结构化摘要，不含用户内容 |
| OBS-UPD-007 | `manifest_result` / `digest_result` | `verify` | `match`、`mismatch`、`missing`、`unsupported_schema` |
| OBS-UPD-008 | `compatibility_result` / `compatibility_reason_code` | `verify` | `compatible`、`incompatible`、`unknown`；原因使用稳定码 |
| OBS-UPD-009 | `config_preservation_result` / `model_preservation_result` | 程序更新 | 分别记录 retained、changed、not_applicable、failed |
| OBS-UPD-010 | `activation_result` / `postcheck_result` | 激活后 | 成功、失败和证据引用；不得只记“完成” |
| OBS-UPD-011 | `rollback_required` / `rollback_result` / `restored_identity` | 失败路径 | 记录是否回退及恢复的活动身份 |
| OBS-UPD-012 | `error_code` / `outcome` | 终点 | 使用稳定错误类别和任务 2 的 outcome；正文按任务 6 脱敏 |
| OBS-UPD-013 | `temporary_residue_count` | `cleanup` | 暂存/半成品残留计数，不记录用户路径 |

## 4. 卸载字段

| Field ID | 字段 | 规则 | 通过判定用途 |
|---|---|---|---|
| OBS-UN-001 | `user_config_choice_presented` | 卸载界面是否显示明确选择 | 必须为 true |
| OBS-UN-002 | `delete_user_config_selected` | 用户当次选择；默认必须为 false | 验证默认保留与显式删除两组 |
| OBS-UN-003 | `user_config_before_count` / `user_config_after_count` | 使用文件/记录计数或等价证据，不记录正文 | 默认组 after 保留；删除组按选择清除 |
| OBS-UN-004 | `remaining_model_processes` | 完成后模型相关 PID 数 | 必须为 0 |
| OBS-UN-005 | `remaining_capture_processes` | 完成后采集相关 PID 数 | 必须为 0 |
| OBS-UN-006 | `remaining_overlay_processes` | 完成后 Overlay 相关 PID 数 | 必须为 0 |
| OBS-UN-007 | `cleanup_result` | 引用任务 4 停止/清理结果 | 必须成功或保留失败证据 |
| OBS-UN-008 | `uninstall_result` | 程序内容处理结果、配置选择结果、错误码 | 不把部分完成静默记为成功 |

## 5. 主页面性能提示字段

| Field ID | 字段 | 规则 |
|---|---|---|
| OBS-UI-001 | `warning_id` / `warning_reason_code` | 稳定提示 ID 和原因码，不包含未经校准的固定承诺 |
| OBS-UI-002 | `hardware_profile_id` | 引用任务 2 的硬件概要；不记录设备序列号或账号 |
| OBS-UI-003 | `mode` / `model_id` / `model_version` | 记录提示所针对的当前选择 |
| OBS-UI-004 | `metric_ref` / `calibration_ref` | 只能引用任务 2/3 已定义指标或待校准项，不创建第二套阈值 |
| OBS-UI-005 | `observed_value_ref` / `limit_source` | 值引用与来源；门槛未冻结时明确 `待实测校准` |
| OBS-UI-006 | `displayed_at` / `dismissed_at` | 提示可见性证据 |
| OBS-UI-007 | `automatic_config_change_count` | 提示后模式、模型质量、频率或采集配置的自动变更次数；必须为 0 |

提示是用户可见信息，不是自动降级动作。用户之后手动修改配置需形成独立的用户操作记录，不得算作自动修复。

## 6. 逻辑事件名

| Event ID | `event_name` | 触发点 | 必要字段 |
|---|---|---|---|
| OBS-EVT-001 | `package_operation_requested` | 用户确认安装/更新/卸载 | operation_id、operation_type、initiated_by_user、source_kind |
| OBS-EVT-002 | `package_precheck_completed` | 前置、清单和兼容检查完成 | from/to identity、manifest/digest/compat results、outcome |
| OBS-EVT-003 | `package_activation_completed` | 活动版本切换尝试结束 | activation_result、observed identity、error_code |
| OBS-EVT-004 | `package_rollback_completed` | 回退尝试结束 | rollback_result、restored_identity、postcheck_result |
| OBS-EVT-005 | `package_operation_completed` | 清理后操作结束 | outcome、temporary_residue_count、network counts |
| OBS-EVT-006 | `uninstall_cleanup_completed` | 卸载清理复核完成 | config choice、remaining process counts、outcome |
| OBS-EVT-007 | `performance_warning_displayed` | 主页面显示提示 | warning fields、automatic_config_change_count |

这些是安装/维护域的记录事件，不新增 `MP-*` 测量点，也不改变 `MP-24 diagnostic_export_completed`。若后续需要把某事件纳入统一时延统计，必须回到任务 2 框架评审。

## 7. 诊断包版本补充

任务 6 的 DIAG-001～009 和排除项保持不变。DIAG-001 版本 section 至少补齐本文件 OBS-ID-005～012 中适用字段；安装/更新失败时可包含 OBS-UPD 字段的结构化结果，但不得包含安装绝对路径、包二进制、模型权重、凭据或远程负载正文。

`MP-24` 的 `package_version` 指诊断包自身版本；不得用它替代程序包、模型包、运行时、清单或 schema 版本。

## 8. 可观察性结论边界

字段存在只证明可记录，不证明安装、更新、回退或卸载成功。字段完整性按 `MET-C06/C07` 逐次核验；耗时和性能分布仍使用任务 2/3 模板，不在本文定义新分位数、阈值或对外承诺。
