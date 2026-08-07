# AIJARVISV2-20 — 建立依赖治理、SBOM 与替换策略

- 状态：`in_review`（Dashi 于 2026-08-07 回读）
- 交付提交：`26c235376c45926ff2a692e7f5f59bea2730fb8c`
- 直接依赖：[16](AIJARVISV2-16.md)

## 最终结果与关键文件

新增[依赖治理、SBOM 与替换策略](../../requirements/dependency-governance-sbom-and-replacement-strategy.md)，覆盖 C/C++、Python、Node、安装器和模型/runtime 五类生态；统一精确锁定、来源与 SHA-256、CycloneDX 1.6 JSON、vendor/patch 可复现记录、许可/漏洞发布门和高风险替换顺序。

## 后续不得破坏的约束

锁文件只证明解析输入，SBOM 必须对实际程序包和模型包生成并与最终文件核对。未知许可、不可履行义务、来源/哈希缺失、可达 Critical 或未处置 High 漏洞均阻断；例外不得覆盖权利不明。任何 revision、来源、patch、构建选项、量化或依赖图变化须重新准入。

## 验证与遗留

静态覆盖生态 5/5、治理环节 6/6、SBOM 字段 12/12、阻断门 5/5、V1 风险 8/8。真实缺口为尚无 V2 仓库、锁文件、最终构建产物和漏洞扫描批次；本交付是策略/模板，不代表实际依赖或发布已通过。

- 检索关键词：CycloneDX 1.6，SBOM，DEP-ID，vendor，patch，SHA-256，NOASSERTION，Critical
