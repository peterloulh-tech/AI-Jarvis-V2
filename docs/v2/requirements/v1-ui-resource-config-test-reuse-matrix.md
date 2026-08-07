# V1 UI、资源、配置与测试资产复用矩阵

> Dashi：AIJARVISV2-18
> 只读基线：`LYiHub/pub-local-jarvis@dd8fbf97a3e0f96239a0a465398654be68e88e15`
> 前置清单：[V1/原作者只读源码快照与资产清单](v1-source-snapshot-and-asset-inventory.md)

## 1. 结论与等级

本矩阵只读取固定 Git 对象，不检出、执行或修改 V1。覆盖 `desktop/src/` 24/24 个文件、`config/default.toml`、8/8 个非 vendor 脚本、31/31 个项目测试文件和 8/8 个非 vendor 位图。结论不改变冻结范围，也不替代 AIJARVISV2-19/20 的依赖许可与准入审计。

等级沿用任务 17：`D` 可按固定符号直接提取，`M` 修改后复用，`R` 只参考行为或测试模式，`W` 按 V2 契约重写；与冻结范围冲突的内容标为 `N/A`。本任务没有批准 `D` 级资产。原作者自有代码按仓库根 MIT 声明评估，但 Electron、Node/Python/CUDA 等依赖仍待任务 19/20；媒体文件必须有逐项来源与许可，不能仅凭根 MIT 推定可分发。

## 2. UI 与配置矩阵

| ID | 固定提交路径/边界 | 事实与范围判断 | 等级 | 来源/许可 | 迁移建议 |
|---|---|---|---|---|---|
| UI-01 | `desktop/src/main.js` 的 launcher 窗口；`ui/launcher.{html,css,js}` | `contextIsolation`、禁用 Node、sandbox 和最小尺寸可参考；页面混入桌宠、长期记忆、生图、课程和 V1 状态，且没有 V2 模式/模型/画面源/风格配置锁 | `W` | 固定提交自有代码，根 MIT；Electron 许可待任务 19 | 重建 V2 主页面与只读运行快照；只参考 BrowserWindow 安全选项和最小窗口 smoke 模式 |
| UI-02 | `desktop/src/preload.js` | 暴露聊天、记忆、生图、桌宠拖动等 V1 IPC；不符合尚待冻结的 V2 最小 IPC allowlist | `W` | 固定提交自有代码，根 MIT；Electron 待审 | 按 V2 schema 重建最小桥接，不复制 V1 channel 集合 |
| UI-03 | `desktop/src/barrage-overlay.js`、`ui/barrage.{html,css,js}`；`main.js` 的 barrage 窗口 | 已有透明、置顶、全工作区、`setIgnoreMouseEvents(true)`、inactive show 和 renderer `pointer-events:none`；仅主屏全屏、5 固定 lane、单向 6 秒动画，缺少横/竖区域、四方向、速度分布、DPI/多屏绑定、失效暂停和高光样式 | `M` | 固定提交自有代码，根 MIT；Electron 待审 | 只按具体 helper/样式规则提取；以 FR-16、AC-B06～B08 重写布局、显示器与生命周期边界 |
| UI-04 | `pet-display.js`、`pet-hit-test.js`、`pet-state.js`、`pet-window.js`、`privacy-mode.js`、`ui/pet.*`；`main.js` 的 pet 窗口 | 桌宠、聊天气泡、拖动、课程状态和拟人隐私提醒均不属于 V2；其中显示器匹配算法只可作为 Overlay 选屏反例/参考 | `N/A` | 固定提交自有代码，根 MIT；Electron 待审 | 不迁移桌宠 UI/交互；如需显示器匹配，从 V2 显示契约重写并保留“不跨屏回退”测试意图 |
| UI-05 | `game-profiles.js`、`scene-policy.js`、`image-generation-settings.js` | 内置非重点游戏提示词、`course` 场景和外部生图 API 与 V2 范围不符；JSON 归一化、原子保存和敏感值不回显仅是实现参考 | `R` / `N/A` | 固定提交自有代码，根 MIT；外部 API/依赖不获准 | 丢弃内置提示词、课程和生图设置；配置持久化须在 V2 schema、离线与配置锁规则冻结后重写 |
| UI-06 | `backend-manager.js`、`event-router.js` | 含可参考的进程监督/事件转发，也混入聊天、课程、记忆 API；源码提取边界已由任务 17 的 SRC-10/SRC-19 判定 | `R` | 固定提交自有代码，根 MIT；`ws` 等待任务 19 | 不在本任务重复批准；UI 只消费未来统一事件信封 |
| UI-07 | `ui/app-icon.{html,css}` | 只服务图标生成，不是 V2 产品 UI；生成结果 `desktop/assets/icon.png` 缺少独立来源/许可 | `R` | 代码为固定提交根 MIT；输出媒体许可不明 | 可参考可重复生成思路，不复用现有输出或视觉设计 |
| CFG-01 | `config/default.toml` 的 `app/server/native/scene/barrage` | TOML 分区可参考；值绑定 V1 runtime，`game_barrage_similar_seconds` 与 V2 禁止语义去重冲突，也没有 O/V、画面/音频源、风格、Overlay 和配置锁 schema | `R` | 固定提交自有配置，根 MIT；运行依赖待审 | 由冻结 FR/NFR 新建 V2 配置 schema；不迁移 V1 默认值或相似去重字段 |
| CFG-02 | `config/default.toml` 的 `memory/courses` | 长期记忆与课程属于第一版排除范围 | `N/A` | 固定提交路径可追溯；根 MIT 不改变范围冲突 | 不进入 V2 配置、迁移器或兼容层 |

