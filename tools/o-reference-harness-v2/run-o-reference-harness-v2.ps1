#requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet("official-runtime-reference", "v2-contract")]
    [string]$Profile = "official-runtime-reference",
    [ValidateSet("official-1hz", "legacy-3s-replay")]
    [string]$Cadence = "official-1hz",
    [string]$ModelRoot,
    [string]$ResultRoot = (Join-Path $PSScriptRoot "results"),
    [int]$Generation = 1,
    [int]$ResultTimeoutMs = 60000,
    [int]$ProcessTimeoutSeconds = 1800,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Expected,
        [Parameter(Mandatory = $true)][string]$Label
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected) { throw "$Label SHA-256 mismatch: $actual" }
}

function Resolve-PackagePath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    return [IO.Path]::GetFullPath((Join-Path $PSScriptRoot $RelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)))
}

function Get-GpuSnapshot {
    $line = & nvidia-smi.exe --query-gpu=index,name,uuid,driver_version,memory.total,memory.used,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if (-not $line) { throw "nvidia-smi did not return a GPU snapshot" }
    $parts = @($line -split "," | ForEach-Object { $_.Trim() })
    if ($parts.Count -lt 7) { throw "unexpected nvidia-smi GPU output" }
    return [pscustomobject]@{
        index = [int]$parts[0]
        name = $parts[1]
        uuid = $parts[2]
        driver_version = $parts[3]
        memory_total_mib = [int]$parts[4]
        memory_used_mib = [int]$parts[5]
        utilization_gpu_percent = [int]$parts[6]
    }
}

function Get-ComputeApplications {
    $rows = @(& nvidia-smi.exe --query-compute-apps=pid,process_name,used_gpu_memory --format=csv,noheader,nounits 2>$null)
    $applications = @()
    foreach ($row in $rows) {
        if (-not $row) { continue }
        $parts = @($row -split "," | ForEach-Object { $_.Trim() })
        if ($parts.Count -ge 3 -and $parts[0] -match "^\d+$") {
            $applications += [pscustomobject]@{
                pid = [int]$parts[0]
                process_name = $parts[1]
                used_memory_mib = if ($parts[2] -match "^\d+$") { [int]$parts[2] } else { $null }
            }
        }
    }
    return @($applications)
}

function Add-ResourceSample {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][int]$ProcessId)
    $processState = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
    $sample = [ordered]@{
        schema_version = 1
        utc_timestamp = (Get-Date).ToUniversalTime().ToString("o")
        process_id = $ProcessId
        gpu = Get-GpuSnapshot
        process_working_set_mib = if ($processState) { [Math]::Round($processState.WorkingSet64 / 1MB, 3) } else { $null }
        process_private_mib = if ($processState) { [Math]::Round($processState.PrivateMemorySize64 / 1MB, 3) } else { $null }
        handle_count = if ($processState) { $processState.HandleCount } else { $null }
    }
    [IO.File]::AppendAllText($Path, ($sample | ConvertTo-Json -Compress -Depth 8) + [Environment]::NewLine, [Text.UTF8Encoding]::new($false))
}

$configPath = Join-Path $PSScriptRoot "runner-config.json"
$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profileConfig = $config.profiles.PSObject.Properties[$Profile].Value
$cadenceConfig = $config.cadences.PSObject.Properties[$Cadence].Value
if ($null -eq $profileConfig -or $null -eq $cadenceConfig) { throw "unknown profile or cadence" }
$profilePath = Resolve-PackagePath -RelativePath ([string]$profileConfig.package_path)
$manifestPath = Resolve-PackagePath -RelativePath ([string]$cadenceConfig.package_path)
Assert-FileHash -Path $profilePath -Expected ([string]$profileConfig.sha256) -Label "profile"
Assert-FileHash -Path $manifestPath -Expected ([string]$cadenceConfig.sha256) -Label "input manifest"

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifestRoot = Split-Path -Parent $manifestPath
foreach ($chunk in @($manifest.chunks)) {
    $audioPath = [IO.Path]::GetFullPath((Join-Path $manifestRoot ([string]$chunk.audio)))
    $imagePath = [IO.Path]::GetFullPath((Join-Path $manifestRoot ([string]$chunk.image)))
    Assert-FileHash -Path $audioPath -Expected ([string]$chunk.audio_sha256) -Label "fixture audio"
    Assert-FileHash -Path $imagePath -Expected ([string]$chunk.image_sha256) -Label "fixture image"
}

$buildManifestPath = Join-Path $PSScriptRoot "portable-build-manifest.json"
$harnessCommit = if (Test-Path -LiteralPath $buildManifestPath -PathType Leaf) {
    [string](Get-Content -LiteralPath $buildManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json).source_commit
} else {
    "UNPACKAGED-DYNAMIC-ONLY"
}
$runId = "$(Get-Date -AsUTC -Format 'yyyyMMdd-HHmmss')-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$runRoot = Join-Path ([IO.Path]::GetFullPath($ResultRoot)) "$Profile\$Cadence\$runId"
$runParent = Split-Path -Parent $runRoot
New-Item -ItemType Directory -Path $runParent -Force | Out-Null
if (Test-Path -LiteralPath $runRoot) { throw "isolated result directory already exists: $runRoot" }

