# AIJARVISV2-23 Windows 便携 PoC 包

GitHub Actions Artifact `AIJARVISV2-23-windows-x64-cuda-portable` 只为任务 23 的 O-C01 P-02～P-04 动态验证提供一次性入口，不是产品运行时、安装包或任务 24 基准实现。当前非 Windows 环境不得执行本包，也不得把 Artifact 构建成功、模板或空结果记为动态通过。

## 现场放置

在仓库外准备两个目录，避免把模型和授权素材提交到 Git：

1. `MODEL_ROOT`：按模板路径放置三项固定 GGUF，并把本目录的 `model-provenance.template.json` 复制为 `MODEL_PROVENANCE.json`；同目录放置 `LICENSE.Apache-2.0.txt` 和固定 revision 的 `MODEL_CARD.md`。
2. `O_IN_07_ROOT`：放置授权、脱敏的 `authorization.md`、`gold.json` 和 `chunks/`；把 `o-in-07-manifest.template.json` 复制为 `manifest.json`，补齐全部 SHA-256。模板中的 `REPLACE_` 不得保留。

模板固定 11 个连续 3 秒槽位（`0001`～`0011`），每个槽位同时提供 WAV 与 JPG，覆盖 0～30 秒边界。素材至少包含一次可辨认的自主触发机会，并在其后继续保留输入，以便从动态时间轴判定生成前、中、后输入。

## 机器前置

- Windows 11 x64（build 22000+）、正常 NVIDIA 驱动及 PowerShell 5.1 或 7；无需安装 VS Build Tools、CMake、Git、Python、Node 或 CUDA Toolkit。
- NVIDIA 显卡至少 12GB 标称显存；脚本记录 `nvidia-smi` 的实际型号和容量，不设上限。低于 16GB 的结果只作补充证据，不能替代任务 23 的正式 16GB 最低环境。
- 运行前关闭其他 GPU compute 进程并断开物理网络；便携目录、模型和输入目录位于本地磁盘且可写。

## 单一入口

解压 Artifact 后，在其根目录执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\run-aijarvisv2-23.ps1 `
  -ModelRoot D:\AIJarvis-PoC\models\MiniCPM-o-4_5-gguf `
  -InputRoot D:\AIJarvis-PoC\o-in-07
```

现场准备完成后只需执行上述一个主命令。入口验证 Artifact/模型/输入哈希后直接运行预编译执行器，再按原有 P-02/P-04 套件及 P-03 正常结束/重建/12 秒硬超时强杀执行；用例间无需人工干预。模型或 O-IN-07 缺失时只列出固定放置槽位，不检查或提示编译工具。

结果写入便携目录的 `results/<run-id>/`：`preflight.json` 和 `build-manifest.json` 固定身份/构建，`evidence.jsonl` 保存完整原始响应和调用时间轴，三个既有格式 CSV 保存性能/资源/故障，`summary.json` 分开记录证据完整性、GPU 证据范围与可行性，`sha256sums.txt` 固定全部结果文件。原始授权音画不会复制进结果目录；执行完成后人工只需保存整个 `<run-id>` 目录。
