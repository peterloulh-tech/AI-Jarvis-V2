# Task93 Official-First O Reference

当前入口只调用锁定的官方 `llama-server` omni HTTP endpoints，不实现 Runtime、Session manager、streaming boundary 或 Mock runtime。`aijarvisv2-o-official-adapter` 负责官方 HTTP/SSE、Comni 同形的 system prompt 注入与三批契约，PowerShell runner 负责固定 O-IN-07、证据和 `break → stop → restart → omni_init` full reinit。

Windows/NVIDIA 动态运行：

```powershell
.\run-o-official-reference.ps1 -ModelRoot D:\Models\MiniCPM-o-4_5-gguf -InputRoot D:\Fixtures\O-IN-07-1HZ
```

模型和 O-IN-07 媒体保持外置；Artifact 只带固定 manifest/gold/authorization。默认核验三个模型 SHA-256，`-SkipModelHashVerification` 只供诊断。Mac/no-GPU 仅运行 C++ unit/static/dry-run，真实 Runtime、Session、SSE、VRAM 和 cleanup 统一为 `DYNAMIC_ONLY`。

`tools/o-reference-harness-v2` 当前为 `LEGACY / RETIRED-PENDING-NEW-ROUTE-VALIDATION`，不被本入口、runner 或 workflow 调用；首个 Official Windows/NVIDIA PASS 后再一次性删除或归档。
