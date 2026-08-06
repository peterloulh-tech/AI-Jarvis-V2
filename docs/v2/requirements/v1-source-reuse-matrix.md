# V1 源码复用分级矩阵与提取边界

> Dashi：AIJARVISV2-17
> 审计日期：2026-08-07
> 只读基线：`LYiHub/pub-local-jarvis@dd8fbf97a3e0f96239a0a465398654be68e88e15`
> 前置清单：[V1/原作者只读源码快照与资产清单](v1-source-snapshot-and-asset-inventory.md)

## 1. 结论与等级

本矩阵只判定技术复用边界，不复制代码，不改变 V2 冻结需求，也不替代 AIJARVISV2-19 的第三方、vendor 与模型许可结论。仓库根 MIT 声明支持评估原作者自有代码，但凡依赖 Windows SDK、Electron、PyInstaller、CUDA、`llama.cpp-omni` 或模型权重，仍须在实际提取和分发前完成对应许可与版本准入。

| 等级 | 含义 | 本次数量 |
|---|---|---:|
| `D` 直接复用候选 | 可按符号提取；保留声明并补齐 V2 测试后可进入实现评审 | 2 |
| `M` 修改复用 | 保留算法、接口或平台骨架；必须先解除 V1 耦合并满足 V2 约束 | 13 |
| `R` 仅参考 | 只保留设计经验或测试思路，不复制实现 | 4 |
| `W` 必须重写 | V1 产品职责或架构与 V2 范围冲突，按冻结需求重新实现 | 2 |

总体结论：低层 CRC、声道混合和定长音频窗口可直接复用；采集、runtime、Overlay、进程与打包只能修改复用；调度、生命周期和发送策略主要参考；V2 编排及产品层必须重写。

## 2. 逐模块矩阵

表内路径均指向上述固定提交；`自有 MIT` 仅表示根仓库声明，最终分发仍受第三方准入门约束。

