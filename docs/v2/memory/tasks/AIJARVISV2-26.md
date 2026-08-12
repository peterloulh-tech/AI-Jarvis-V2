# AIJARVISV2-26 — 验证 V 多图单次结构化输出 PoC

- 状态：`done`（2026-08-13 用户确认 Qwen 制品身份并重新验收）
- 交付提交：`4805a5d15c9403090b93e69e4df0fdb3945d3735`；复核修正 `4f2dfb18e12af7134ce78f7dab9bc89cb0b7c137`；验收修正 `c8fab1c`
- 直接依赖：[AIJARVISV2-25](AIJARVISV2-25.md)

## 最终结果与关键文件

已交付独立 [V 多图 PoC 测试包](../../../../tools/v-multimage-poc/README.md)和[四方审计证据](../../requirements/v-multimage-poc-audit.md)。V-C02 原 6/9 根因是先生成 emit 的决策偏置与旧平静图事件歧义；v3 改为先生成 level、静默/发言完整互斥 schema、无主体平静图并拒绝占位事件。Mac/Metal 严格顺序重跑 V-C01/V-C02：两个 profile 的 JSON/schema、完整契约、emit、level 均 9/9，required 各 6/6、智能沉默各 3/3，每个 profile 调用 9、修复 0，硬门均为 `PASS`。

## 后续不得破坏的约束

保持 V/O 隔离、每轮一个服务/候选/权重、每组一次调用、零修复/补模型/在线核心。大型制品普通运行只查名称和字节数，完整 SHA 仅用于准入、变化或最终组包事件。本结果不冻结最终产品模型，也不提前启动任务 27。

## 验证与遗留

硬门要求结构、emit 与 level 同时正确，并新增 `EVENT_PLACEHOLDER` 拒绝占位主要事件。锁定 Qwen 两份制品已重新保存到正式模型目录，首次保存时 SHA/字节数与任务25记录完全一致；后续普通运行仅做 fast identity。26/26 单测、compileall、JSON、计划一致性、V/O 隔离、loopback-only 与服务退出门通过。Windows/NVIDIA、8/12GB、显存/GPU、真实许可英雄联盟语料、双人金标和质量阈值仍为 `UNCONFIRMED`，Mac 数据不是产品或真机 PASS。

- 检索关键词：V-C01，V-C02，required，allow_silence，Qwen3-VL，MiniCPM-V，multi-image，JSON Schema
