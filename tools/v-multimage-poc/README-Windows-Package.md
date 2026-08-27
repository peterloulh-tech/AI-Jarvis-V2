# Task27 V Windows test package

This directory is the portable Windows 11/NVIDIA execution package for Task27. It contains the V benchmark tool, both locked model profiles, and deterministic CC0 test-fixture source. It is not a Jarvis product build and is independent of the Task93 O package.

## First use on a Windows test machine

Open PowerShell in this directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Prepare-V-Windows-Test.ps1
```

The preparation script downloads exactly the locked `llama.cpp b10369` CUDA 12.4 server and CUDART assets, validates their official SHA-256 values, and installs embedded Python locally. Keep the machine online only for this preparation. It creates `prepared-runtime.json` when successful.

## Run one machine's full matrix

Disconnect external networking, then run:

```powershell
.\Run-Task27-Matrix.ps1 `
  -HardwareProfileId "win11-<gpu>-8gb-machine-a" `
  -PowerPolicy high-performance-ac
```

For the 12GB+ machine, change only `HardwareProfileId`. Do not use a 16GB result as 8GB evidence. The script runs each profile separately: 9 normal groups (`slots 1/2/3` by `images 1/2/3`) plus three `slots=3/images=3` fault groups. Every group writes immutable evidence below `Evidence/`.

`Prepare-V-Windows-Test.ps1` is idempotent. `Run-Task27-Matrix.ps1 -PrepareRuntime` is available for diagnostics, but formal evidence must keep online preparation and disconnected execution as separate steps. Do not copy any executable, DLL, fixture, or model from the Task93 O package into this directory.
