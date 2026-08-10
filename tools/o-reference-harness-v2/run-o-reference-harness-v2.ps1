#requires -Version 5.1

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
    [string]$MockResultSource,
    [ValidateSet("listen_transition", "generation_change", "session_end_drain", "input_exhausted", "failure", "timeout")]
    [string]$MockBoundary = "input_exhausted",
    [string]$MockCleanupError,
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

function ConvertTo-NativeArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes += 1
        } elseif ($character -eq '"') {
            [void]$builder.Append(('\' * ($slashes * 2 + 1)))
            [void]$builder.Append('"')
            $slashes = 0
        } else {
            if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)) }
            [void]$builder.Append($character)
            $slashes = 0
        }
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function New-CapturedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $startInfo = New-Object Diagnostics.ProcessStartInfo
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.Arguments = (@($Arguments | ForEach-Object { ConvertTo-NativeArgument -Value $_ }) -join ' ')
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $startInfo
    return $process
}

function Stop-ProcessTree {
    param([Parameter(Mandatory = $true)][Diagnostics.Process]$Process)
    $wasRunning = $false
    $cleanupError = $null
    try {
        $Process.Refresh()
        if (-not $Process.HasExited) {
            $wasRunning = $true
            $runningOnWindows = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
                [Runtime.InteropServices.OSPlatform]::Windows)
            if ($runningOnWindows) {
                & taskkill.exe /PID $Process.Id /T /F 2>$null | Out-Null
            }
            $Process.Refresh()
            if (-not $Process.HasExited) { $Process.Kill() }
            if (-not $Process.WaitForExit(30000)) {
                throw "process tree did not exit within 30 seconds"
            }
        }
    } catch {
        $cleanupError = $_.Exception.Message
    }
    return [pscustomobject]@{
        process_was_running = $wasRunning
        error = $cleanupError
    }
}

function Write-Utf8Text {
    param([Parameter(Mandatory = $true)][string]$Path, [AllowEmptyString()][string]$Value)
    [IO.File]::WriteAllText($Path, $Value, (New-Object Text.UTF8Encoding($false)))
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
$runId = "$((Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss'))-$([guid]::NewGuid().ToString('N').Substring(0, 8))"
$runRoot = Join-Path ([IO.Path]::GetFullPath($ResultRoot)) "$Profile\$Cadence\$runId"
$runParent = Split-Path -Parent $runRoot
New-Item -ItemType Directory -Path $runParent -Force | Out-Null
if (Test-Path -LiteralPath $runRoot) { throw "isolated result directory already exists: $runRoot" }

$executable = Join-Path $PSScriptRoot "bin\o-reference-harness-v2.exe"
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) { throw "Harness executable is missing" }
$deferredError = $null

if ($DryRun -and -not [string]::IsNullOrWhiteSpace($MockResultSource)) {
    throw "-DryRun and -MockResultSource are mutually exclusive"
}

