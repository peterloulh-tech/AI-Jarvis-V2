# AI Jarvis V2 隐私与安全验证记录模板

> 任务：AIJARVISV2-6
> 使用规则：结论必须引用原始证据；尚未执行时留空实际结果，不得预填通过。

批量记录可使用 [templates/privacy-security-validation-record.csv](templates/privacy-security-validation-record.csv)；字段含义和判定仍以本文为准。

## 1. 执行头

| 字段 | 记录值 |
|---|---|
| execution_id | |
| case_id | |
| build_commit / app_version | |
| package_manifest_version | |
| model_id / version / digest_result | |
| Windows version / Build | |
| CPU / GPU / driver | |
| test_profile_id（不得记录用户名） | |
| mode / config_snapshot_hash | |
| started_at_utc / ended_at_utc | |
| operator / reviewer | |
| evidence_root | |

## 2. 数据类驻留与清除记录

| data_class_id | source | purpose | residency | limit_kind | configured_limit | observed_peak | limit_action | clear_trigger | before_count | after_count | export_rule | evidence | result |
|---|---|---|---|---|---|---:|---|---|---:|---:|---|---|---|
| DATA-___ | | | | | | | | | | | | | |

要求：DATA-001～016 逐项记录；不适用项说明依据。原始音画的持久化/上传结果另在第 5 节记录，预期为 0。

## 3. 网络与 IPC 记录

| case_id | process | endpoint_type | direction | bind_or_peer_scope | protocol | endpoint_category | dns_count | connection_count | bytes | payload_class | declared_net_or_flow_id | evidence | result |
|---|---|---|---|---|---|---|---:|---:|---:|---|---|---|---|
| NET/IPC-___ | | | | | | | | | | | | | |

必须分别汇总：外部出站连接、外部入站/监听、本机 IPC、DNS 请求和未声明端点。负载正文不得写入记录。

## 4. 断网核心闭环记录

| 检查项 | O 实际/证据 | V 实际/证据 | 结果 |
|---|---|---|---|
| 完整安装且模型已在本机 | | | |
| 无账号/登录 | | | |
| 外部网络阻断方式已记录 | | | |
| 配置页可交互 | | | |
| 核心输入、推理和文字显示完成 | | | |
| 暂停/恢复/停止完成 | | | |
| 外部出站连接数 = 0 | | | |
| DNS 请求数 = 0 | | | |
| 本机 IPC 已单独归类 | | | |
| 未声明端点数 = 0 | | | |

## 5. 原始音画落盘/上传检查

| case_id | data_class_id | scan_scope | before_snapshot | after_snapshot | changed_entry_count | media_signature_hits | persisted_raw_events | uploaded_raw_events | evidence | result |
|---|---|---|---|---|---:|---:|---:|---:|---|---|
| DISK-___ | DATA-00_ | | | | | | | | | |

扫描范围至少包含应用安装区、应用数据区、系统临时目录、用户选择输出目录和测试期间实际打开的文件句柄目标。不能只按扩展名判断，必须核对内容签名或等价证据。

## 6. 日志脱敏记录

| case_id | scenario | schema_version | field_count | undeclared_field_count | raw_media_hits | free_text_hits | path_identity_hits | credential_marker_hits | redaction_rule_version | evidence | result |
|---|---|---|---:|---:|---:|---:|---:|---:|---|---|---|
| LOG-___ | | | | | | | | | | | |

测试标记必须是人工构造的非真实敏感值。任何真实凭据或真实用户内容不得用于验证。

## 7. 诊断包隐私记录

| case_id | stopped_state | user_text_opt_in | included_sections | manifest_entries | missing_required_fields | undeclared_entries | raw_media_hits | danmaku_text_hits | other_free_text_hits | network_events | temp_residue | evidence | result |
|---|---:|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---|---|
| DIAG-TEST-___ | | | | | | | | | | | | | |

默认组和勾选弹幕文字组必须分别执行。默认组 `raw_media_hits=0`、`danmaku_text_hits=0`；勾选组 `raw_media_hits=0`，弹幕条目必须与 UI 选择和内容清单一致。

## 8. 完整性记录

| case_id | artifact_type | artifact_id | version | source_ref | size_expected | size_actual | digest_algorithm | digest_expected | digest_actual | match | load_or_use_blocked_on_mismatch | evidence | result |
|---|---|---|---|---|---:|---:|---|---|---|---|---|---|---|
| INTEGRITY-TEST-___ | | | | | | | | | | | | | |

必须包含至少一个受控不匹配样本，证明不匹配不会进入可用/加载状态。该结果只证明与清单的一致性，不得写成全面安全结论。

## 9. 采集权限与生命周期记录

| case_id | state_transition | selected_sources | actual_sources | capture_events_before_boundary | capture_events_after_boundary | old_history_after_restart | runtime_logs_after_close | lock_marker_fields | evidence | result |
|---|---|---|---|---:|---:|---:|---:|---|---|---|
| PERM/LIFE-___ | | | | | | | | | | |

覆盖未开始、开始、暂停、恢复、停止、再次开始、正常关闭和异常退出后重启。任务 4 的恢复动作直接引用，不在本记录重定义。

## 10. 验收汇总

| 要求/候选项 | 适用 case | 期望 | 实际结论 | 证据 | 评审备注 |
|---|---|---|---|---|---|
| PRIV-NFR-001～012 | | | | | |
| AC-D01 无自动上传 | NET-TEST-001/002 | 外部连接与自动上传 0 | | | |
| AC-D02 原始音画不落盘 | DISK-TEST-001～003 | 持久化/上传 0 | | | |
| AC-D03 轻量历史边界 | LIFE-TEST-001/002 | 再次开始/关闭后旧记录 0 | | | |
| AC-D04 滚动日志 | LOG/LIFE | 有界且关闭清除 | | | |
| AC-D05 诊断包 | DIAG-TEST-001/006 | 必备字段完整、手动本地导出 | | | |
| AC-D06 诊断包隐私 | DIAG-TEST-001/003/006 | 默认无原始音画/弹幕；弹幕仅勾选 | | | |

最终状态只能使用 `PASS_FROZEN`、`FAIL_FROZEN`、`DATA_INCOMPLETE`、`REVIEW_REQUIRED` 或有依据的 `NOT_APPLICABLE`。任何失败或未声明行为必须保留证据并进入评审，不得在记录中改变冻结范围。
