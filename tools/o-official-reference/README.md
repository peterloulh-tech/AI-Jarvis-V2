# Task93 Official-First O Reference

当前入口只调用 `tc-mb/llama.cpp-omni master@09f5c3f1…` 的官方 `llama-omni-server /backend`，不实现 Runtime、Session manager、streaming boundary 或 Mock runtime。该版本与 `MiniCPM-o-Demo main@d0a00209…` 当前 C++ backend 默认的 `master/origin/master` 路线一致。`aijarvisv2-o-official-adapter` 按 Comni `RemoteBackendSession` 的 `session.init → input.append → pull → HTTP session close` 原语工作，只补 O-IN-07 的 PCM16 WAV/JPEG 到协议 payload、官方 duplex suffix token 包装、三批验证和证据收集。预热 session 通过官方 close 触发 `omni_prepare_for_reuse`，正式 session 直接复用已加载模型与干净 context；不再保留 HTTP/SSE、显式 `cnt=0` 或自管 full-reinit。

Windows/NVIDIA 动态运行：

```powershell
.\run-o-official-reference.ps1 -ModelRoot D:\Models\MiniCPM-o-4_5-gguf -InputRoot D:\Fixtures\O-IN-07-1HZ
```

模型和 O-IN-07 媒体保持外置；Artifact 只带固定 manifest/gold/authorization。正式需求首版明确禁用 TTS；当前官方 `omni_init(use_tts=false)` 只加载 LLM、`audio/MiniCPM-o-4_5-audio-F16.gguf` 与 `vision/MiniCPM-o-4_5-vision-F16.gguf`，因此现有三个外置文件直接兼容。Comni entrypoint 为完整视频通话默认检查的 TTS/projector/token2wav 不属于此 no-TTS profile 必需项。默认核验三个模型 SHA-256，`-SkipModelHashVerification` 只供诊断。Mac/no-GPU 仅运行 C++ unit/static/dry-run；真实 Runtime、Session、LISTEN/SPEAK、VRAM 和 process cleanup 统一为 `DYNAMIC_ONLY`。

`tools/o-reference-harness-v2` 当前为 `LEGACY / RETIRED-PENDING-NEW-ROUTE-VALIDATION`，不被本入口、runner 或 workflow 调用；首个 Official Windows/NVIDIA PASS 后再一次性删除或归档。
