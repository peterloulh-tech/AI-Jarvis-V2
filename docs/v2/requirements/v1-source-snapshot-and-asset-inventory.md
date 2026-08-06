# V1/原作者只读源码快照与资产清单

> Dashi：AIJARVISV2-16
> 审计日期：2026-08-07
> 审计对象：`https://github.com/LYiHub/pub-local-jarvis`
> 固定提交：`dd8fbf97a3e0f96239a0a465398654be68e88e15`

## 1. 结论与审计边界

本次只读审计直接读取本地 Git 对象库中的固定提交，没有切换、执行、构建或修改原作者源码，也没有下载、复制或分发模型及其他未评估资产。`upstream/HEAD -> upstream/main` 与 `upstream/main` 均包含固定提交；提交主题为 `update README`，作者/提交者为 `Gbining <2205658756@qq.com>`，时间为 `2026-07-24T18:36:59+08:00`。

快照共 3,276 个普通文件、96,862,940 字节；全部模式为 `100644`，没有子模块、符号链接或可执行位。根树为 `ef03278a04ea1b70bb5fe925139a559d7f647bfe`。`git archive --format=tar <commit>` 产生 99,635,200 字节，SHA-256 为 `750ef140da1c2b18d57a7eb143ef0c71f9172ba858f6338757d2e85419a543fc`。

仓库根 `LICENSE` 为 MIT；这只确认仓库代码的声明，不能替代模型权重、vendor 内依赖和图片/GIF 等资产的逐项许可核验。任务 16 只固化事实，不作复用等级或分发许可结论，后者分别由任务 17～19评审。

## 2. 快照清单

计数与字节来自 `git ls-tree -r -l <commit>`；对象 ID 可直接定位不可变子树。

| 边界 | 文件数 | 字节 | Git 对象 | 内容 |
|---|---:|---:|---|---|
| 根文件 | 9 | 77,788 | 根树见上 | `.gitignore`、`CMakeLists.txt`、`LICENSE`、`PROJECT_OVERVIEW.md`、`README.md`、`THIRD_PARTY_NOTICES.md`、`pyproject.toml`、`start-real.cmd`、`start-real.ps1` |
| `config/` | 1 | 1,306 | `6e7b4e9cf948f7f801f66e8b6b9ccc9e46ddcc7a` | 默认 TOML 配置 |
| `desktop/` | 55 | 2,858,173 | `7f0773689b123cd1b9e415163a8d5d10fcd19b27` | Electron UI、资产、构建脚本与测试 |
| `docs/` | 1 | 7,699,998 | `9aea06e100c178ec9b7efed54c88d684970ce43f` | 产品截图 |
| `native/` | 21 | 157,894 | `662027fad573ea32bb06f6844cfe664d38b0e889` | C++20 worker、Windows 采集、IPC 与测试 |
| `src/` | 29 | 2,250,072 | `63fa05a7d6387dc54e544dc0df39cd00db44f6c3` | Python/FastAPI 后端与两张参考图 |
| `tests/` | 12 | 112,790 | `4acd177c3f2833584c84160302f19dc5bcf6a2c6` | Python 单元测试 |
| `third_party/` | 3,148 | 83,704,919 | `4187fb13eb97793f67c04176173b6bfe257d6255` | runtime 接入层与 vendor 快照 |

`third_party/runtime/` 的对象为 `4cf5a623694f355f89e839677f63d77cb4c23bab`。其中项目维护的接入层只有 9 个文件；`vendor/` 单独占 3,139 个文件、83,687,322 字节，对象为 `48ab029a0794b140f802fd39cf556f6b07f5ab83`。因此 vendor 不得混入原作者自有模块计数或后续逐模块复用结论。

## 3. 模块地图

| 模块 | 具体入口 | 职责边界 |
|---|---|---|
| Electron 主进程 | `desktop/src/main.js`、`backend-manager.js`、`event-router.js`、`preload.js` | 应用启动、后端进程、事件路由与渲染桥接 |
| 桌宠与 Overlay | `desktop/src/pet-*.js`、`barrage-overlay.js`、`desktop/src/ui/` | 桌宠窗口、命中测试、弹幕窗口与页面资源 |
| 桌面策略/配置 | `desktop/src/game-profiles.js`、`privacy-mode.js`、`scene-policy.js`、`image-generation-settings.js` | 游戏方案、隐私暂停、场景策略与可选生图配置 |
| 后端 API | `src/jarvis_backend/app.py`、`api/routes.py`、`api/schemas.py`、`api/ws.py` | FastAPI 启动、HTTP schema/路由与 WebSocket |
| 后端编排 | `src/jarvis_backend/orchestrator/`、`barrage/policy.py` | 事件、场景、生命周期、服务编排与弹幕策略 |
| V1 非 V2 核心域 | `src/jarvis_backend/courses/`、`memory/`、`prompts/` | 课程、长期记忆、生图与 V1 提示模板；是否适用留给任务 17/18 |
| Native 客户端 | `src/jarvis_backend/native/` | named pipe 客户端、协议与 native supervisor |
| Native 公共接口 | `native/include/jarvis/` | 音频、采集、协议、runtime、调度、Windows 与 worker 接口 |
| Native 实现 | `native/src/*.cpp`、`native/src/windows/` | 音频转换、CRC/指纹、调度、runtime adapter、DXGI、WASAPI、named pipe |
| Runtime 接入层 | `third_party/runtime/{CMakeLists.txt,INTEGRATION.md,VENDOR.json,include/,src/,patches/}` | 模型布局校验、固定上游描述和项目补丁；不等于 vendor 本体 |
| Vendor 本体 | `third_party/runtime/vendor/` | 固定的 `llama.cpp-omni` 上游源码快照，必须独立审计许可 |

