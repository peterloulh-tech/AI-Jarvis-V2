# AIJARVISV2-26 — 验证 V 多图单次结构化输出 PoC

- 状态：`in_review`（Dashi 回读 2026-08-12，version 10）
- 交付提交：`4805a5d15c9403090b93e69e4df0fdb3945d3735`；复核修正 `4f2dfb18e12af7134ce78f7dab9bc89cb0b7c137`
- 直接依赖：[AIJARVISV2-25](AIJARVISV2-25.md)

## 最终结果与关键文件

已交付独立 [V 多图 PoC 测试包](../../../../tools/v-multimage-poc/README.md)和[四方审计证据](../../requirements/v-multimage-poc-audit.md)。V-C01 精确锁改为 b10369 可识别的同一官方 Qwen GGUF `1cd86af...`；普通/高光使用 `required` schema 强制一次请求完整输出，只有平静允许智能沉默。Mac/Metal 顺序实测 V-C01 9/9 完整契约 `PASS`；V-C02 required 6/6，但沉默 0/3，整体 `FAIL`。

## 后续不得破坏的约束

保持 V/O 隔离、每轮一个服务/候选/权重、每组一次调用、零修复/补模型/在线核心。大型制品普通运行只查名称和字节数，完整 SHA 仅用于准入、变化或最终组包事件。V-C02 不进入任务 27；本结果不冻结最终产品模型。

## 验证与遗留

25/25 单测、compileall、JSON、静态隔离门通过；两 profile 各 9 次本地推理，原始响应哈希和失败分类已保存。Windows/NVIDIA、8/12GB、显存/GPU、真实许可英雄联盟语料、双人金标和质量阈值仍为 `UNCONFIRMED`，Mac 数据不是产品或真机 PASS。

- 检索关键词：V-C01，V-C02，required，allow_silence，Qwen3-VL，MiniCPM-V，multi-image，JSON Schema