if ($DryRun) {
    & $executable dry-run --profile $profilePath --manifest $manifestPath `
        --output-dir $runRoot --harness-commit $harnessCommit
    if ($LASTEXITCODE -ne 0) { throw "Harness dry-run failed: $LASTEXITCODE" }
} elseif (-not [string]::IsNullOrWhiteSpace($MockResultSource)) {
    $mockSource = [IO.Path]::GetFullPath($MockResultSource)
    if (-not (Test-Path -LiteralPath $mockSource -PathType Leaf)) {
        throw "Mock result source is missing: $mockSource"
    }
    $arguments = @(
        "replay-results", "--profile", $profilePath, "--input", $mockSource,
        "--boundary", $MockBoundary, "--output-dir", $runRoot,
        "--harness-commit", $harnessCommit
    )
    $process = New-CapturedProcess -FilePath $executable -Arguments $arguments
    if (-not $process.Start()) { throw "failed to start Reference Harness mock replay" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $mockTimeoutMs = [int][Math]::Min(
        [int64][int]::MaxValue, ([int64][Math]::Max(0, $ProcessTimeoutSeconds) * 1000))
    $mockCompleted = $process.WaitForExit($mockTimeoutMs)
    $primaryError = if ($mockCompleted) { $null } else {
        "Mock result replay timed out after $ProcessTimeoutSeconds seconds"
    }
    $cleanupActions = @(
        Stop-ProcessTree -Process $process
        Stop-ProcessTree -Process $process
    )
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    $stdoutText = if ($process.HasExited) { $stdoutTask.Result } else { "stdout unavailable: process did not exit" }
    $stderrText = if ($process.HasExited) { $stderrTask.Result } else { "stderr unavailable: process did not exit" }
    Write-Utf8Text -Path (Join-Path $runRoot "runner-stdout.log") -Value $stdoutText
    Write-Utf8Text -Path (Join-Path $runRoot "runner-stderr.log") -Value $stderrText
    $evidencePath = Join-Path $runRoot "evidence.json"
    if ($null -eq $primaryError -and (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
        $mockEvidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $mockEvidence.primary_error) { $primaryError = [string]$mockEvidence.primary_error }
    }
    $mockExitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
    if ($null -ne $mockExitCode -and $mockExitCode -ne 0 -and [string]::IsNullOrWhiteSpace($primaryError)) {
        $primaryError = "Mock result replay failed with exit $mockExitCode"
    }
    $summaryPresent = Test-Path -LiteralPath (Join-Path $runRoot "summary.json") -PathType Leaf
    if ($mockExitCode -eq 0 -and -not $summaryPresent) {
        $primaryError = "Mock result replay did not produce summary.json"
    }
    $processRemaining = $null -ne (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
    $cleanupMessages = @($cleanupActions | Where-Object { $null -ne $_.error } | ForEach-Object { $_.error })
    if (-not [string]::IsNullOrWhiteSpace($MockCleanupError)) { $cleanupMessages += $MockCleanupError }
    $cleanupError = if ($cleanupMessages.Count -gt 0) { $cleanupMessages -join "; " } else { $null }
    [ordered]@{
        schema_version = 1
        platform = [Environment]::OSVersion.VersionString
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        profile = $Profile
        cadence = $Cadence
        execution_mode = "mock_result_source"
        mock_result_source = $mockSource
        process_id = $process.Id
        process_exit_code = $mockExitCode
        summary_present = $summaryPresent
        primary_error = $primaryError
        cleanup_error = $cleanupError
        cleanup_attempts = 2
        cleanup_actions = $cleanupActions
        cleanup_idempotent = (-not $processRemaining -and -not $cleanupActions[1].process_was_running)
        cleanup = if (-not $processRemaining -and $null -eq $cleanupError) { "passed" } else { "failed" }
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot "environment.json") -Encoding UTF8
    if ($null -ne $primaryError) {
        $deferredError = if ($null -ne $cleanupError) {
            "$primaryError; cleanup error: $cleanupError"
        } else { $primaryError }
    } elseif ($null -ne $cleanupError) {
        $deferredError = "cleanup error: $cleanupError"
    }
} else {
    $runningOnWindows = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(
        [Runtime.InteropServices.OSPlatform]::Windows)
    if (-not $runningOnWindows -or -not [Environment]::Is64BitOperatingSystem) {
        throw "Dynamic Reference Harness requires Windows x64"
    }
    if ([string]::IsNullOrWhiteSpace($ModelRoot)) { throw "-ModelRoot is required for dynamic execution" }
    $ModelRoot = [IO.Path]::GetFullPath($ModelRoot)
    $lockedModelEvidence = @()
    foreach ($modelFile in @($config.model_files)) {
        $modelPath = Join-Path $ModelRoot ([string]$modelFile.path).Replace("/", "\")
        $modelItem = Get-Item -LiteralPath $modelPath
        if ($modelItem.Length -ne [int64]$modelFile.size) {
            throw "locked model size mismatch: $modelPath"
        }
        $modelSha256 = Get-Sha256 -Path $modelPath
        if ($modelSha256 -ne [string]$modelFile.sha256) { throw "locked model SHA-256 mismatch: $modelSha256" }
        $lockedModelEvidence += [ordered]@{
            path = [string]$modelFile.path
            size = $modelItem.Length
            sha256 = $modelSha256
        }
    }
    Get-Command nvidia-smi.exe -ErrorAction Stop | Out-Null
    $gpuBefore = Get-GpuSnapshot
    $executableSha256 = Get-Sha256 -Path $executable
    $buildManifestSha256 = if (Test-Path -LiteralPath $buildManifestPath -PathType Leaf) {
        Get-Sha256 -Path $buildManifestPath
    } else { $null }
    $arguments = @(
        "run", "--profile", $profilePath, "--manifest", $manifestPath,
        "--output-dir", $runRoot, "--harness-commit", $harnessCommit,
        "--model-root", $ModelRoot, "--generation", [string]$Generation,
        "--result-timeout-ms", [string]$ResultTimeoutMs
    )
    $process = New-CapturedProcess -FilePath $executable -Arguments $arguments
    if (-not $process.Start()) { throw "failed to start Reference Harness" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $resourcePath = Join-Path $runRoot "resource-samples.jsonl"
    $runnerOutcome = "completed"
    $primaryError = $null
    $cleanupMessages = @()
    try {
        $deadline = (Get-Date).AddSeconds($ProcessTimeoutSeconds)
        while (-not $process.HasExited -and (Get-Date) -lt $deadline) {
            if (Test-Path -LiteralPath (Join-Path $runRoot "run-metadata.json") -PathType Leaf) {
                Add-ResourceSample -Path $resourcePath -ProcessId $process.Id
            }
            Start-Sleep -Seconds 1
            $process.Refresh()
        }
        if (-not $process.HasExited) {
            $runnerOutcome = "runner_timeout_process_tree_terminated"
            $primaryError = "Reference Harness timed out after $ProcessTimeoutSeconds seconds"
        }
    } catch {
        $runnerOutcome = "runner_exception"
        $primaryError = "Reference Harness runner failed: $($_.Exception.Message)"
    } finally {
        $cleanupActions = @(
            Stop-ProcessTree -Process $process
            Stop-ProcessTree -Process $process
        )
        $cleanupMessages += @($cleanupActions | Where-Object { $null -ne $_.error } | ForEach-Object { $_.error })
    }
    $processExitCode = if ($process.HasExited) { $process.ExitCode } else { $null }
    if ($null -eq $primaryError -and $null -ne $processExitCode -and $processExitCode -ne 0) {
        $primaryError = "Reference Harness failed: $runnerOutcome / exit $processExitCode"
    }
    New-Item -ItemType Directory -Path $runRoot -Force | Out-Null
    try {
        $stdoutText = if ($process.HasExited) { $stdoutTask.Result } else { "stdout unavailable: process did not exit" }
        $stderrText = if ($process.HasExited) { $stderrTask.Result } else { "stderr unavailable: process did not exit" }
        Write-Utf8Text -Path (Join-Path $runRoot "runner-stdout.log") -Value $stdoutText
        Write-Utf8Text -Path (Join-Path $runRoot "runner-stderr.log") -Value $stderrText
    } catch {
        $cleanupMessages += "runner log capture failed: $($_.Exception.Message)"
    }
    $gpuPidRemaining = $true
    $processRemaining = $true
    $gpuAfter = $null
    try {
        if (Test-Path -LiteralPath $runRoot -PathType Container) {
            Add-ResourceSample -Path $resourcePath -ProcessId $process.Id
        }
        $cleanupDeadline = (Get-Date).AddSeconds(90)
        do {
            $computeApplications = @(Get-ComputeApplications)
            $gpuPidRemaining = @($computeApplications | Where-Object pid -eq $process.Id).Count -gt 0
            $processRemaining = $null -ne (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)
            if (-not $gpuPidRemaining -and -not $processRemaining) { break }
            Start-Sleep -Seconds 1
        } while ((Get-Date) -lt $cleanupDeadline)
        $gpuAfter = Get-GpuSnapshot
    } catch {
        $cleanupMessages += $_.Exception.Message
    }
    $cleanupError = if ($cleanupMessages.Count -gt 0) { $cleanupMessages -join "; " } else { $null }
    [ordered]@{
        schema_version = 1
        platform = [Environment]::OSVersion.VersionString
        architecture = [Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()
        profile = $Profile
        cadence = $Cadence
        gpu_before = $gpuBefore
        gpu_after = $gpuAfter
        vram_delta_mib = if ($null -ne $gpuAfter) { $gpuAfter.memory_used_mib - $gpuBefore.memory_used_mib } else { $null }
        process_id = $process.Id
        process_exit_code = $processExitCode
        runner_outcome = $runnerOutcome
        process_remaining = $processRemaining
        process_gpu_allocation_remaining = $gpuPidRemaining
        primary_error = $primaryError
        cleanup_error = $cleanupError
        cleanup_attempts = 2
        cleanup_actions = $cleanupActions
        cleanup_idempotent = (-not $processRemaining -and -not $cleanupActions[1].process_was_running)
        cleanup = if (-not $processRemaining -and -not $gpuPidRemaining -and $null -eq $cleanupError) { "passed" } else { "failed" }
        harness_executable_sha256 = $executableSha256
        portable_build_manifest_sha256 = $buildManifestSha256
        locked_model_files = $lockedModelEvidence
        dynamic_runtime_status = "DYNAMIC-ONLY result produced on Windows/NVIDIA"
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runRoot "environment.json") -Encoding UTF8
    if ($null -ne $primaryError) {
        $deferredError = if ($null -ne $cleanupError) {
            "$primaryError; cleanup error: $cleanupError"
        } else { $primaryError }
    } elseif ($null -ne $cleanupError) {
        $deferredError = "cleanup error: $cleanupError"
    }
}

$hashLines = @(Get-ChildItem -LiteralPath $runRoot -File | Where-Object Name -ne "sha256sums.txt" | Sort-Object Name | ForEach-Object {
    "$(Get-Sha256 -Path $_.FullName)  $($_.Name)"
})
$hashLines | Set-Content -LiteralPath (Join-Path $runRoot "sha256sums.txt") -Encoding UTF8
Write-Host "Reference Harness result: $runRoot"
if ($null -ne $deferredError) { throw $deferredError }
