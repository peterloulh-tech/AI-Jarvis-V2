# AIJARVISV2-5 — 编写 Windows 兼容、采集与 Overlay 非功能需求

- 状态：`done`（Dashi 于 2026-08-06 回读）
- 交付提交：`e10bbdc90f0cc619b1064b2515a3be384c1a715e`
- 直接依赖：[AIJARVISV2-2](AIJARVISV2-2.md)

## 最终结果与关键文件

形成 Windows/采集/Overlay NFR、15组分辨率与缩放、6类多显示器、12类采集、9类设备、8类 Overlay、8类系统事件及简中检查。入口为 [`windows-compatibility-nfr.md`](../../requirements/windows-compatibility-nfr.md)、[`windows-display-capture-matrix.md`](../../requirements/windows-display-capture-matrix.md) 和 [`windows-device-overlay-scenarios.md`](../../requirements/windows-device-overlay-scenarios.md)。

## 后续不得破坏的约束

第一版正式支持仅 Windows 11 64位、NVIDIA独显、简体中文；不得宣称 Windows 10、非NVIDIA、远程桌面或虚拟机支持。Overlay 必须在1080P/2K/4K × 五档缩放下验证点击穿透。

## 验证与遗留

ID、链接、追踪和CSV表头已静态核验；所有物理机、显示器、音视频设备与点击穿透组合仍待指定构建实测。

- 检索关键词：WIN-NFR，Windows 11，NVIDIA，DPI，Overlay，点击穿透
