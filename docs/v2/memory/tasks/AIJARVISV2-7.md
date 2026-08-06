# AIJARVISV2-7 — 编写离线安装、手动更新与可观测性非功能需求

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`c6d74dcd970e71b790f4c84d66d0ddeabb1169cf`
- 直接依赖：[AIJARVISV2-2](AIJARVISV2-2.md)

## 最终结果与关键文件

定义离线安装、包分离、兼容回退、手动更新、卸载及版本化字段。入口为[安装更新 NFR](../../requirements/offline-install-update-nfr.md)、[包兼容规则](../../requirements/package-layout-and-version-compatibility.md)、[可观测字段](../../requirements/update-observability-fields.md)和[验证方案](../../requirements/offline-install-update-validation-plan.md)。

## 后续不得破坏的约束

终端用户无需开发环境；程序更新不重下全部模型，失败不得破坏原组合；禁止自动、后台或强制更新。卸载策略见 [`DECISIONS.md`](../DECISIONS.md)。

## 验证与遗留

链接、表格、ID、56列CSV和差异白名单已静态核验。离线安装、断网、更新/回退、卸载、版本日志和诊断仍待 Windows 实测。

- 检索关键词：INST-NFR，PKG，COMPAT，手动更新，离线包，回退，卸载
