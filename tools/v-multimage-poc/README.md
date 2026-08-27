# AIJARVISV2-26/27 V 测试包

本目录是独立 Local V 测试包，覆盖任务 26 多图单次结构化输出 PoC 和任务 27 共享权重 1～3 路并发基准。它直接启动任务 25 锁定的官方 `llama-server b10369`，不依赖或导入 O Runtime、Harness、Session、Worker，也不实现第二套 runtime。模型文件与运行时二进制不进入仓库。

## 固定 profile 与边界

`profiles.json` 固定两个独立 profile：V-C01（Qwen3-VL-4B-Instruct Q4_K_M + Q8 mmproj）和 V-C02（MiniCPM-V-4.6 Q4_K_M + F16 mmproj）。每次 CLI 只能选择一个 profile；运行锁保证同一输出根目录不能同时驻留两个候选。任务 27 的每个 sample group 只启动一个 `llama-server`、一个 PID、一个 `--model` 和一个 `--mmproj`，通过 `--parallel 1/2/3` 共享同一份权重；禁止 router、多进程、备用服务或模型副本。

同一确定性 CC0 合成 fixture 覆盖平静、普通、高光 × 1/2/3 图，共 9 组；每张图为 896×512 `contain-no-stretch` 对照画布。两个候选使用同一 prompt/schema/评分，每个任务只有一个 HTTP 请求，零格式修复和零补调用。合成 fixture 不代替尚缺的英雄联盟许可录像、双人金标或质量阈值。

任务 27 当前只开放 `standard` 输出档。低/高/自定义档的精确参数尚未冻结，因此测试包不会猜测参数或生成伪对照数据。

## 制品检查与任务 26

准备 fixture 与 profile plan 不需要权重：

```text
python run_v_poc.py prepare --profile V-C01 --output evidence
python run_v_poc.py prepare --profile V-C02 --output evidence
```

Windows/NVIDIA 发布包由 GitHub Actions 按任务 25 锁定的官方 `llama-b10369-bin-win-cuda-12.4-x64.zip`（SHA-256 `5eca96bb...642642`）和 `cudart` 包（SHA-256 `8c79a9b2...ae1d6`）组装，并把 `llama-server.exe`、CUDA DLL、便携 Python 和脚本直接放入 ZIP。网吧保持联网即可运行；不需要 Visual Studio、CUDA Toolkit、Git 或现场下载。普通 `check/run/benchmark` 只检查包内 runtime 路径、文件名和非零字节数，以及模型的锁定文件名与字节数，不重复计算大型制品 SHA-256。

```powershell
.\run-v-poc.ps1 `
  -Mode Poc `
  -Profile V-C01 `
  -Python C:\AIJarvisV2\python.exe `
  -Server C:\AIJarvisV2\runtime\llama-server.exe `
  -ModelsDir D:\AIJarvisModels\V-C01 `
  -OutputDir D:\AIJarvisEvidence\task26
```

仅在首次准入、制品来源/版本/字节数变化或最终测试包组装时，显式增加一次 `-FullShaPurpose initial-admission`、`changed-artifact` 或 `final-package`。该动作写入 `artifact-admission.json`；普通重复开发和推理不得增加此参数，也不得重新联网锁定。

## 任务 27 正常矩阵

每个候选在真实 Windows 11/NVIDIA `8GB` 与 `12GB+` 两类硬件上分别执行 slots 1/2/3 × image count 1/2/3，共 9 个正常 sample group。每组默认预热 1 次、正式样本 20 次。每个 `run-id` 是不可追加的证据单元，已有非空目录会被拒绝。