| ID | 模块与固定路径 | 等级 | 理由与 V2 缺口 | 依赖/许可 | 提取前置条件 |
|---|---|---|---|---|---|
| SRC-01 | `ipc::crc32`：`native/src/protocol.cpp`、`native/include/jarvis/protocol.hpp` | `D` | 无状态、无平台依赖，标准 CRC-32 可独立验证；不携带 V1 消息语义 | C++20 标准库；自有 MIT | 只提取 CRC 符号；加入空载荷、标准向量、大载荷测试并保留来源提交 |
| SRC-02 | `audio::downmix_mono`、`ExactWindowAssembler`：`native/src/audio.cpp`、`native/include/jarvis/audio.hpp` | `D` | 纯 PCM 工具且已有基本测试；可作为 O 音频前处理构件，不决定采集策略 | C++20 标准库；自有 MIT | 按符号提取；补 NaN/极值、非整帧、reset 和长稳有界缓冲测试 |
| SRC-03 | 二进制帧编解码：`native/{include/jarvis/protocol.hpp,src/protocol.cpp}`、`src/jarvis_backend/native/protocol.py` | `M` | 32 字节小端头、CRC 和 16 MiB 上限可保留；V2 IPC schema 尚未冻结，C++ 端未拒绝非零 reserved 或未知消息类型，与 Python 校验不对称 | C++20/Python 标准库；自有 MIT | 先冻结 V2 消息、版本协商、错误响应和上限；生成跨语言金向量/畸形帧测试，禁止两端手工漂移 |
| SRC-04 | 线性重采样：`audio::resample_linear` in `native/src/audio.cpp` | `M` | 算法简单，但逐块 `llround` 且无跨块相位状态，不足以证明持续 O 音频无漂移/断点 | C++20 标准库；自有 MIT | 定义采样质量和时钟策略；改为有状态重采样并做 4 小时累计误差、边界连续性和性能验证 |
| SRC-05 | 指纹与变化检测：`native/{include/jarvis/fingerprint.hpp,src/fingerprint.cpp}` | `M` | 32x18 亮度采样和 FNV 骨架可留；阈值、只在判变后更新基线及 idle reminder 属 V1 策略，变化分数也不得等同高光 | C++20 标准库；自有 MIT | 拆出纯采样/指纹；变化评分、候选保护和校准参数由 V2 V 模式协议另定并用回放金标验证 |
| SRC-06 | 采集抽象：`native/include/jarvis/capture.hpp` | `M` | `VideoFrame`/`PcmBlock` 和 start/stop/next 形状可参考；缺少源身份、失效分类、颜色/时钟元数据及可选音频状态 | C++20 标准库；自有 MIT | 先冻结 V2 采集契约和错误模型；增加目标 ID、格式、时间基、代次和能力声明 |
| SRC-07 | DXGI/GDI：`native/src/windows/dxgi_capture.cpp` | `M` | DXGI duplication、staging copy、access-lost 重建可留；当前按“AI Jarvis Pet”所在显示器选源并自动改源，只支持整屏，违反用户显式选择单显示器/窗口和失效不自动切源 | Windows SDK（D3D11/DXGI/GDI）；自有 MIT | 注入已校验的显示器/窗口句柄；移除宠物窗口和隐式 fallback；实现显式失效、窗口采集、DPI/多屏与清理测试 |
| SRC-08 | WASAPI：`native/src/windows/wasapi_capture.cpp` | `M` | COM/loopback 拉流与 float/PCM16 转换可留；仅默认 render endpoint，不覆盖麦克风、目标进程音频、系统混合组合、设备选择和独立降级 | Windows SDK（WASAPI/MMDevice/AVRT）；自有 MIT | 按来源拆 adapter；显式设备/进程绑定和失效事件；验证时间戳、格式变化、静音、设备拔插与纯画面降级 |
| SRC-09 | Named pipe 与客户端：`native/src/windows/named_pipe_server.cpp`、`src/jarvis_backend/native/{client.py,protocol.py,supervisor.py}` | `M` | byte pipe、exact read/write、拒绝远端和 request ID 可留；server 直接耦合 `Worker`，默认 ACL、单连接、错误帧、代次/超时/背压和断线恢复未形成 V2 契约，`restart_limit` 未生效 | Windows named pipe、Python stdlib；自有 MIT | transport 与业务 handler 分离；限制当前用户 ACL；冻结握手/代次/取消/错误语义并做跨进程故障测试 |
| SRC-10 | 后端进程管理：`desktop/src/backend-manager.js` | `M` | 打包入口、随机 pipe、健康等待、取消启动和 Windows 进程树终止可留；混入课程/记忆/聊天 API，缺少所有权认证、遗留进程清理和冻结重启预算 | Node.js、Electron、`ws`；自有 MIT，依赖许可待任务 19/20 | 提取 launcher/supervisor 子集；绑定实例令牌与版本；实现启动取消、崩溃、卡死、退出、旧 PID 和无孤儿进程验收 |
| SRC-11 | Runtime 公共边界与模型布局：`native/include/jarvis/runtime.hpp`、`third_party/runtime/{include/jarvis/runtime/model_layout.hpp,src/model_layout.cpp}` | `M` | 不泄漏上游头文件的接口和 GGUF 布局校验有价值；接口绑定 MiniCPM-o/O-V1 duplex，模型/运行时尚未选型，文件名与“ready”不足以证明身份或兼容 | 自有接入层 MIT；模型与 vendor 许可待任务 19 | 先完成模型/运行时选型；用哈希、版本、能力和显存声明替代仅 magic/name 校验；按 O/V 服务拓扑重塑接口 |
| SRC-12 | 真实 runtime adapter：`native/src/omni_runtime.cpp`、`third_party/runtime/{CMakeLists.txt,VENDOR.json,patches/0001-text-input-runtime.patch}` | `M` | 上游隔离、RAII 清理和 text-only 接入可留；simplex/duplex 每帧把原始画面/音频写入临时 BMP/WAV，违反默认原始音画不落盘，取消只在推理边界检查，且产品并发语义不等于 V2 O/V | `llama.cpp-omni@b9d15b8`、模型权重、CUDA；许可与可分发性待任务 19 | 许可和选型双门；改为内存输入、可中断超时、显式单权重/会话拓扑；完成 8/12/16GB 真机、清理和断网验证 |
| SRC-13 | `LatestOnlyScheduler`：`native/{include/jarvis/scheduler.hpp,src/scheduler.cpp}` | `R` | 单活动项+单 pending、优先级覆盖和低优先级旧结果抑制可作有界调度参考；不能表达 O 单待生成槽规则，也不能表达 V 1～3 槽、最新槽/候选槽、摘要时序与共享权重 | C++20 线程库；自有 MIT | 不复制类；从 FR-05/06、AC-O01～O09、AC-V01～V09 重新建模后，只复用其取消/停止测试思路 |
| SRC-14 | Native Worker：`native/{include/jarvis/worker.hpp,src/worker.cpp}` | `R` | 展示了线程收口、最新帧和 generation 思路；但混合采集、V1 场景/课程/硬编码弹幕、固定节奏、fallback 文案和 runtime duplex，职责与 V2 O/V 分工冲突 | C++20、nlohmann JSON、Windows SDK、runtime vendor；许可待任务 19 | 不复制 Worker；按采集、O、V、后处理、生命周期边界重建；仅把停止 join、旧结果屏蔽和 fake runtime 用例转成 V2 测试需求 |
| SRC-15 | 事件与生命周期：`src/jarvis_backend/orchestrator/{events.py,lifecycle.py,scene.py}` | `R` | 有界 fan-out 和显式转移值得参考；状态机没有配置锁、paused、运行代次、自动暂停/停止区别，订阅溢出静默丢最旧也未按事件等级定义 | Python stdlib；自有 MIT | 从 FR-17、AC-A03～A08、AC-R01～R08 重写状态/清理表；冻结哪些事件可丢、哪些必须持久证据 |
| SRC-16 | 发送与弹幕策略：`src/jarvis_backend/barrage/policy.py`、`orchestrator/service.py` 的 barrage 路径 | `R` | 有界容器、过期和取消 task 可参考；当前按最低优先级淘汰而非最旧，未实现普通并发池/独立高光流/发送窗口，并用 `SequenceMatcher` 做语义相似去重，直接冲突 FR-15/AC-C08 | Python stdlib；自有 MIT | 不复制实现；按 FR-11～15、AC-C02～C09 重建批次/池/队列/时效/高光状态机，只保留完全相同文本保护 |
| SRC-17 | Overlay 窗口操作：`desktop/src/barrage-overlay.js` | `M` | topmost、全工作区、`setIgnoreMouseEvents(true)` 和 inactive show 可留；只有 14 行呈现 helper，无横/竖区域、四方向、速度分布、DPI/多屏、目标失效与自动暂停 | Electron；自有 MIT，依赖许可待任务 19/20 | 任务 18 先隔离 UI/资源；补显示器绑定、15 个显示组合、点击穿透、布局、异常暂停和真机证据 |
| SRC-18 | 构建与安装：`CMakeLists.txt`、`native/CMakeLists.txt`、`pyproject.toml`、`desktop/{package.json,scripts/build.js,scripts/prepare-release.ps1,scripts/verify-installer.ps1}` | `M` | CMake/PyInstaller/Electron-builder 编排、产物哈希和安装 smoke 可留；当前是 V1 单包拓扑，包含未审计图标/参考音频，未满足程序/模型/配置/诊断分离、兼容回退和两个独立卸载选项 | CMake、PowerShell、Python/PyInstaller、Electron-builder、CUDA/vendor；任务 18～20 联合门 | 先冻结 V2 包拓扑/SBOM；移除未批准资产；实现离线来源校验、版本兼容、失败不破坏、默认保留模型/配置和无残留进程验收 |
| SRC-19 | V1 产品编排与产品层：`src/jarvis_backend/orchestrator/service.py`、`api/`、`courses/`、`memory/`、`prompts/`，以及 `desktop/src/event-router.js` | `W` | 以桌宠、聊天、课程、长期记忆、生图和 V1 持续感知为中心；大量职责明确不属于 V2，且没有冻结的 O/V 共用事件信封、配置快照、发送池、高光时间线和诊断边界 | FastAPI/Pydantic/Node/Electron 等；依赖许可待任务 19/20 | 仅从冻结 FR/NFR/AC 建立 V2 产品域；禁止携带课程、桌宠、聊天、长期记忆、生图或 V1 prompt/fallback 文案 |
| SRC-20 | 测试：`native/tests/native_tests.cpp`、`tests/unit/test_protocol.py`、`desktop/test/{backend-manager,barrage-overlay,event-router,release-metadata,resource-fallback}.test.js` | `M` | fake runtime、协议破坏、调度停止、进程树和 Overlay mock 可转化；原生测试单文件耦合 V1 产品语义，缺跨语言金向量、真实 Windows 采集/pipe、原始音画落盘扫描、O/V 乱序/复位和安装回退证据 | CTest、pytest、Node test；测试依赖许可待任务 19/20 | 按模块拆测试；保留断言意图而非整套复制；用任务 9～14 的 P0/P1 用例补齐 Windows 真机、回放、资源和 FS/NET 证据 |
| SRC-21 | V1 非 V2 核心域与关联资产：`courses/`、`memory/`、`prompts/`、桌宠/聊天/生图入口 | `W` | 与冻结第一版范围不适用，不应形成 V2 依赖或迁移入口 | 自有代码 MIT；图片/GIF 来源许可未确认 | 不提取；UI/资源逐项结论留给任务 18，许可结论留给任务 19 |