## 4. 构建、脚本与依赖入口

| 入口 | 作用 | 本次状态 |
|---|---|---|
| `CMakeLists.txt`、`native/CMakeLists.txt` | C++ worker、Windows 库和 CTest 入口 | 仅静态读取 |
| `third_party/runtime/CMakeLists.txt` | runtime boundary 与可选上游 provider | 仅静态读取 |
| `pyproject.toml` | Python 3.12+、后端包、pytest 与打包依赖 | 仅静态读取 |
| `desktop/package.json`、`package-lock.json` | Electron 入口、npm scripts、NSIS 配置与锁文件 | 仅静态读取 |
| `desktop/scripts/build.js` | Python/C++/Electron 发布编排 | 仅静态读取 |
| `start-real.cmd`、`start-real.ps1` | 源码运行入口 | 未执行 |

非 vendor 脚本共 8 个：`start-real.cmd`、`start-real.ps1`，以及 `desktop/scripts/{build.js,install-dependencies.js,prepare-release.ps1,resource-fallback.js,verify-gpu-runtime.ps1,verify-installer.ps1}`。资产生成入口另位于 `desktop/test/generate-assets.js` 和 `generate-memory-reference-assets.js`，两者本次均未执行。

直接声明的桌面运行依赖为 `lucide`、`ws`，开发依赖为 `electron`、`electron-builder`。Python 运行依赖为 `fastapi`、`hf-xet`、`huggingface-hub`、`pydantic`、`pydantic-settings`、`tqdm`、`uvicorn`；可选组另含测试、Anthropic 与 PyInstaller。Native 侧链接 Windows SDK 库，并可接入下述固定 vendor。这里只登记来源入口，许可与 SBOM 结论留给任务 19/20。

## 5. 测试清单

| 测试根 | 文件数 | runner/入口 | 覆盖对象 |
|---|---:|---|---|
| `desktop/test/` | 18 | `node --test test/*.test.js`、`electron test/visual-smoke.js` | 13 个 `*.test.js`、1 个视觉 smoke、2 个生成器、2 个参考 HTML |
| `native/tests/` | 1 | CTest 的 `jarvis-native-tests` | 协议、音频、调度、runtime/worker 等 native 行为 |
| `tests/unit/` | 12 | `pytest` | API、课程、记忆、模型下载、打包、策略、提示与协议 |

桌面 13 个单测文件为 `backend-manager`、`barrage-overlay`、`event-router`、`game-profiles`、`image-generation-settings`、`pet-display`、`pet-hit-test`、`pet-state`、`pet-window`、`privacy-mode`、`release-metadata`、`resource-fallback`、`scene-policy` 对应的 `*.test.js`。Native 唯一入口为 `native/tests/native_tests.cpp`；Python 12 个文件均在 `tests/unit/test_*.py`。本任务未运行任何测试，因为验收要求是只读清单而非源码执行。

vendor 子树另有 162 个路径命中目录名 `test/tests/testing`，140 个路径命中 `script/scripts` 或脚本扩展名；这些只表示上游快照内容，不计入项目自有 31 个测试入口，也未执行。

## 6. 资产、二进制与模型边界

非 vendor 位图资产共 8 个：

| 路径 | 字节 | SHA-256 |
|---|---:|---|
| `desktop/assets/icon.png` | 16,902 | `8a1555c3ca757d66fd7757e053a455994bd77b45f7e657861868cbfbb7f3f476` |
| `desktop/assets/pet/closed-eyes.gif` | 576,771 | `a8406f40afade2ffdb1676a6aebfab3f90112c7937d64075ec74d502aa073081` |
| `desktop/assets/pet/course.gif` | 731,092 | `bc4f4fd72b46d1cbfa701556d5bdca4913cdbffb69004e5a19e5f4a1a96efab2` |
| `desktop/assets/pet/idle.gif` | 598,189 | `e8769e54bce5c00ea4d1391a48315fb22226703cd1056a68a61aa7ff203ff873` |
| `desktop/assets/pet/normal.gif` | 635,524 | `4741df21aba5057b9848868dbe29e1f42e72b1b14bb9fc0394a36239563d3154` |
| `docs/images/pet-chat.png` | 7,699,998 | `31edbc4b0b260f59a36822204ea0d9af34276e3a1f99c24ef8c5ef242727f569` |
| `src/jarvis_backend/assets/jarvis-character-reference.png` | 322,269 | `dcfa1630294674e371f942e2422b1f88adf7fcf4ee725eba5ca0311dd84aa3d3` |
| `src/jarvis_backend/assets/jarvis-style-reference.png` | 1,737,365 | `984ccf79d94d2efeb0244430ccc0e2be32e37d9787dca146c72c3e88483559ad` |

