# AIJARVISV2-22 — 筛选 O 模型与运行时候选

- 状态：`in_review`（Dashi 于 2026-08-07 回读）
- 交付提交：`361215800d79cef09910ac38e9b1d9538e85c38d`
- 直接依赖：[AIJARVISV2-21](AIJARVISV2-21.md)

## 最终结果与关键文件

新增 [O 候选筛选](../../requirements/o-model-runtime-candidate-screening.md)，以八项门审查 4 个组合。唯一进入任务 23 的 `O-C01` 固定为 MiniCPM-o 4.5 GGUF 与固定 `llama.cpp-omni` 的 TTS 关闭双工路径；Qwen2.5-Omni 因证据缺口保持 `HOLD`。

## 后续不得破坏的约束

`O-C01` 只批准 PoC，不批准 V1 provider、模型包或最终选型。自主触发只能来自同一模型的 `SPEAK/LISTEN`，不得用业务壳或额外模型替代；三批文字须来自一次生成，TTS/补调用为 0。候补不得自动替换，来源、权重、量化、patch 或依赖变化须重新准入。

## 验证与遗留

静态覆盖组合 4/4、硬门 8/8、交付物 4/4、O10 能力面 7/7、P1 入口 9/9；链接、接口、固定 revision/哈希与差异检查通过。仍缺 O10 闭环、Windows 16GB、停止/显存、离线包、许可、P50/P95 和长稳实测。

- 检索关键词：O-C01，MiniCPM-o 4.5，llama.cpp-omni，SPEAK/LISTEN，no-tts，Qwen HOLD，O10
