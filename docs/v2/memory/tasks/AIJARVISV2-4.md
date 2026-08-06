# AIJARVISV2-4 — 编写可靠性、恢复与长时间运行非功能需求

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`2ca8637f405d16bee8f04b40666208547850fe76`
- 直接依赖：[AIJARVISV2-2](AIJARVISV2-2.md)

## 最终结果与关键文件

建立14条可靠性 NFR、16类故障恢复矩阵及故障、4h/8h、暂停/恢复/停止、异常退出和单实例记录模板。关键文件为 [`reliability-nfr.md`](../../requirements/reliability-nfr.md)、[`reliability-fault-recovery-matrix.md`](../../requirements/reliability-fault-recovery-matrix.md) 和 [`reliability-test-and-record-templates.md`](../../requirements/reliability-test-and-record-templates.md)。

## 后续不得破坏的约束

组件故障不得拖死主程序，所有等待与结构必须有界；停止须释放显存、进程和孤儿；第二实例不得加载第二份模型。4h是正式P0，8h不是对外承诺。

## 验证与遗留

REL/FAULT ID、链接、CSV字段和差异范围已核验。恢复/停止耗时、V超时与重启保护、资源增长、故障注入、孤儿清理及4h/8h结果仍待实测。

- 检索关键词：REL-NFR，FAULT，故障隔离，有界等待，停止清理，单实例
