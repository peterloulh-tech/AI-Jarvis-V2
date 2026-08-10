#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ModelRoot,
    [Parameter(Mandatory = $true)][string]$InputRoot,
    [string]$PackageRoot = $PSScriptRoot,
    [ValidateSet("short", "standard", "long")][string]$Profile = "standard",
    [string]$EvidenceRoot = "",
    [switch]$DryRun,
    [switch]$SkipModelHashVerification
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$ModelRoot = [IO.Path]::GetFullPath($ModelRoot)
$InputRoot = [IO.Path]::GetFullPath($InputRoot)
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
    $EvidenceRoot = Join-Path $PackageRoot ("evidence\O93-OFFICIAL-{0}" -f (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss"))
}
$EvidenceRoot = [IO.Path]::GetFullPath($EvidenceRoot)

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label is missing: $Path" }
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonUtf8 {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    $Value | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

$adapterPath = Join-Path $PackageRoot "bin\aijarvisv2-o-official-adapter.exe"
$serverPath = Join-Path $PackageRoot "bin\llama-omni-server.exe"
$configPath = Join-Path $PackageRoot "official-config.json"
$lockPath = Join-Path $PackageRoot "upstream-lock.json"
$manifestPath = Join-Path $InputRoot "manifest.json"
Assert-File -Path $adapterPath -Label "thin official adapter"
Assert-File -Path $configPath -Label "official config"
Assert-File -Path $lockPath -Label "upstream lock"
Assert-File -Path $manifestPath -Label "O-IN-07 manifest"

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$lock = Get-Content -LiteralPath $lockPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$profileConfig = $config.budget_profiles.PSObject.Properties[$Profile].Value
if ($null -eq $profileConfig) { throw "unknown profile: $Profile" }
if ($manifest.input_id -ne "O-IN-07" -or $manifest.slice_duration_ms -ne 1000 -or
    -not $manifest.deidentified -or -not $manifest.rights_confirmed -or @($manifest.chunks).Count -ne 33) {
    throw "O-IN-07 official-1hz manifest gate failed"
}

$dryRunJson = & $adapterPath dry-run --manifest $manifestPath
if ($LASTEXITCODE -ne 0) { throw "O-IN-07 official-1hz dry-run failed" }
$dryRunPlan = ($dryRunJson | Out-String) | ConvertFrom-Json
if ($dryRunPlan.cadence -ne "official-1hz" -or @($dryRunPlan.steps).Count -ne 33) {
    throw "O-IN-07 official-1hz dry-run output is invalid"
}
if ($DryRun) {
    $dryRunJson | Write-Output
    return
}

Assert-File -Path $serverPath -Label "official llama-omni-server"
$modelFiles = @($lock.model.files)
$modelEvidence = @()
foreach ($model in $modelFiles) {
    $modelPath = Join-Path $ModelRoot ([string]$model.path).Replace("/", "\")
    Assert-File -Path $modelPath -Label "external model"
    $actualHash = if ($SkipModelHashVerification) { "NOT_COMPUTED" } else { Get-LowerSha256 -Path $modelPath }
    if (-not $SkipModelHashVerification -and $actualHash -ne [string]$model.sha256) {
        throw "model SHA-256 mismatch: $($model.path)"
    }
    $modelEvidence += [ordered]@{
        path = [string]$model.path
        expected_sha256 = [string]$model.sha256
        actual_sha256 = $actualHash
    }
}

foreach ($step in @($dryRunPlan.steps)) {
    $chunk = @($manifest.chunks)[$step.cnt - 1]
    foreach ($kind in @("audio", "image")) {
        $assetPath = Join-Path $InputRoot ([string]$chunk.$kind).Replace("/", "\")
        Assert-File -Path $assetPath -Label "O-IN-07 $kind"
        $hashProperty = "${kind}_sha256"
        $expectedHash = [string]$chunk.$hashProperty
        if ((Get-LowerSha256 -Path $assetPath) -ne $expectedHash) {
            throw "O-IN-07 $kind SHA-256 mismatch at cnt=$($step.cnt)"
        }
    }
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $EvidenceRoot "raw-sse") -Force | Out-Null
$promptPath = Join-Path $EvidenceRoot "init-contract-prompt.txt"
$effectivePrompt = ([string]$config.contract_prompt_template).Replace(
    "{{MAX_CHINESE_CHARS}}", [string]$profileConfig.max_chinese_chars)
if ($effectivePrompt.Contains("{{MAX_CHINESE_CHARS}}")) { throw "contract prompt budget is unresolved" }
$effectivePrompt | Set-Content -LiteralPath $promptPath -Encoding utf8NoBOM
$serverOutput = Join-Path $EvidenceRoot "llama-omni-server.stdout.log"
$serverError = Join-Path $EvidenceRoot "llama-omni-server.stderr.log"
$runtimeOutput = Join-Path $EvidenceRoot "runtime-output"
New-Item -ItemType Directory -Path $runtimeOutput -Force | Out-Null
$baseUrl = "http://$($config.server.host):$($config.server.port)"
$serverProcess = $null
$processExits = @()
$hardKillUsed = $false
$fullReinit = "NOT_RUN"
$sessionBreak = "NOT_RUN"
$runError = $null
$rounds = @()
$finalText = ""
$parsedJson = $null

function Get-VramSample {
    param([Parameter(Mandatory = $true)][string]$Phase)
    $line = & nvidia-smi --query-gpu=index,name,memory.total,memory.used --format=csv,noheader,nounits 2>$null | Select-Object -First 1
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($line)) { throw "nvidia-smi failed for $Phase" }
    $parts = @($line -split "," | ForEach-Object { $_.Trim() })
    return [ordered]@{
        phase = $Phase
        timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
        gpu_index = [int]$parts[0]
        gpu_name = $parts[1]
        memory_total_mib = [int]$parts[2]
        memory_used_mib = [int]$parts[3]
    }
}

function Start-OfficialServer {
    Assert-File -Path $serverPath -Label "official llama-omni-server"
    $llmPath = Join-Path $ModelRoot "MiniCPM-o-4_5-Q4_K_M.gguf"
    $arguments = @(
        "--host", [string]$config.server.host,
        "--port", [string]$config.server.port,
        "--model", ('"{0}"' -f $llmPath),
        "--n-gpu-layers", [string]$config.runtime.n_gpu_layers,
        "--ctx-size", [string]$config.runtime.ctx_size,
        "--repeat-penalty", "1.05",
        "--temp", "0.7"
    )
    $script:serverProcess = Start-Process -FilePath $serverPath -ArgumentList $arguments `
        -WorkingDirectory $PackageRoot -PassThru -RedirectStandardOutput $serverOutput `
        -RedirectStandardError $serverError

    $deadline = (Get-Date).AddSeconds([int]$config.server.health_timeout_seconds)
    do {
        if ($script:serverProcess.HasExited) { throw "llama-omni-server exited before health ready" }
        & $adapterPath health --base-url $baseUrl --timeout-seconds 3 *> $null
        if ($LASTEXITCODE -eq 0) { break }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    if ((Get-Date) -ge $deadline) { throw "llama-omni-server health timeout" }

    & $adapterPath init --base-url $baseUrl --timeout-seconds ([string]$config.server.health_timeout_seconds) `
        --model-dir $ModelRoot --output-dir $runtimeOutput --prompt-file $promptPath *> $null
    if ($LASTEXITCODE -ne 0) { throw "official omni_init failed" }
}

function Stop-OfficialServer {
    param([switch]$AllowHardKill)
    if ($null -eq $script:serverProcess) { return }
    if (-not $script:serverProcess.HasExited) {
        # Matches Comni's terminate -> bounded wait -> kill fallback lifecycle.
        Stop-Process -Id $script:serverProcess.Id -ErrorAction SilentlyContinue
        if (-not $script:serverProcess.WaitForExit([int]$config.server.shutdown_timeout_seconds * 1000)) {
            if (-not $AllowHardKill) { throw "llama-omni-server graceful shutdown timeout" }
            Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue
            $script:hardKillUsed = $true
            $script:serverProcess.WaitForExit()
        }
    }
    $script:processExits += [ordered]@{
        pid = $script:serverProcess.Id
        exit_code = $script:serverProcess.ExitCode
    }
    $script:serverProcess = $null
}

$vramSamples = @()
try {
    $vramSamples += Get-VramSample -Phase "before"
    Start-OfficialServer
    $vramSamples += Get-VramSample -Phase "during"
    $timelineStart = [Diagnostics.Stopwatch]::StartNew()

    foreach ($step in @($dryRunPlan.steps)) {
        $waitMs = [int]$step.offset_ms - [int]$timelineStart.ElapsedMilliseconds
        if ($waitMs -gt 0) { Start-Sleep -Milliseconds $waitMs }
        $audioPath = Join-Path $InputRoot ([string]$step.audio).Replace("/", "\")
        $imagePath = Join-Path $InputRoot ([string]$step.image).Replace("/", "\")
        $stepJson = & $adapterPath step --base-url $baseUrl `
            --timeout-seconds ([string]$profileConfig.hard_timeout_seconds) `
            --audio $audioPath --image $imagePath --cnt ([string]$step.cnt)
        if ($LASTEXITCODE -ne 0) { throw "official prefill/decode failed at cnt=$($step.cnt)" }
        $round = ($stepJson | Out-String) | ConvertFrom-Json
        [string]$round.raw_sse | Set-Content -LiteralPath `
            (Join-Path $EvidenceRoot ("raw-sse\{0:D2}.sse" -f [int]$step.cnt)) -Encoding utf8NoBOM
        $rounds += [ordered]@{
            cnt = [int]$step.cnt
            is_listen = [bool]$round.is_listen
            stop = [bool]$round.stop
            done = [bool]$round.done
            content_length = ([string]$round.content).Length
            first_fragment_latency_ms = [int64]$round.first_fragment_latency_ms
            completion_latency_ms = [int64]$round.completion_latency_ms
        }
        if (-not [string]::IsNullOrEmpty([string]$round.content)) {
            $finalText = [string]$round.content
            break
        }
    }
    if ([string]::IsNullOrEmpty($finalText)) { throw "official O-IN-07 completed without a SPEAK text round" }
    $finalTextPath = Join-Path $EvidenceRoot "final-text.txt"
    $finalText | Set-Content -LiteralPath $finalTextPath -Encoding utf8NoBOM
    $parsed = & $adapterPath validate --input $finalTextPath `
        --styles ((@($config.style_ids) -join ",")) --budget ([string]$profileConfig.max_chinese_chars)
    if ($LASTEXITCODE -ne 0) { throw "V2 exactly-three-batch contract failed" }
    $parsedJson = ($parsed | Out-String) | ConvertFrom-Json
    Write-JsonUtf8 -Value $parsedJson -Path (Join-Path $EvidenceRoot "final-parsed.json")

    & $adapterPath break --base-url $baseUrl --timeout-seconds 10 *> $null
    if ($LASTEXITCODE -ne 0) { throw "official break failed" }
    $sessionBreak = "PASS"
    Stop-OfficialServer -AllowHardKill

    # Comni full_reinit: restart the official server and omni_init a clean context.
    Start-OfficialServer
    $fullReinit = "PASS"
    & $adapterPath break --base-url $baseUrl --timeout-seconds 10 *> $null
    Stop-OfficialServer -AllowHardKill
    $vramSamples += Get-VramSample -Phase "after"
} catch {
    $runError = $_.Exception.Message
} finally {
    if ($null -ne $serverProcess) {
        try { & $adapterPath break --base-url $baseUrl --timeout-seconds 3 *> $null } catch {}
        try { Stop-OfficialServer -AllowHardKill } catch {}
    }
    if (@($vramSamples | Where-Object phase -eq "after").Count -eq 0) {
        try { $vramSamples += Get-VramSample -Phase "after" } catch {}
    }
}

$selectedRound = @($rounds | Where-Object content_length -gt 0 | Select-Object -First 1)
$summary = [ordered]@{
    schema_version = 1
    result = if ($null -eq $runError) { "PASS" } else { "FAIL" }
    error = $runError
    profile = $Profile
    cadence = "official-1hz"
    input_id = "O-IN-07"
    upstream_commits = @($lock.components | ForEach-Object { [ordered]@{ name = $_.name; commit = $_.commit } })
    model_hashes = $modelEvidence
    rounds = $rounds
    first_fragment_latency_ms = if ($selectedRound.Count -eq 1) { $selectedRound[0].first_fragment_latency_ms } else { $null }
    completion_latency_ms = if ($selectedRound.Count -eq 1) { $selectedRound[0].completion_latency_ms } else { $null }
    session_break = $sessionBreak
    full_reinit = $fullReinit
    process_exit = $processExits
    hard_kill_fallback_used = $hardKillUsed
    vram = $vramSamples
}
Write-JsonUtf8 -Value $summary -Path (Join-Path $EvidenceRoot "summary.json")
if ($null -ne $runError) { throw "Official-First run failed: $runError; evidence=$EvidenceRoot" }
Write-Host "Official-First PASS: $EvidenceRoot"