## 3. 提取白名单与禁止边界

本任务只批准形成下列“候选白名单”，不执行复制：

1. `D` 级仅允许按符号从固定提交提取 `ipc::crc32`、`audio::downmix_mono` 和 `audio::ExactWindowAssembler`；不得整文件复制 `protocol.cpp` 或 `audio.cpp`。
2. `M` 级必须先有 V2 接口/状态契约和对应失败测试，再提取算法或平台调用骨架；不得保留 V1 默认源选择、prompt、产品文案、临时原始音画文件或隐式降级。
3. `R` 级禁止复制实现，只能把有界、取消、线程收口和 fault-injection 思路写入 V2 设计或测试。
4. `W` 级不得迁移。`third_party/runtime/vendor/`、模型权重和任何图片/GIF/音频资产均不在本任务白名单；vendor 仍以对象 `48ab029a0794b140f802fd39cf556f6b07f5ab83` 和 `VENDOR.json` 上游提交 `b9d15b83ee353b2eaeee4d9318c98a35a1347486` 单独约束。

每次实际提取必须记录固定提交、原路径、符号/行级范围、目标模块、修改摘要、测试、许可证/NOTICE、第三方版本和审批任务；禁止用“V1 已实现”作为复用证据。

## 4. 重写缺口与后续门

