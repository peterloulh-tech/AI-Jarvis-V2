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
    $Value | ConvertTo-Json -Depth 64 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
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
if ($config.transport -ne "/backend" -or $config.runtime.use_tts -ne $false) {
    throw "official /backend no-TTS profile changed"
}
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
$modelEvidence = @()
foreach ($model in @($lock.model.files)) {
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
        if ((Get-LowerSha256 -Path $assetPath) -ne [string]$chunk.$hashProperty) {
            throw "O-IN-07 $kind SHA-256 mismatch at cnt=$($step.cnt)"
        }
    }
}

New-Item -ItemType Directory -Path $EvidenceRoot -Force | Out-Null
$promptPath = Join-Path $EvidenceRoot "session-contract-prompt.txt"
$effectivePrompt = ([string]$config.contract_prompt_template).Replace(
    "{{MAX_CHINESE_CHARS}}", [string]$profileConfig.max_chinese_chars)
if ($effectivePrompt.Contains("{{MAX_CHINESE_CHARS}}")) { throw "contract prompt budget is unresolved" }
$effectivePrompt | Set-Content -LiteralPath $promptPath -Encoding utf8NoBOM
$serverOutput = Join-Path $EvidenceRoot "llama-omni-server.stdout.log"
$serverError = Join-Path $EvidenceRoot "llama-omni-server.stderr.log"
$baseUrl = "http://$($config.server.host):$($config.server.port)"
$serverProcess = $null
$processExits = @()
$hardKillUsed = $false
$runError = $null
$backendRun = $null

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
    $llmPath = Join-Path $ModelRoot "MiniCPM-o-4_5-Q4_K_M.gguf"
    Assert-File -Path $llmPath -Label "external LLM model"
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
        if ($LASTEXITCODE -eq 0) { return }
        Start-Sleep -Seconds 1
    } while ((Get-Date) -lt $deadline)
    throw "llama-omni-server health timeout"
}

function Stop-OfficialServer {
    param([switch]$AllowHardKill)
    if ($null -eq $script:serverProcess) { return }
    if (-not $script:serverProcess.HasExited) {
        Stop-Process -Id $script:serverProcess.Id -ErrorAction SilentlyContinue
        if (-not $script:serverProcess.WaitForExit([int]$config.server.shutdown_timeout_seconds * 1000)) {
            if (-not $AllowHardKill) { throw "llama-omni-server shutdown timeout" }
            Stop-Process -Id $script:serverProcess.Id -Force -ErrorAction SilentlyContinue
            $script:hardKillUsed = $true
            $script:serverProcess.WaitForExit()
        }
    }
    $script:processExits += [ordered]@{ pid = $script:serverProcess.Id; exit_code = $script:serverProcess.ExitCode }
    $script:serverProcess = $null
}

$vramSamples = @()
try {
    $vramSamples += Get-VramSample -Phase "before"
    Start-OfficialServer
    $runJson = & $adapterPath run `
        --base-url $baseUrl `
        --manifest $manifestPath `
        --input-root $InputRoot `
        --prompt-file $promptPath `
        --styles ((@($config.style_ids) -join ",")) `
        --budget ([string]$profileConfig.max_chinese_chars) `
        --init-timeout-seconds ([string]$config.server.health_timeout_seconds) `
        --timeout-seconds ([string]$profileConfig.hard_timeout_seconds)
    if ($LASTEXITCODE -ne 0) { throw "official /backend evidence session failed" }
    $backendRun = ($runJson | Out-String) | ConvertFrom-Json
    $expectedInputs = @($manifest.chunks).Count
    if ($backendRun.transport -ne "/backend" -or -not $backendRun.warmup_close.closed -or
        -not $backendRun.session_close.closed -or [string]::IsNullOrWhiteSpace([string]$backendRun.content) -or
        [int]$backendRun.sent_inputs -ne $expectedInputs -or
        [int]$backendRun.terminal_responses -ne $expectedInputs -or
        -not $backendRun.pause_resume_contract.new_session) {
        throw "official /backend lifecycle evidence is incomplete"
    }
    Write-JsonUtf8 -Value $backendRun.events -Path (Join-Path $EvidenceRoot "backend-events.json")
    [string]$backendRun.content | Set-Content -LiteralPath (Join-Path $EvidenceRoot "final-text.txt") -Encoding utf8NoBOM
    Write-JsonUtf8 -Value $backendRun.parsed -Path (Join-Path $EvidenceRoot "final-parsed.json")
    $vramSamples += Get-VramSample -Phase "during"
    Stop-OfficialServer -AllowHardKill
    $vramSamples += Get-VramSample -Phase "after"
} catch {
    $runError = $_.Exception.Message
} finally {
    if ($null -ne $serverProcess) {
        try { Stop-OfficialServer -AllowHardKill } catch {}
    }
    if (@($vramSamples | Where-Object phase -eq "after").Count -eq 0) {
        try { $vramSamples += Get-VramSample -Phase "after" } catch {}
    }
}

$summary = [ordered]@{
    schema_version = 2
    result = if ($null -eq $runError) { "PASS" } else { "FAIL" }
    error = $runError
    profile = $Profile
    transport = "/backend"
    cadence = "official-1hz"
    input_id = "O-IN-07"
    upstream_commits = @($lock.components | ForEach-Object { [ordered]@{ name = $_.name; commit = $_.commit } })
    model_hashes = $modelEvidence
    session_id = if ($null -ne $backendRun) { $backendRun.session_id } else { $null }
    warmup_session_id = if ($null -ne $backendRun) { $backendRun.warmup_session_id } else { $null }
    official_session_reuse = if ($null -ne $backendRun -and $backendRun.warmup_close.closed -and $backendRun.session_close.closed) { "PASS" } else { "NOT_RUN" }
    sent_inputs = if ($null -ne $backendRun) { $backendRun.sent_inputs } else { 0 }
    terminal_responses = if ($null -ne $backendRun) { $backendRun.terminal_responses } else { 0 }
    first_fragment_latency_ms = if ($null -ne $backendRun) { $backendRun.first_fragment_latency_ms } else { $null }
    completion_latency_ms = if ($null -ne $backendRun) { $backendRun.completion_latency_ms } else { $null }
    process_exit = $processExits
    hard_kill_fallback_used = $hardKillUsed
    vram = $vramSamples
}
Write-JsonUtf8 -Value $summary -Path (Join-Path $EvidenceRoot "summary.json")
if ($null -ne $runError) { throw "Official-First run failed: $runError; evidence=$EvidenceRoot" }
Write-Host "Official-First PASS: $EvidenceRoot"
