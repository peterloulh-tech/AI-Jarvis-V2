# Task27 V Windows test package

This directory is the portable Windows 11/NVIDIA execution package for Task27. It contains the V benchmark tool, both locked model profiles, and deterministic CC0 test-fixture source. It is not a Jarvis product build and is independent of the Task93 O package.

## First use on a Windows test machine

Download the ZIP from the GitHub Actions artifact, extract it, and place the two locked V model pairs under `Models/V-C01` and `Models/V-C02`. The ZIP already contains the Windows server, CUDA DLLs, embedded Python, benchmark code, and fixture generator.

The test machine may remain online. No Visual Studio, CUDA Toolkit, Git, pip, or runtime download is required.

Open PowerShell in this directory and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Run-Task27-Matrix.ps1 `
  -HardwareProfileId "win11-<gpu>-8gb-machine-a" `
  -PowerPolicy high-performance-ac
```

The script runs one machine's full matrix while normal internet access remains enabled. Model inference itself uses the local `llama-server` over loopback; internet connectivity is not used as an inference service.

For the 12GB+ machine, change only `HardwareProfileId`. Do not use a 16GB result as 8GB evidence. The script runs each profile separately: 9 normal groups (`slots 1/2/3` by `images 1/2/3`) plus three `slots=3/images=3` fault groups. Every group writes immutable evidence below `Evidence/`.

Do not run `Prepare-V-Windows-Test.ps1` and do not use `-PrepareRuntime`; those are obsolete development helpers. Do not copy any executable, DLL, fixture, or model from the Task93 O package into this directory.