## 3. 位图与禁用资产

以下来源均为固定提交中的精确路径，SHA-256 见前置清单。仓库没有逐项作者、原始来源或独立许可记录；因此“来源可定位”不等于“许可已确认”。

| 路径 | V1 用途 | 独立许可结论 | V2 决定 |
|---|---|---|---|
| `desktop/assets/icon.png` | 应用/托盘/安装器图标 | 未记录；根 MIT 不足以证明媒体权利 | `W`：禁用并重新制作有来源记录的应用图标；不带入托盘用途 |
| `desktop/assets/pet/closed-eyes.gif` | 桌宠隐私状态 | 未记录 | `N/A`：范围冲突且许可不明，禁用 |
| `desktop/assets/pet/course.gif` | 桌宠课程状态 | 未记录 | `N/A`：范围冲突且许可不明，禁用 |
| `desktop/assets/pet/idle.gif` | 桌宠空闲状态 | 未记录 | `N/A`：范围冲突且许可不明，禁用 |
| `desktop/assets/pet/normal.gif` | 桌宠普通状态 | 未记录 | `N/A`：范围冲突且许可不明，禁用 |
| `docs/images/pet-chat.png` | 桌宠聊天产品截图 | 未记录 | `N/A`：范围冲突且许可不明，禁用 |
| `src/jarvis_backend/assets/jarvis-character-reference.png` | 记忆生图角色参考 | 未记录 | `N/A`：长期记忆/生图范围冲突，禁用 |
| `src/jarvis_backend/assets/jarvis-style-reference.png` | 记忆生图风格参考及视觉 smoke 输入 | 未记录 | `N/A`：长期记忆/生图范围冲突，禁用；smoke test 必须换用可审计夹具 |

桌宠、托盘常驻、面向用户聊天、课程、长期记忆和生图相关 UI、IPC、配置、测试输出统一进入禁用清单。禁止为了兼容 V1 而保留隐藏入口、默认配置、生成器或安装包资源。

## 4. 构建、安装与脚本矩阵

| 路径 | 复用结论 | 等级 | 迁移门槛 |
|---|---|---|---|
| `start-real.cmd`、`start-real.ps1` | 源码开发入口，要求本机开发环境，不是 V2 用户安装资产 | `R` | 仅参考开发 smoke；不得替代完整离线安装包 |
| `desktop/scripts/build.js` | 固定 NSIS x64 构建入口和失败传播可留 | `M` | 先冻结程序/模型/配置/诊断包拓扑、依赖锁和离线来源 |
| `desktop/scripts/install-dependencies.js` | `npm ci`、运行中 Electron 检测属于构建机流程 | `R` | 保持用户机器无需 Node；网络镜像必须纳入任务 20 来源治理 |
| `desktop/scripts/prepare-release.ps1` | 固定源码、CPU/CUDA 双 worker、运行时 manifest 与 SHA-256 模式有价值；当前单包并复制未单独获准的 vendor 参考音频 | `M` | 任务 19/20 许可与 SBOM 通过后，删除未批准媒体并实现包分离/兼容/回退 |
| `desktop/scripts/resource-fallback.js` | 官方源优先、显式镜像回退可作构建参考 | `R` | 仅限构建期；不得形成产品自动更新或未登记外连 |
| `desktop/scripts/verify-gpu-runtime.ps1` | 隔离数据根、唯一 pipe、CUDA 检查和进程树清理可参考；绑定 MiniCPM 与聊天 API | `R` | 选型后重写为 O/V 候选验收，不保留聊天调用 |
| `desktop/scripts/verify-installer.ps1` | 临时目录静默安装、无开发工具 self-test、启动/清理流程可修改复用 | `M` | 补断网、单实例、程序/模型独立更新与卸载选择、失败不破坏、配置/诊断保留规则 |