$executable = Join-Path $PSScriptRoot "bin\o-reference-harness-v2.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Harness executable is missing" }

if ($DryRun) {
    & $executable dry-run --profile $profilePath --manifest $manifestPath `
        --output-dir $runRoot --harness-commit $harnessCommit
    if ($LASTEXITCODE -ne 0) { throw "Harness dry-run failed: $LASTEXITCODE" }
} else {
    if (-not $IsWindows -or -not [Environment]::Is64BitOperatingSystem) {
        throw "Dynamic Reference Harness requires Windows x64"
    }
    if ([string]::IsNullOrWhiteSpace($ModelRoot)) { throw "-ModelRoot is required for dynamic execution" }
    $ModelRoot = [IO.Path]::GetFullPath($ModelRoot)
    foreach ($modelFile in @($config.model_files)) {
        $modelPath = Join-Path $ModelRoot ([string]$modelFile.path).Replace("/", "\")
        if ((Get-Item -LiteralPath $modelPath).Length -ne [int64]$modelFile.size) {
            throw "locked model size mismatch: $modelPath"
        }
        Assert-FileHash -Path $modelPath -Expected ([string]$modelFile.sha256) -Label "locked model"
    }
    Get-Command nvidia-smi.exe -ErrorAction Stop | Out-Null
    $gpuBefore = Get-GpuSnapshot
    $arguments = @(
        "run", "--profile", $profilePath, "--manifest", $manifestPath,
        "--output-dir", $runRoot, "--harness-commit", $harnessCommit,
        "--model-root", $ModelRoot, "--generation", [string]$Generation,
        "--result-timeout-ms", [string]$ResultTimeoutMs
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $executable
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in $arguments) { $startInfo.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    if (-not $process.Start()) { throw "failed to start Reference Harness" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)
    $resourcePath = Join-Path $runRoot "resource-samples.jsonl"
    while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath (Join-Path $runRoot "run-metadata.json") -PathType Leaf) {
            Add-ResourceSample -Path $resourcePath -ProcessId $process.Id
        }
        Start-Sleep -Seconds 1
        $process.Refresh()
    }
    $runnerOutcome = "completed"
    if (-not $process.HasExited) {
        $process.Kill($true)
        $process.WaitForExit()
        $runnerOutcome = "runner_timeout_process_tree_terminated"
    }
    if (Test-Path -LiteralPath $runRoot -PathType Container) {
        Add-ResourceSample -Path $resourcePath -ProcessId $process.Id
    }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $stdoutTask.Result | Set-Content -LiteralPath (Join-Path $runRoot "runner-stdout.log") -Encoding UTF8
    $stderrTask.Result | Set-Content -LiteralPath (Join-Path $runRoot "runner-stderr.log") -Encoding UTF8
    $cleanupDeadline = (Get-Date).AddSeconds(90)
    do {
        $computeApplications = @(Get-ComputeApplications)
        $gpuPidRemaining = @($computeApplications | Where-Object pid -eq $process.Id).Count -gt 0
        $processRemaining = $null -ne (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
        if (-not $gpuPidRemaining -and -not $processRemaining) { break }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $cleanupDeadline)
    $gpuAfter = Get-GpuSnapshot
    [ordered]@{
        schema_version = 1
        platform = [Environment]::OSVersion.VersionString
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        profile = $Profile
        cadence = $Cadence
        gpu_before = $gpuBefore
        gpu_after = $gpuAfter
        vram_delta_mib = $gpuAfter.memory_used_mib - $gpuBefore.memory_used_mib
        process_id = $process.Id
        process_exit_code = $process.ExitCode
        runner_outcome = $runnerOutcome
        process_remaining = $processRemaining
        process_gpu_allocation_remaining = $gpuPidRemaining
        cleanup = if (-not $processRemaining -and -not $gpuPidRemaining) { "passed" } else { "failed" }
        dynamic_runtime_status = "DYNAMIC-ONLY result produced on Windows/NVIDIA"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot "environment.json") -Encoding UTF8
    if ($runnerOutcome -ne "completed" -or $process.ExitCode -ne 0) {
        throw "Reference Harness failed: $runnerOutcome / exit $($process.ExitCode)"
    }
}

$hashLines = @(Get-ChildItem -LiteralPath $runRoot -File | Where-Object Name -ne "sha256sums.txt" | Sort-Object Name | ForEach-Object {
    "$(Get-Sha256 -Path $_.FullName)  $($_.Name)"
})
$hashLines | Set-Content -LiteralPath (Join-Path $runRoot "sha256sums.txt") -Encoding UTF8
Write-Host "Reference Harness result: $runRoot"
