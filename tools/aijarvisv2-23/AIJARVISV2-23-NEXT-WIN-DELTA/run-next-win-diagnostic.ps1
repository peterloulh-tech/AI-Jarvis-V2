#requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet("O-CASE-A", "O-CASE-B")][string]$Case,
    [string]$PortableRoot,
    [string]$ModelRoot,
    [string]$OriginalInputRoot,
    [string]$ResultBase,
    [ValidateRange(5, 120)][int]$CaseTimeoutMinutes = 45,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ToolRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$FieldRoot = Split-Path -Parent $ToolRoot
. (Join-Path $ToolRoot "aggregate-speak-fragments.ps1")
if (-not $PortableRoot) { $PortableRoot = Join-Path $FieldRoot "AIJARVISV2-23-windows-x64-cuda-portable" }
if (-not $ModelRoot) { $ModelRoot = Join-Path $FieldRoot "models\MiniCPM-o-4_5-gguf" }
if (-not $OriginalInputRoot) { $OriginalInputRoot = Join-Path $FieldRoot "o-in-07" }
if (-not $ResultBase) { $ResultBase = Join-Path $ToolRoot "results" }
$PortableRoot = [IO.Path]::GetFullPath($PortableRoot)
$ModelRoot = [IO.Path]::GetFullPath($ModelRoot)
$OriginalInputRoot = [IO.Path]::GetFullPath($OriginalInputRoot)
$ResultBase = [IO.Path]::GetFullPath($ResultBase)
$Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Assert-File {
    param([Parameter(Mandatory = $true)][string]$Path, [string]$Label = "file")
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing ${Label}: $Path" }
}

function Assert-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Expected, [string]$Label = "file")
    Assert-File -Path $Path -Label $Label
    $actual = Get-Sha256 -Path $Path
    if ($actual -ne $Expected.ToLowerInvariant()) { throw "$Label SHA-256 mismatch: $Path" }
}

function Write-JsonFile {
    param([Parameter(Mandatory = $true)]$Value, [Parameter(Mandatory = $true)][string]$Path)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 32) + [Environment]::NewLine, $Utf8NoBom)
}

function Get-QuotedArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    return '"' + $Value.Replace('"', '\"') + '"'
}

$ConfigPath = Join-Path $ToolRoot "diagnostic-config.json"
Assert-File -Path $ConfigPath -Label "diagnostic config"
$Config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$CaseConfig = $Config.cases.PSObject.Properties[$Case].Value
if ($null -eq $CaseConfig) { throw "Unknown diagnostic case: $Case" }