- **协议门**：V2 IPC 消息 schema、版本协商、代次、错误、超时和背压尚未冻结；当前 C++/Python 双实现不能直接成为协议基线。
- **采集门**：没有用户指定窗口采集、麦克风/进程音频/系统混合组合及来源独立失效；DXGI 还会随桌宠所在显示器隐式改源。
- **隐私门**：真实 runtime 把每帧画面和音频写入 OS 临时目录，未证明异常退出后的清理，必须阻止原样复用。
- **O/V 调度门**：V1 latest-only/duplex 不满足 O 单持续会话与单待生成槽，也不满足 V 共享权重、1～3 槽、最新槽/候选槽和前序摘要规则。
- **后处理门**：普通池、最旧淘汰、时效、高光独立流/降级和完全重复保护未实现；现有语义相似去重必须删除而不是迁移。
- **生命周期门**：配置锁、暂停/恢复代次、停止显存释放、锁屏/睡眠、Overlay 故障、异常退出清理与单实例仍需按 V2 重写。
- **显示与包门**：Overlay 只有呈现 helper；安装包尚未满足逻辑包分离、手动更新回退和卸载默认保留模型/配置。
- **证据门**：现有测试可提供少量单元测试种子，但没有 V2 跨语言、Windows 真机、回放、4/8 小时、安装/卸载、FS/NET 证据。
- **许可门**：模型权重、vendor 内依赖、Electron/Python/构建依赖和媒体资产结论仍待任务 18～20；`M`/`D` 等级不等于分发批准。

## 5. 验收覆盖

| 检查项 | 覆盖 |
|---|---:|
| Dashi 点名领域：IPC/CRC、音频、DXGI/WASAPI、pipe、进程、runtime、调度、生命周期、发送、测试 | 10/10 |
| 明确分级的模块/边界 | 21/21 |
| 理由、依赖/许可、提取前置条件、重写缺口字段 | 21/21 |
| `D/M/R/W` 四类最低结论 | 4/4 |
| `D/M/R/W` 数量 | 2/13/4/2，矩阵行数 21 |
| 固定提交与具体路径引用 | 21/21 |

本覆盖是静态源码审计，不代表构建、Windows 真机、模型、性能、稳定性或分发许可已经通过。本任务未执行 V1 源码或测试。
