# AIJARVISV2-6 — 编写隐私、安全与数据生命周期非功能需求

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`11b2c111e4a98181a73e4ed4146b3a5e4f333589`
- 直接依赖：[AIJARVISV2-2](AIJARVISV2-2.md)

## 最终结果与关键文件

形成隐私安全 NFR、16类数据驻留/清除、9个威胁边界、9条数据流、6类网络行为，以及断网、落盘、完整性和诊断包最小化方案。入口为 [`privacy-security-nfr.md`](../../requirements/privacy-security-nfr.md)、[`data-residency-and-clearing-matrix.md`](../../requirements/data-residency-and-clearing-matrix.md) 与 [`diagnostic-package-minimization.md`](../../requirements/diagnostic-package-minimization.md)。

## 后续不得破坏的约束

核心无需账号和联网；无自动遥测、上传或第三方外传；原始音画默认不落盘；IPC保持本机边界；诊断包默认不含原始音画，弹幕仅在用户勾选后导出。

## 验证与遗留

文档链接、ID、35列CSV和差异白名单已静态核验。断网、落盘、清除、脱敏、诊断包和完整性仍须指定构建实测。

- 检索关键词：PRIV-NFR，数据驻留，原始音画，断网，IPC，诊断包