$PortableManifestPath = Join-Path $PortableRoot "portable-manifest.json"
$BuildManifestPath = Join-Path $PortableRoot "portable-build-manifest.json"
Assert-File -Path $PortableManifestPath -Label "existing portable manifest"
Assert-File -Path $BuildManifestPath -Label "existing portable build manifest"
Assert-Sha256 -Path $PortableManifestPath -Expected ([string]$Config.portable_manifest_sha256) -Label "exact existing portable manifest"
Assert-Sha256 -Path $BuildManifestPath -Expected ([string]$Config.portable_build_manifest_sha256) -Label "exact existing portable build manifest"
$PortableManifest = Get-Content -LiteralPath $PortableManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$BuildManifest = Get-Content -LiteralPath $BuildManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($PortableManifest.artifact_name -ne $Config.portable_artifact -or
    $PortableManifest.source_commit -ne $Config.portable_source_commit -or
    $PortableManifest.runtime_revision -ne $Config.runtime_revision -or
    $PortableManifest.runtime_patch_sha256 -ne $Config.runtime_patch_sha256 -or
    $BuildManifest.runtime_revision -ne $Config.runtime_revision -or
    $BuildManifest.runtime_patch_sha256 -ne $Config.runtime_patch_sha256 -or
    $BuildManifest.source_commit -ne $Config.portable_source_commit) {
    throw "Existing portable/runtime identity does not match the locked O-C01 diagnostic config"
}
$BuildManifestEntry = @($PortableManifest.files | Where-Object { $_.path -eq "portable-build-manifest.json" })
if ($BuildManifestEntry.Count -ne 1) { throw "Portable manifest must identify portable-build-manifest.json exactly once" }
Assert-Sha256 -Path $BuildManifestPath -Expected ([string]$BuildManifestEntry[0].sha256) -Label "existing portable build manifest"
$Executable = Join-Path $PortableRoot ([string]$Config.executable.path).Replace("/", "\")
if ((Get-Item -LiteralPath $Executable).Length -ne [int64]$Config.executable.size -or
    ([string]$BuildManifest.executable_sha256).ToLowerInvariant() -ne ([string]$Config.executable.sha256).ToLowerInvariant()) {
    throw "Existing Task23 EXE size or build identity does not match the pinned field baseline"
}
Assert-Sha256 -Path $Executable -Expected ([string]$Config.executable.sha256) -Label "exact existing Task23 EXE"
$ExecutableEntry = @($PortableManifest.files | Where-Object { $_.path -eq "bin/aijarvisv2-task23-poc.exe" })
if ($ExecutableEntry.Count -ne 1 -or [int64]$ExecutableEntry[0].size -ne [int64]$Config.executable.size -or
    ([string]$ExecutableEntry[0].sha256).ToLowerInvariant() -ne ([string]$Config.executable.sha256).ToLowerInvariant()) {
    throw "Portable manifest and build manifest disagree on the existing Task23 EXE"
}
foreach ($expectedDll in @($Config.runtime_dlls)) {
    $BuildDll = @($BuildManifest.runtime_dlls | Where-Object { $_.path -eq ([string]$expectedDll.path) })
    $DllEntry = @($PortableManifest.files | Where-Object { $_.path -eq ([string]$expectedDll.path) })
    if ($BuildDll.Count -ne 1 -or $DllEntry.Count -ne 1 -or
        [int64]$BuildDll[0].size -ne [int64]$expectedDll.size -or [int64]$DllEntry[0].size -ne [int64]$expectedDll.size -or
        ([string]$BuildDll[0].sha256).ToLowerInvariant() -ne ([string]$expectedDll.sha256).ToLowerInvariant() -or
        ([string]$DllEntry[0].sha256).ToLowerInvariant() -ne ([string]$expectedDll.sha256).ToLowerInvariant()) {
        throw "Portable identity does not match pinned runtime DLL $($expectedDll.path)"
    }
    Assert-Sha256 -Path (Join-Path $PortableRoot ([string]$expectedDll.path).Replace("/", "\")) `
        -Expected ([string]$expectedDll.sha256) -Label "exact existing portable runtime DLL"
}

$ModelProvenancePath = Join-Path $ModelRoot "MODEL_PROVENANCE.json"
Assert-File -Path $ModelProvenancePath -Label "model provenance"
$ModelProvenance = Get-Content -LiteralPath $ModelProvenancePath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($ModelProvenance.repo_id -ne "openbmb/MiniCPM-o-4_5-gguf" -or
    $ModelProvenance.revision -ne $Config.model_revision -or @($ModelProvenance.files).Count -ne @($Config.model_files).Count) {
    throw "Model provenance does not match the locked MiniCPM-o model"
}
foreach ($expectedModelFile in @($Config.model_files)) {
    $provenanceEntry = @($ModelProvenance.files | Where-Object { $_.path -eq ([string]$expectedModelFile.path) })
    if ($provenanceEntry.Count -ne 1 -or [int64]$provenanceEntry[0].size -ne [int64]$expectedModelFile.size -or
        ([string]$provenanceEntry[0].sha256).ToLowerInvariant() -ne ([string]$expectedModelFile.sha256).ToLowerInvariant()) {
        throw "Model provenance does not match pinned file $($expectedModelFile.path)"
    }
    $relative = ([string]$expectedModelFile.path).Replace("/", "\")
    $path = Join-Path $ModelRoot $relative
    Assert-File -Path $path -Label "locked model file"
    if ((Get-Item -LiteralPath $path).Length -ne [int64]$expectedModelFile.size) { throw "Model size mismatch: $path" }
    Assert-Sha256 -Path $path -Expected ([string]$expectedModelFile.sha256) -Label "locked model file"
}

$InputRoot = if ($CaseConfig.input_kind -eq "original-3s") { $OriginalInputRoot } else { Join-Path $ToolRoot "O-IN-07-1HZ" }
$InputManifestPath = Join-Path $InputRoot "manifest.json"
$ExpectedManifestHash = if ($CaseConfig.input_kind -eq "original-3s") { [string]$Config.source_manifest_sha256 } else { [string]$Config.one_hz_manifest_sha256 }
Assert-Sha256 -Path $InputManifestPath -Expected $ExpectedManifestHash -Label "$Case input manifest"
$InputManifest = Get-Content -LiteralPath $InputManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($InputManifest.input_id -ne "O-IN-07" -or -not $InputManifest.deidentified -or
    -not $InputManifest.rights_confirmed -or @($InputManifest.style_ids).Count -ne 3 -or
    @($InputManifest.chunks).Count -ne [int]$CaseConfig.expected_chunk_count) {
    throw "$Case input identity, rights, styles, or chunk count is invalid"
}
foreach ($metadata in @(
    @{ path = $InputManifest.authorization_record; hash = $InputManifest.authorization_sha256; label = "authorization" },
    @{ path = $InputManifest.gold_record; hash = $InputManifest.gold_sha256; label = "gold record" }
)) {
    Assert-Sha256 -Path (Join-Path $InputRoot ([string]$metadata.path)) -Expected ([string]$metadata.hash) -Label ([string]$metadata.label)
}
$Rounds = @()
$ExpectedDurationMs = [int64]$CaseConfig.expected_chunk_duration_ms
for ($index = 0; $index -lt @($InputManifest.chunks).Count; ++$index) {
    $chunk = @($InputManifest.chunks)[$index]
    $expectedSequence = $index + 1
    $expectedOffset = [int64]$index * $ExpectedDurationMs
    if ([int64]$chunk.sequence -ne $expectedSequence -or [int64]$chunk.offset_ms -ne $expectedOffset -or
        [int64]$chunk.duration_ms -ne $ExpectedDurationMs -or -not $chunk.marker) {
        throw "$Case timeline is not continuous at sequence $expectedSequence"
    }
    foreach ($asset in @(
        @{ path = $chunk.audio; hash = $chunk.audio_sha256; label = "audio" },
        @{ path = $chunk.image; hash = $chunk.image_sha256; label = "image" }
    )) {
        Assert-Sha256 -Path (Join-Path $InputRoot ([string]$asset.path)) -Expected ([string]$asset.hash) -Label "$Case $($asset.label)"
    }
    if ($expectedOffset -le ([int64]$CaseConfig.context_seconds * 1000)) {
        $Rounds += [pscustomobject]@{
            round = $Rounds.Count + 1
            sequence = [int64]$chunk.sequence
            offset_ms = [int64]$chunk.offset_ms
            duration_ms = [int64]$chunk.duration_ms
            marker = [string]$chunk.marker
            source_sequence = if ($null -ne $chunk.PSObject.Properties["source_sequence"]) { [int64]$chunk.source_sequence } else { [int64]$chunk.sequence }
            source_part = if ($null -ne $chunk.PSObject.Properties["source_part"]) { [int]$chunk.source_part } else { 1 }
            expected_decision_mode = if ($Rounds.Count -lt 3) { "startup-guard-LISTEN" } else { "autonomous" }
        }
    }
}
$TimelineEndMs = @($InputManifest.chunks).Count * $ExpectedDurationMs
if ([int64]$InputManifest.duration_ms -ne $TimelineEndMs -or $Rounds.Count -ne [int]$CaseConfig.expected_selected_rounds) {
    throw "$Case duration or selected round count does not match diagnostic config"
}

$DryRunRecord = [ordered]@{
    schema_version = 1
    task_id = "AIJARVISV2-23"
    case = $Case
    diagnostic_label = $CaseConfig.diagnostic_label
    no_rebuild = $true
    executable = $Executable
    executable_sha256 = Get-Sha256 -Path $Executable
    runtime_revision = $Config.runtime_revision
    model_revision = $Config.model_revision
    model_root = $ModelRoot
    input_manifest = $InputManifestPath
    input_manifest_sha256 = Get-Sha256 -Path $InputManifestPath
    total_chunk_count = @($InputManifest.chunks).Count
    chunk_duration_ms = $ExpectedDurationMs
    total_duration_ms = $TimelineEndMs
    context_seconds = [int]$CaseConfig.context_seconds
    selected_round_count = $Rounds.Count
    startup_guard_rounds = 3
    autonomous_round_count = $Rounds.Count - 3
    tier = $CaseConfig.tier
    budget_chars = [int]$CaseConfig.budget_chars
    result_base = $ResultBase
    rounds = $Rounds
}
if ($DryRun) {
    $DryRunRecord | ConvertTo-Json -Depth 32
    exit 0
}

if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or -not [Environment]::Is64BitOperatingSystem) {
    throw "Dynamic execution requires Windows x64; use -DryRun for zero-GPU validation"
}
if (-not (Get-Command "nvidia-smi.exe" -ErrorAction SilentlyContinue)) { throw "nvidia-smi.exe is required for dynamic execution" }

$Timestamp = (Get-Date).ToUniversalTime().ToString("yyyyMMdd-HHmmss")
$RunId = "O10-P23-NEXT-$Case-$Timestamp-WIN-01"
$ResultRoot = Join-Path (Join-Path $ResultBase $Case) $RunId
if (Test-Path -LiteralPath $ResultRoot) { throw "Refusing to overwrite existing result directory: $ResultRoot" }
New-Item -ItemType Directory -Path $ResultRoot -Force | Out-Null
Write-JsonFile -Value $DryRunRecord -Path (Join-Path $ResultRoot "run-config.json")

$EvidencePath = Join-Path $ResultRoot "evidence.jsonl"
$StdoutPath = Join-Path $ResultRoot "stdout.log"
$StderrPath = Join-Path $ResultRoot "stderr.log"
$Arguments = @(
    "--mode", "case",
    "--model-root", $ModelRoot,
    "--input-manifest", $InputManifestPath,
    "--output", $EvidencePath,
    "--run-id", $RunId,
    "--case-id", [string]$CaseConfig.case_id,
    "--tier", [string]$CaseConfig.tier,
    "--budget-chars", [string]$CaseConfig.budget_chars,
    "--context-seconds", [string]$CaseConfig.context_seconds,
    "--hard-timeout-seconds", [string]$CaseConfig.hard_timeout_seconds,
    "--run-generation", [string]$CaseConfig.run_generation
)
$ArgumentText = ($Arguments | ForEach-Object { Get-QuotedArgument -Value ([string]$_) }) -join " "
$Process = Start-Process -FilePath $Executable -ArgumentList $ArgumentText -PassThru `
    -RedirectStandardOutput $StdoutPath -RedirectStandardError $StderrPath -WindowStyle Hidden
$Deadline = (Get-Date).AddMinutes($CaseTimeoutMinutes)
while (-not $Process.HasExited -and (Get-Date) -lt $Deadline) {
    Start-Sleep -Seconds 1
    $Process.Refresh()
}
$RunnerOutcome = "completed"
if (-not $Process.HasExited) {
    & taskkill.exe /PID $Process.Id /T /F *> $null
    $RunnerOutcome = "runner_timeout"
}
$Process.WaitForExit()

$FragmentPath = Join-Path $ResultRoot "speak-fragments.jsonl"
$AggregationPath = Join-Path $ResultRoot "speak-aggregation.json"
$AggregationOutcome = "failure"
$AggregationError = ""
try {
    if (-not (Test-Path -LiteralPath $EvidencePath -PathType Leaf)) { throw "Harness did not write evidence.jsonl" }
    $AggregationReport = Invoke-Task23SpeakAggregation -InputPath $EvidencePath `
        -FragmentPath $FragmentPath -SummaryPath $AggregationPath -StyleIds @($Config.style_ids) `
        -MinimumItems 1 -MaximumItems 5 -BudgetChars ([int]$CaseConfig.budget_chars)
    $AggregationOutcome = "success"
} catch {
    $AggregationError = $_.Exception.Message
    Write-JsonFile -Value ([ordered]@{
        schema_version = 1; outcome = "failure"; error = $AggregationError
        evidence = $EvidencePath; generated_at = (Get-Date).ToUniversalTime().ToString("o")
    }) -Path (Join-Path $ResultRoot "speak-aggregation-error.json")
}
$ExecutionSummary = [ordered]@{
    schema_version = 1
    run_id = $RunId
    case = $Case
    diagnostic_label = $CaseConfig.diagnostic_label
    runner_outcome = $RunnerOutcome
    process_exit_code = $Process.ExitCode
    aggregation_outcome = $AggregationOutcome
    aggregation_error = $AggregationError
    dynamic_only = $true
    evidence = $EvidencePath
    aggregation = Join-Path $ResultRoot "speak-aggregation.json"
}
Write-JsonFile -Value $ExecutionSummary -Path (Join-Path $ResultRoot "execution-summary.json")
$HashLines = @()
foreach ($file in Get-ChildItem -LiteralPath $ResultRoot -File | Where-Object Name -ne "sha256sums.txt" | Sort-Object Name) {
    $HashLines += "$(Get-Sha256 -Path $file.FullName)  $($file.Name)"
}
$HashLines | Set-Content -LiteralPath (Join-Path $ResultRoot "sha256sums.txt") -Encoding ASCII
Write-Host "$Case results: $ResultRoot"
if ($RunnerOutcome -ne "completed" -or $Process.ExitCode -ne 0 -or $AggregationOutcome -ne "success") { exit 2 }
