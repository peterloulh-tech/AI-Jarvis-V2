# AI Jarvis V2 NFR 工程化附录冻结登记 V1.0

> 任务：AIJARVISV2-8
>
> 冻结输入提交：`c6d74dcd970e71b790f4c84d66d0ddeabb1169cf`
>
> 工程附录版本：`NFR-ENG-APPENDIX-V1.0`

## 1. 权威边界

本登记只冻结 AIJARVISV2-3～7 形成的工程化附录、记录模板和追踪关系。它不是新的正式 NFR，不重写、不替代也不复制正式基线正文。

权威顺序保持不变：

1. `AI_Jarvis_V2_总需求_功能需求正式冻结版_v1.0.md`，SHA-256 `2b9f2bd67bcd4d0e1c510b35b961411c0445e0e4bc9f4da768f237c9073f6d46`，是第一版功能范围的唯一正式基线。
2. `AI_Jarvis_V2_非功能需求_正式冻结版_v1.0.md`，SHA-256 `3f04ecaa48298517692a814d1e0004a042e853b35a825fb360ad987f835084dd`，仍是唯一正式 NFR 基线。
3. `AI_Jarvis_V2_验收标准与测试清单_精简候选版_v0.1.md`，SHA-256 `2fa89eb557e0f638bd4a5430cf9d86e63b17773000bf657409bc6ef287ee5f66`，仍是候选测试规划基线，不因本登记升级为正式冻结版。
4. 本工程附录 V1.0 只提供可执行场景、字段、模板、追踪和阶段出口证据；与上述冻结基线不一致时，必须登记评审并以冻结基线为准。

## 2. 冻结内容

以下 25 个任务专属文件按输入提交中的内容冻结。SHA-256 用于复核工程附录内容，不改变原正式基线的哈希或版本。

| 任务 | 文件 | SHA-256 |
|---|---|---|
| AIJARVISV2-3 | `performance-nfr.md` | `b0b1ff36360e050733c903621002bca195589c1e937cc2fecec1d3e8b4cf4eba` |
| AIJARVISV2-3 | `performance-benchmark-scenarios.md` | `4e0ce1c4e6c165469e7b4de254939496fe73e2072c5cee7d79b9579a2ff3c383` |
| AIJARVISV2-3 | `performance-record-templates.md` | `a49b1a21b6384aa91a2211c5c29f4c288de2d6736feffc45d79468b07f38ff0b` |
| AIJARVISV2-3 | `templates/performance-sample-record.csv` | `097dcff8b7636a37480215d0a0c46a38f64bfe96a9dae62a25dec479e72696b8` |
| AIJARVISV2-3 | `templates/resource-trend-record.csv` | `f3ede1403222b2a7d62b4e00383181f058c4ea6985709fbb529ca33b2245b1c9` |
| AIJARVISV2-4 | `reliability-nfr.md` | `c84c39b14b6d6e6412fdd23f57902f242ce0a6ed147ba1404c9c0efefb145a4f` |
| AIJARVISV2-4 | `reliability-fault-recovery-matrix.md` | `bdf7189d006bd931975b5b000d8f22d0e09b2aa2f72a820da4a26c4179e45778` |
| AIJARVISV2-4 | `reliability-test-and-record-templates.md` | `60396fbbbf051470f5b337800ef1176f13c1e757166b949372256746b3eb3c0e` |
| AIJARVISV2-4 | `templates/reliability-event-record.csv` | `7296d226b113996d49e283fe7335898c9539f7b8662b0b8adc4256484bcfdc0d` |
| AIJARVISV2-5 | `windows-compatibility-nfr.md` | `db0f7031d94a0d384bda84c16824ae784d0896c32c9bcc5e8b71805b65e1be4d` |
| AIJARVISV2-5 | `windows-display-capture-matrix.md` | `1b7d132c5fe780f06842ae02174c617d2727c4f56bdd865ee820dd81ff0cd08a` |
| AIJARVISV2-5 | `windows-device-overlay-scenarios.md` | `565bd35c6460d4d06a413fc7e7714e19496e12317cc892c9127a86e564818c52` |
| AIJARVISV2-5 | `windows-validation-record-templates.md` | `c9afc92aee7d6676c7b79af06a6dd99e37981611fdabd19fc9f6c0c640f63af1` |
| AIJARVISV2-5 | `templates/windows-compatibility-record.csv` | `9c1268e14b6735ab18b8e745c1c73af4e2e0127e1ca2395d500f8b5019acb280` |
| AIJARVISV2-6 | `privacy-security-nfr.md` | `68cbd60eb1a4b8f47c2a4b8cb7abf9de0721072afffd4abc160654adc26374cc` |
| AIJARVISV2-6 | `data-residency-and-clearing-matrix.md` | `d077dd4d3c7221c12b7091208e0949e10ec5b7aad006ff7abc7bc8d568252e9c` |
| AIJARVISV2-6 | `threat-boundaries-and-network-behavior.md` | `fbb3c0c3a76e05f4428fbe28038a72f9addada09048cc282090ea9634aabc3d0` |
| AIJARVISV2-6 | `diagnostic-package-minimization.md` | `979b98dad396b7cecdaf628155b3f8a2ae026b435622004e8f70b0e711e221d5` |
| AIJARVISV2-6 | `privacy-security-validation-record-templates.md` | `b85cc92cc2faa674b2ffab9775eee398d4bd8ff3a46d960e17f3f51f7f5a05c0` |
| AIJARVISV2-6 | `templates/privacy-security-validation-record.csv` | `81507d45e2e95f8ceca0e9b22b03e31ffaec2a8eef67da668554e5d10b7a45b2` |
| AIJARVISV2-7 | `offline-install-update-nfr.md` | `8a3a287decece9ca7affc8d092c6e7ff41766029fa385c6ae19aa1bdd9b1eb6c` |
| AIJARVISV2-7 | `package-layout-and-version-compatibility.md` | `f98b9766722b85a7216faa5f19f1fcd642a4cceb2ce7790d7c401daa1a1814a7` |
| AIJARVISV2-7 | `update-observability-fields.md` | `3a85302b6eeed0462a4d8b8811ec8d8c01b3d26d672c4e9713341f62d8b2f0b1` |
| AIJARVISV2-7 | `offline-install-update-validation-plan.md` | `d48d09b8f527d20ff768bb4c932f75138d940e67e3e3380424e9d69f0da45d50` |
| AIJARVISV2-7 | `templates/offline-update-validation-record.csv` | `e7dbbcb41e3f391aced5631d4a18b1a9bdd71ddce2ac20ce734eca6048eb25ba` |

共享入口 `README.md` 与 `traceability-matrix.md` 由 AIJARVISV2-8 更新，用于指向本登记、归一化追踪与阶段出口；它们不属于上述输入文件哈希集合。

## 3. 版本与变更规则

- `NFR-ENG-APPENDIX-V1.0` 的版本只表示本次工程附录集合，不得简称或宣传为“新的正式 NFR V1.0”。
- 待实测指标的类别、口径和记录入口可以被冻结；尚无证据的数值不得因附录冻结而变成固定承诺。
- 任何修改上述 25 个文件的后续变更必须说明原因、影响的冻结需求、是否改变追踪或验收，并更新工程附录版本与哈希登记。
- 修正拼写、引用或追踪也必须显式评审；不得以编辑性修改掩盖范围变化。
- 阶段出口状态以 [nfr-stage-gate-review.md](nfr-stage-gate-review.md) 为准。本登记完成不等于用户评审通过，也不自动授权启动 AIJARVISV2-9。