Git 树中没有 `.gguf`、`.safetensors`、`.onnx`、`.pt/.pth`、`.bin`、`.exe`、`.dll`、`.so/.dylib/.lib` 文件。README/代码只声明运行时另行取得 `MiniCPM-o-4_5-Q4_K_M.gguf`、视觉 F16 与音频 F16 权重；它们不属于本快照，也没有在本任务下载或核验。vendor 内含 133 个图片/音频/PDF 路径和 2 个归档路径，均由 vendor 根树统一约束，不得视为项目自有资产。

真实缺口：仓库没有为上述 8 个非 vendor 位图逐项记录作者、原始来源和独立许可；仓库 MIT 声明不能单独证明每个媒体文件可复用或再分发。任务 18/19 必须据此逐项收口，未确认前不得复制到 V2 产品资产。

## 7. 第三方边界与哈希记录

`third_party/runtime/VENDOR.json` 固定 `tc-mb/llama.cpp-omni` 提交 `b9d15b83ee353b2eaeee4d9318c98a35a1347486`，归档 SHA-256 为 `f8505a9179ff4b8e3ca648c4d462ad46edcc7698507ab3717bc3ee840f45710c`；项目补丁 `patches/0001-text-input-runtime.patch` SHA-256 为 `cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e`。接入层保留 `LICENSE.llama.cpp-omni` 和 `NOTICE.md`，vendor 内另有 `LICENSE`、`AUTHORS`、`licenses/` 及嵌套依赖许可。模型权重不属于该 MIT vendor 结论。

关键边界文件的快照 SHA-256：

| 路径 | SHA-256 |
|---|---|
| `LICENSE` | `50ccf7ff1d026e043cf8ede78232e36dfb78836d268c9bef353588bb94a88c54` |
| `THIRD_PARTY_NOTICES.md` | `6495256bd3c84604fdd4179b692bf4fdb2d1ebad4367c1d8ec8094eece25dcec` |
| `CMakeLists.txt` | `147799f0cb4f31151898c915bc115e6178e6ad20db31eb28e7fe4d42a84411c0` |
| `pyproject.toml` | `f0d4d7688451067d3fad76ebda5e40c895f7e1dc5f67ca56efb5d3bc560755a5` |
| `desktop/package.json` | `11367e1b94c68bfa708061bd7b4f58113a5eb46f4bb772644aa161088f76caf4` |
| `desktop/package-lock.json` | `c93d46f99c03c795ce15c8c87da43f450e6164966c9b136093e83f5bb69f6c60` |
| `desktop/scripts/build.js` | `2bc87a89c81805a58f0c4d32e84da1acf1fb574576a58fe0aa14dce2136ede87` |
| `native/CMakeLists.txt` | `772703e401aba1e22762bbef09877ca341762c291d01e0041de42e96337bc784` |
| `third_party/runtime/VENDOR.json` | `0d5253ddcea0bd45bb370b0cc13dfe888d7ec929311f02f48aa159400c2e363f` |
| `third_party/runtime/NOTICE.md` | `aae75ecc86011f13ed2167d9f1a7e1b60b0abb97192367fdf5ca1a3df2e67737` |
| `third_party/runtime/INTEGRATION.md` | `74007cc26e3f8ccf8685feaaf3902502d8c9061eb0981a688b980ec877f7b5f9` |
| `third_party/runtime/CMakeLists.txt` | `22ff2f71090a784b0fcfd805484632a9e2b5aa42db1ae8be805b582bf5d79e17` |
| `third_party/runtime/cmake/AcquireUpstream.cmake` | `46904d6831f424249a4659138bbc5f8454a2acf30e7a35a8736d0858d25a425a` |
| `third_party/runtime/patches/0001-text-input-runtime.patch` | `cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e` |

## 8. 只读复现与后续引用规则

以下命令足以复核本清单，不需要检出或执行源码：

```bash
git cat-file -e dd8fbf97a3e0f96239a0a465398654be68e88e15^{commit}
git show -s --format='%H%n%T%n%aI%n%s' dd8fbf97a3e0f96239a0a465398654be68e88e15
git ls-tree -r -l dd8fbf97a3e0f96239a0a465398654be68e88e15
git archive --format=tar dd8fbf97a3e0f96239a0a465398654be68e88e15 | shasum -a 256
```

后续任务引用 V1 时必须同时给出本固定提交和具体路径/模块；引用 vendor 时还必须给出 `third_party/runtime/vendor` 子树对象或 `VENDOR.json` 的上游提交。不得用“V1 已实现”替代文件级证据，不得将本清单解释为复用批准、模型许可批准或 V2 范围变更。
