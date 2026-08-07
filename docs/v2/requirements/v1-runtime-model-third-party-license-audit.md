# V1 运行时、模型权重与第三方许可审计

> Dashi：AIJARVISV2-19
> 审计日期：2026-08-07
> 只读基线：`LYiHub/pub-local-jarvis@dd8fbf97a3e0f96239a0a465398654be68e88e15`
> 前置清单：[V1/原作者只读源码快照与资产清单](v1-source-snapshot-and-asset-inventory.md)

## 1. 四层结论

本审计只读取固定 Git 对象、固定上游许可页和依赖清单，不构建、下载或分发模型。`通过`只表示对应许可来源足以支持所列用途，不代表 V1 安装包已满足全部义务；无法证明来源、版本或随包材料的项目统一判为`阻塞`。

| 层 | 固定边界与原始来源 | 商业使用 | 当前 V1/离线再分发 | 结论 |
|---|---|---|---|---|
| V1 自有代码 | 固定提交根 [`LICENSE`](https://github.com/LYiHub/pub-local-jarvis/blob/dd8fbf97a3e0f96239a0a465398654be68e88e15/LICENSE)，SHA-256 `50ccf7ff...a88c54` | `通过`：MIT 允许使用、修改、销售和再许可 | `通过`：复制或实质部分须保留版权与许可文本 | 不覆盖 vendor、模型、依赖或媒体权利 |
| `llama.cpp-omni` vendor | `VENDOR.json` 固定 `tc-mb/llama.cpp-omni@b9d15b83...7486`；[上游 `LICENSE`](https://github.com/tc-mb/llama.cpp-omni/blob/b9d15b83ee353b2eaeee4d9318c98a35a1347486/LICENSE) 与本地副本一致 | `通过`：主代码为 MIT，所见嵌入组件均为宽松许可 | `阻塞`：现有安装编排未证明随包保留完整 notices，且实际复制的参考音频权利不明 | 只批准许可评估，不批准当前 provider/安装包选型 |
| MiniCPM 权重 | `openbmb/MiniCPM-o-4_5-gguf@502eec5b...9a63` 的[固定模型卡](https://huggingface.co/openbmb/MiniCPM-o-4_5-gguf/blob/502eec5b03eaee9d0d2ce17a176e3490103c9a63/README.md)明确权重和代码为 Apache-2.0 | `通过`：允许商业使用、修改和分发 | `阻塞`：V1 只下载三份权重，未保存 Apache-2.0 文本、模型卡/NOTICE 快照或分发归属 | 许可证已确认；离线模型包须先补齐随包材料 |
| 桌面与打包依赖 | `desktop/package-lock.json`、`pyproject.toml`、Electron/PyInstaller/CUDA 构建入口 | `通过`仅限已核实直接项；没有发现直接许可证禁止商业使用 | `阻塞`：npm 来源/完整性、Python 锁、CUDA 版本和最终安装包 notices 均未收口 | 不得把 V1 安装包作为 V2 可分发基线 |

## 2. V1 代码与 vendor

### 2.1 V1 自有代码

根 MIT 声明的版权行为 `Copyright (c) 2026 AI Jarvis contributors`。源代码或二进制可商业使用且没有源代码披露义务；复制、修改或分发时必须保留该版权声明、许可条件和免责声明。`THIRD_PARTY_NOTICES.md` 只是信息摘要，不能把根 MIT 扩展到第三方或模型。

### 2.2 固定 vendor 与补丁

vendor 子树对象为 `48ab029a0794b140f802fd39cf556f6b07f5ab83`，3,139 个文件；`VENDOR.json` 还固定上游归档 SHA-256 `f8505a91...5710c`。项目补丁 `0001-text-input-runtime.patch` 固定到同一上游 revision，SHA-256 `cc8b1c4...783e`；再分发修改版须同时保留 V1 与上游 MIT 声明并标明补丁来源。

当前 Windows CPU/CUDA provider 的静态构建边界可确认以下许可：

| 组件/固定路径 | 原始许可来源 | 义务 |
|---|---|---|
| llama.cpp-omni / llama / ggml | `vendor/LICENSE`、`LICENSE.llama.cpp-omni`，MIT | 保留版权和 MIT 文本；没有源码披露义务 |
| cpp-httplib | `vendor/vendor/cpp-httplib/LICENSE`，MIT | 保留版权和 MIT 文本 |
| nlohmann/json | `vendor/vendor/nlohmann/json.hpp` 的 SPDX `MIT`；另有 `licenses/LICENSE-jsonhpp` | 保留版权和 MIT 文本 |
| miniaudio | `vendor/vendor/miniaudio/miniaudio.h` 文件尾，Unlicense 或 MIT-0 双选 | 选择 MIT-0 时可无署名，但应保留原始头以便审计 |
| stb_image | `vendor/vendor/stb/stb_image.h` 文件尾，MIT 或 Public Domain 双选 | 选择 MIT 时保留版权和许可文本 |
| 保留但未证明进入该目标的上游项 | `licenses/LICENSE-{curl,httplib,jsonhpp,linenoise}`、`gguf-py/LICENSE` | 这些文件存在不等于启用清单完整；须由后续 SBOM 按最终二进制收口 |

`prepare-release.ps1` 关闭 OpenSSL、LLGuidance、OpenMP 和 NCCL，仅构建 CPU/CUDA provider，但 `omni_text_runtime` 实际仍把 TTS/token2wav 源编入 `omni`。更严重的是脚本把 `tools/omni/assets/default_ref_audio/default_ref_audio.wav`（192,590 字节，blob `4b4cbbb...5470db`）复制进运行时，native/launcher 还会传递它；固定树没有该录音的说话人、原始来源、授权范围或人格/声音权记录。代码 MIT 不能证明录音权利，因此当前 provider 与安装包选型必须阻塞，直至删除该依赖或取得可审计授权。

## 3. MiniCPM 模型权重

V1 的 `model_download.py` 固定仓库、revision、大小和 SHA-256，只允许取得以下三项；Git 树和安装包均不包含权重：

| 文件 | 字节 | SHA-256 | 固定许可来源 |
|---|---:|---|---|
| `MiniCPM-o-4_5-Q4_K_M.gguf` | 5,026,714,400 | `1237a97e...0932` | 固定 revision 模型卡的 Apache-2.0 声明 |
| `vision/MiniCPM-o-4_5-vision-F16.gguf` | 1,095,113,184 | `1453678c...f421` | 同上 |
| `audio/MiniCPM-o-4_5-audio-F16.gguf` | 660,167,904 | `d5b188ac...2ef7` | 同上 |

该固定模型卡的 metadata 为 `license: apache-2.0`，正文再次声明 MiniCPM-o/V 权重和代码采用 Apache-2.0，并标识这是 `openbmb/MiniCPM-o-4_5` 的量化产物。Apache-2.0 允许商业和离线再分发；分发方必须提供[Apache-2.0 文本](https://www.apache.org/licenses/LICENSE-2.0.txt)，保留适用的版权、专利、商标和署名 notice，修改文件须显著标记，若上游有 NOTICE 则须保留其适用内容；它不要求公开整个应用源码。

固定模型仓库根没有独立 `LICENSE` 或 `NOTICE` 文件，只有模型卡上的许可声明；模型卡还列出 SigLip2、Whisper-medium、CosyVoice2 和 Qwen3-8B 架构来源，但没有组件级权重 notice 清单。许可证足以支持候选评估，离线模型包仍须先固化 Apache 文本、模型卡来源/revision、三项哈希、量化/修改声明和“上游未提供独立 NOTICE”的审计记录；材料缺失时不得默认允许分发。

## 4. 桌面、Python 与 CUDA 依赖

### 4.1 Electron/npm

| 直接项 | 固定版本 | 原始来源 | 许可与要求 |
|---|---:|---|---|
| Electron | `41.10.1` | [npm 固定版本](https://www.npmjs.com/package/electron/v/41.10.1)、仓库 `electron/electron` | MIT；发行物还必须保留 Electron、Chromium、Node 的组件许可/notice |
| electron-builder | `26.15.3` | [npm 固定版本](https://www.npmjs.com/package/electron-builder/v/26.15.3) | MIT；构建工具许可不替代其下载的 Electron/NSIS 产物许可 |
| Lucide | `0.468.0` | [npm 固定版本](https://www.npmjs.com/package/lucide/v/0.468.0) | ISC；保留版权、许可和免责声明 |
| ws | `8.21.0` | [上游固定 `LICENSE`](https://github.com/websockets/ws/blob/8.21.0/LICENSE) | MIT；保留版权和许可文本 |

锁文件共有 313 个非根 package 节点，313/313 有 `license` 字段，分布为 MIT 241、ISC 37、BSD-3-Clause 9、BlueOak-1.0.0 8、Apache-2.0 6、BSD-2-Clause 6，以及 0BSD/Python-2.0/WTFPL/多许可证各 1；但只有 8/313 同时记录 `resolved`/`integrity`，305/313 没有来源 URL 和完整性。许可证字段不是原始许可文本，也不能证明最终 Electron 二进制携带了 Chromium notices。

### 4.2 Python/PyInstaller

`pyproject.toml` 只用范围声明 7 个运行依赖和 PyInstaller 可选组，没有 lock、哈希或构建快照；`prepare-release.ps1` 在线执行 `pip install`。现有 notice 只概述直接许可证，未登记实际 Python、CPython/PSF、transitive wheels、版本、来源或许可文件。PyInstaller 的 GPL-2.0-or-later bootloader exception通常允许封装非 GPL 应用，但仍须按实际固定版本保留 PyInstaller/bootloader 文本并逐项履行被捆绑 Python 包的许可；当前证据不足，安装包分发为`阻塞`。

### 4.3 CUDA 与最终安装包

[CUDA Toolkit 13.3 EULA](https://docs.nvidia.com/cuda/eula/index.html) 的 Attachment A 明确允许随应用分发 Windows `cudart`、`cublas`、`cublasLt` 对应 DLL。V1 脚本复制的文件类型在该清单内，但脚本会从任意最新 CUDA 13.1+ 目录取文件，没有固定 toolkit 版本、源包、EULA 版本或 Redist 清单；运行时 manifest 只记录最终文件名/大小/哈希，不能回溯授权来源。

`desktop/package.json` 只显式复制 V1 根 `LICENSE` 和汇总 notice。没有已提交安装产物可证明 Electron/Chromium、vendor、Python/PyInstaller、CUDA 和模型许可材料最终都可见；也没有逐文件安装包许可清单。现有安装包不得作为许可通过证据。

## 5. 许可门与真实缺口

| ID | 阻断项 | 解除条件 | 阻断范围 |
|---|---|---|---|
| LIC-01 | vendor 参考音频缺作者、来源、录音/声音权许可且被运行时实际使用 | 删除 provider 对该音频的依赖，或取得可再分发且覆盖商业/离线使用的书面来源记录 | 当前 `llama.cpp-omni` provider 选型与安装包 |
| LIC-02 | vendor notices 只在源码树，未证明进入二进制发行物 | 对最终目标生成组件清单，随包保留适用 `LICENSE`/`AUTHORS`/嵌入组件 notice | vendor 二进制分发 |
| LIC-03 | 模型仓库无独立 LICENSE/NOTICE，V1 不保存模型卡许可材料 | 模型包固化 Apache-2.0 文本、模型卡 revision、哈希、归属和修改/NOTICE 记录 | 离线模型包；不阻止纯许可候选评估 |
| LIC-04 | npm 锁 305/313 节点缺来源与完整性，且没有最终 Electron 组件 notices 证据 | 固定来源/哈希并对实际安装产物生成许可清单 | 桌面安装包 |
| LIC-05 | Python/PyInstaller 无锁、无 wheel 哈希、无 transitive/CPython 许可清单 | 固定全部版本和制品并生成随包许可清单 | 后端运行时与安装包 |
| LIC-06 | CUDA toolkit/EULA/Redist 来源未固定 | 固定 toolkit 和官方来源，核对 Attachment A，记录 DLL 哈希并随发布保存适用条款 | CUDA 运行时分发 |

因此：V1 自有 MIT 代码可进入后续文件级复用评审；MiniCPM 三项固定权重的 Apache-2.0 许可已确认，但离线模型包材料未完成；当前 vendor provider 和整套桌面安装包均不得进入 V2 白名单。任何版本、模型仓库、量化文件、构建后端或依赖图变化都必须重新审计，未知项不得按“通常允许”放行。

## 6. 验收覆盖

| 检查项 | 覆盖 |
|---|---:|
| 代码 / vendor / 模型 / 桌面依赖四层独立结论 | 4/4 |
| 商业使用与离线再分发独立判定 | 8/8 |
| V1 根许可、vendor revision/patch、模型 revision/三项哈希 | 1/1、2/2、3/3 |
| 桌面直接依赖原始许可来源 | 4/4 |
| npm lock 许可字段与来源/完整性统计 | 313/313、8/313 |
| 署名、许可副本、NOTICE、修改标记、源码披露、安装包义务 | 6/6 |
| 阻断项及解除条件 | 6/6 |

本覆盖是静态工程许可审计，不是法律意见，也不代表构建、模型能力、Windows 真机、性能、稳定性或最终发布验收通过。本任务未运行 V1 源码或测试，未下载或分发模型。
