# AIJARVISV2-19 — 审计运行时、模型权重与第三方许可

- 状态：`in_review`（Dashi 于 2026-08-07 回读）
- 交付提交：`d9901d5e68210c6ecb7d908d31c2e3a7cc2f9840`
- 直接依赖：[16](AIJARVISV2-16.md)

## 最终结果与关键文件

新增[V1 运行时、模型权重与第三方许可审计](../../requirements/v1-runtime-model-third-party-license-audit.md)，分别判定 V1 自有代码、固定 vendor、三份 MiniCPM 权重和桌面/打包依赖。根代码 MIT 与固定权重 Apache-2.0 支持商业使用；当前 vendor provider 和 V1 安装包因随包义务及来源缺口阻塞。

## 后续不得破坏的约束

仓库 MIT 不覆盖 vendor、模型或依赖。vendor/model 必须固定 revision、路径和哈希；任何版本、量化、构建后端或依赖图变化均须重审。许可、来源或随包证据不明时不得默认允许选型或分发。

## 验证与遗留

静态覆盖四层 4/4、商业/离线判定 8/8、模型哈希 3/3、桌面直接许可源 4/4、npm 许可字段 313/313。真实缺口为 vendor 参考音频权利、vendor/model notices、npm 305/313 来源与完整性、Python 无锁、CUDA 来源/EULA 未固定及最终安装包许可清单缺失；未运行源码/测试或下载模型。

- 检索关键词：dd8fbf9，b9d15b8，502eec5，MIT，Apache-2.0，MiniCPM，CUDA，离线分发