```powershell
$BaseRunId = "20260827-vc01-win11-rtx4070"
foreach ($Slots in 1..3) {
  foreach ($Images in 1..3) {
    .\run-v-poc.ps1 `
      -Mode Benchmark `
      -Profile V-C01 `
      -Python C:\AIJarvisV2\python.exe `
      -Server C:\AIJarvisV2\runtime\llama-server.exe `
      -ModelsDir D:\AIJarvisModels\V-C01 `
      -OutputDir D:\AIJarvisEvidence\task27 `
      -Slots $Slots `
      -ImageCount $Images `
      -Samples 20 `
      -Warmup 1 `
      -RunId "$BaseRunId-s$Slots-i$Images" `
      -AppVersion "task27-benchmark-v1" `
      -HardwareProfileId "win11-rtx4070-8gb-machine-a" `
      -PowerPolicy "high-performance-ac"
  }
}
```

V-C01 完全退出且进程枚举无 `llama-server.exe` 后，才可使用新的 `run-id` 和对应模型目录执行 V-C02。两个候选、两类硬件的结果不得混合。16GB GPU 只覆盖 `12GB+` 组，绝不能作为 8GB 证据；10GB 等非目标容量记录为 `OTHER`，不能形成完整组结论。

## 故障组

在 slots=3 下使用交错的高光、平静和普通任务分别运行取消、服务退出和全局复位。建议固定 image count 3，每种故障使用独立 `run-id`：

```powershell
foreach ($Fault in "cancel", "server-exit", "global-reset") {
  .\run-v-poc.ps1 `
    -Mode Benchmark `
    -Profile V-C01 `
    -Python C:\AIJarvisV2\python.exe `
    -Server C:\AIJarvisV2\runtime\llama-server.exe `
    -ModelsDir D:\AIJarvisModels\V-C01 `
    -OutputDir D:\AIJarvisEvidence\task27 `
    -Slots 3 `
    -ImageCount 3 `
    -Samples 20 `
    -Warmup 1 `
    -Fault $Fault `
    -RunId "20260827-vc01-s3-i3-$Fault" `
    -AppVersion "task27-benchmark-v1" `
    -HardwareProfileId "win11-rtx4070-8gb-machine-a" `
    -PowerPolicy "high-performance-ac"
}
```

取消只中断目标连接并释放 slot；服务退出和全局复位终止唯一服务、提升 generation，并将旧代次在途任务标为 expired。测试包不会启动备用服务恢复。

## 证据与结论

每组输出位于 `<OutputDir>/<profile>/benchmark/<run-id>/`：

- `summary.json`：拓扑、model load/slot 日志观察、延迟/吞吐、结果分母、完成顺序、环境、GPU 汇总、清理和结论。
- `samples.csv`：使用正式性能样本模板字段的逐任务记录。
- `events.jsonl`：submit/start/complete、slot、generation 和丢弃原因。
- `cases/*.json`：正式样本的原始响应、校验和评分；无响应故障样本仍保留任务与故障上下文。
- `warmup/*.json`：预热原始响应，明确标记 `excluded_from_metrics=true`。
- `gpu-samples.jsonl`：`load_ready`、`steady`、`fault` 和 `post_cleanup` 阶段的 NVIDIA 原始采样。
- `llama-server.log`：单次 model load 与配置 slot 数的直接观察入口。
- `blocked.json`：制品、加载或推理失败时的零调用/失败分类证据。

正常组只有在 Windows/NVIDIA、目标显存组、环境身份齐全、GPU 阶段完整、单次 model load、slot 数一致且全部正式样本成功时，才写 `DATA_COMPLETE_PENDING_CALIBRATION`；其余写 `DATA_INCOMPLETE`。故障组另用 `fault_result=PASS_FROZEN/FAIL_FROZEN` 判断冻结故障语义，不能用正常组结论代替。Mac、无 `nvidia-smi`、缺少 8GB 或 12GB+ 任一硬件组、缺少任一候选或任一 1/2/3 组合时，都不是任务 27 或产品 PASS。

## 停止条件

结构、业务一致性、制品和 runtime 冲突沿用任务 26 的失败分类。任何失败只记录并停止；禁止 OCR、分类/摘要模型、格式修复补调用、在线核心服务或第二模型副本。任务 26 的历史 Mac 证据位于 `evidence/`，仅证明两个 profile 通过共同 v3 多图结构化功能硬门，不证明 Windows/NVIDIA、并发边界或最终产品模型。
