# AIJARVISV2-23 — 验证 O 持续全双工与自主文字输出 PoC

- 状态：`in_review`（Dashi 于 2026-08-09 回读）
- 交付提交：便携链至 `9869933d07bb7e962a73887347d84235691d72a4`；runner 修复 `07f32c1500514f25fc5106c106ffc952bfd52299`；Reuse-First/官方基线 `53c8c1e3697459caa02425490a9016d856d45c6a`；四方 Delta 为本轮文档提交
- 直接依赖：[AIJARVISV2-22](AIJARVISV2-22.md)

## 最终结果与关键文件

[PoC 记录](../../requirements/o-duplex-autonomous-text-poc.md)与[`现场包`](../../../../tools/aijarvisv2-23/)提供 O-C01 前检、便携入口及 P-02～04 采集。三层 Reuse-First 与 Local O 基线已固化；[`O Runtime 四方 Delta`](../O_RUNTIME_FOUR_WAY_DELTA.md)确认 Task23 绕过正式 adapter/worker/IPC、代表性为 `PARTIAL`，3 秒素材实际只产生 3 秒一次 decision，Locked C API 到 V2 没有 `is_speak` 语义反转。本轮未改 runner、产品代码或 LISTEN/SPEAK 逻辑。

## 后续不得破坏的约束

只允许 O-C01 固定来源复跑；不得用参考音频、TTS、业务触发壳或补调用替代。`O-RISK-23-01` 关闭前不得宣称可行或启动任务 24。

## 验证与遗留

runner 修复既有验证为 `diff --check`、8/8 静态断言及 Formal/cleanup truth table；四方审计完成 14/14 段 source/reference/symbol 核对，确认前三次 LISTEN 不会在单 case 反复归零、async 正常路径持续消费、plain no-ref/no-TTS prompt 结构有效。仍需先把 fixture 对齐约 1 秒 cadence 做单变量真机复验，再决定是否检查 result failure 或 prompt 分布。

- 检索关键词：O-C01，Four-Way Delta，PARTIAL，3 秒 cadence，SPEAK/LISTEN，O-RISK-23-01，TTS 0
