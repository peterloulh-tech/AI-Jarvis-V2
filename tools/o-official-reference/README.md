# Task93 Official-First O Reference

当前入口只调用 `tc-mb/llama.cpp-omni master@09f5c3f1…` 的官方 `llama-omni-server` HTTP/SSE 能力，不实现 Runtime、Session manager、streaming boundary 或 Mock runtime。该版本与 `MiniCPM-o-Demo main@d0a00209…` 当前 C++ backend 默认的 `master/origin/master` 路线一致。`aijarvisv2-o-official-adapter` 只负责 HTTP/SSE、system prompt 注入与三批契约；当前 server 的 HTTP `omni_init` 不代做 system prefill，因此 adapter 随后只补一次官方 `/v1/stream/prefill` `cnt=0`，O-IN-07 仍从 `cnt=1` 开始。PowerShell runner 只保留固定 O-IN-07、证据与有界进程清理，并直接复用官方 `omni_init` 的旧 context 释放/重建作为 clean context / full reinit。

Windows/NVIDIA 动态运行：

```powershell
.\run-o-official-reference.ps1 -ModelRoot D:\Models\MiniCPM-o-4_5-gguf -InputRoot D:\Fixtures\O-IN-07-1HZ
```

模型和 O-IN-07 媒体保持外置；Artifact 只带固定 manifest/gold/authorization。活动配置为 `use_tts=false`，当前官方 server 从主 GGUF 同目录解析并实际要求 LLM、`audio/MiniCPM-o-4_5-audio-F16.gguf`、`vision/MiniCPM-o-4_5-vision-F16.gguf`，因此现有三个外置文件直接兼容；官方完整 TTS 布局中的 TTS/projector/token2wav 文件不属于本 profile 必需项。默认核验三个模型 SHA-256，`-SkipModelHashVerification` 只供诊断。Mac/no-GPU 仅运行 C++ unit/static/dry-run，真实 Runtime、Session、SSE、VRAM 和 cleanup 统一为 `DYNAMIC_ONLY`。

`tools/o-reference-harness-v2` 当前为 `LEGACY / RETIRED-PENDING-NEW-ROUTE-VALIDATION`，不被本入口、runner 或 workflow 调用；首个 Official Windows/NVIDIA PASS 后再一次性删除或归档。