`desktop/package.json` 的 Electron/NSIS 编排、许可证文件随包分发和固定 artifact 名称可作为 `M` 级入口；当前 `assets/icon.png`、V1 单包 `extraResources` 与卸载默认行为不能直接沿用。依赖本身的许可和锁文件完整性仍由任务 19/20 判定。

## 5. 测试资产矩阵

| 测试资产 | 数量/覆盖 | 等级与处理 |
|---|---:|---|
| `desktop/test/barrage-overlay.test.js` | 1 文件、2 用例 | `M`：保留 Electron 调用序列的 unit 模式；它只验证 mock 调用，不是点击穿透实测 |
| `release-metadata.test.js`、`resource-fallback.test.js` | 2 文件、6 用例 | `M/R`：保留法务资源存在性、官方源优先与显式回退模式；按 V2 包拓扑重写 |
| `backend-manager.test.js`、`game-profiles.test.js`、`pet-display.test.js` | 3 文件、24 用例 | `R`：只提取进程清理、配置持久化、显示器精确匹配等意图；删除聊天/记忆/桌宠/内置提示词内容 |
| `event-router.test.js`、`image-generation-settings.test.js`、`pet-hit-test.test.js`、`pet-state.test.js`、`pet-window.test.js`、`privacy-mode.test.js`、`scene-policy.test.js` | 7 文件、20 用例 | `N/A`：主体与桌宠、课程、聊天、生图或 V1 场景策略绑定，不迁移 |
| `desktop/test/visual-smoke.js` | 1 文件、15 个 capture 场景 | `M`：可保留隐藏窗口、IPC stub、截图和布局断言模式；仅 barrage 场景接近 V2，必须移除 8 个 launcher/6 个 pet 场景中的排除域并更换许可不明图片 |
| `generate-assets.js`、`generate-memory-reference-assets.js`、`memory-character-reference.html`、`memory-style-reference.html` | 4 文件 | `N/A`：图标/桌宠/记忆生图生成与参考夹具禁用 |
| `native/tests/native_tests.cpp` | 1 文件 | `R`：属于任务 17 的 native 边界，不在本任务重复批准 |
| `tests/unit/test_model_download.py`、`test_packaged_launcher.py`、`test_protocol.py` | 3 文件 | `R`：下载/打包/协议测试模式可参考；须经模型选型、协议冻结和任务 19/20 后重写 |
| `tests/unit/` 其余 9 文件 | 9 文件 | `N/A/R`：课程、记忆、生图、聊天、V1 prompt/策略内容禁用；少量 API/原子文件意图只能从 V2 契约重建 |

### 点击穿透与单实例样例

- **透明点击穿透**：已有代码入口为 `main.js` 的透明 barrage BrowserWindow、`barrage-overlay.js` 的 `setIgnoreMouseEvents(true)` 及 `barrage.css` 的 `pointer-events:none`；已有单测仅断言 mock 调用。没有 1080P/2K/4K × 100/125/150/175/200%、横/竖布局、左上/中心/右下真实下层点击或目标显示器失效证据。迁移后必须执行 AC-B06～B08、任务 12/14 的 Windows 真机矩阵。
- **单实例**：`main.js` 已调用 `app.requestSingleInstanceLock()`，第二实例退出并通过 `second-instance` 唤起主窗；V1 没有对应 unit、Electron 集成或安装包测试。V2 必须新增配置/运行/暂停/故障恢复四种状态的双启动测试，断言第二进程、第二模型和第二运行会话新增数均为 0，并验证已有主窗被唤起。

## 6. 迁移门与真实缺口

1. 先删除或替换全部禁用媒体与排除域，再冻结 V2 配置、IPC、窗口和包拓扑；不得从 V1 UI 反推产品范围。
2. `M` 级只允许从固定提交按具体路径/符号提取并补 V2 测试；`R`、`W`、`N/A` 禁止复制实现。任何 Electron、Node、Python、CUDA、vendor 或模型依赖须通过任务 19/20。
3. Overlay helper、installer smoke 和 visual smoke 只是候选模式，不是 Windows、离线安装、单实例或分发许可通过证据。
4. 当前真实缺口为：8 个位图均无逐项来源/许可；单实例零测试；点击穿透只有 mock；visual smoke 依赖许可不明图片且没有像素/透明度/DPI 真机断言；V1 配置与安装脚本不满足配置锁、包分离、回退、两个独立卸载选项和禁止自动更新的完整约束。
