#requires -Version 5.1

[CmdletBinding()]
param([Parameter(Mandatory = $true)][string]$PackageRoot)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Write-Utf8Lines {
    param([string]$Path, [string[]]$Lines)
    [IO.File]::WriteAllLines($Path, $Lines, (New-Object Text.UTF8Encoding($false)))
}

function Get-LatestRun {
    param([string]$ResultRoot)
    $runs = @(Get-ChildItem -LiteralPath $ResultRoot -Directory -Recurse |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "environment.json") -PathType Leaf } |
        Sort-Object LastWriteTimeUtc)
    Assert-True ($runs.Count -gt 0) "runner did not create an isolated result directory"
    return $runs[-1].FullName
}

$package = [IO.Path]::GetFullPath($PackageRoot)
$runner = Join-Path $package "run-o-reference-harness-v2.ps1"
Assert-True (Test-Path -LiteralPath $runner -PathType Leaf) "packaged runner is missing"
$testRoot = Join-Path $env:RUNNER_TEMP "Task93 no GPU 中文 path"
New-Item -ItemType Directory -Path $testRoot -Force | Out-Null

$normalSource = Join-Path $testRoot "normal mock 中文.jsonl"
$normalLines = @(
    '{"user_seq":1,"frame_id":1,"generation_id":1,"ok":true,"is_speak":false,"fragment":"","latency_ms":1.0,"input_offset_ms":0,"input_duration_ms":1000,"seen_at_us":1000000}',
    '{"user_seq":2,"frame_id":2,"generation_id":1,"ok":true,"is_speak":true,"fragment":"{\"batches\":[{\"style_id\":\"style-1\",\"items\":[\"中文一\"]},","latency_ms":2.0,"input_offset_ms":1000,"input_duration_ms":1000,"seen_at_us":2000000}',
    '{"user_seq":3,"frame_id":3,"generation_id":1,"ok":true,"is_speak":true,"fragment":"{\"style_id\":\"style-2\",\"items\":[\"中文二\"]},{\"style_id\":\"style-3\",\"items\":[\"中文三\"]}]}","latency_ms":3.0,"input_offset_ms":2000,"input_duration_ms":1000,"seen_at_us":3000000}',
    '{"user_seq":4,"frame_id":4,"generation_id":1,"ok":true,"is_speak":true,"fragment":"","latency_ms":4.0,"input_offset_ms":3000,"input_duration_ms":1000,"seen_at_us":4000000}',
    '{"user_seq":5,"frame_id":5,"generation_id":1,"ok":true,"is_speak":false,"fragment":"","latency_ms":5.0,"input_offset_ms":4000,"input_duration_ms":1000,"seen_at_us":5000000}',
    '{"user_seq":1,"frame_id":6,"generation_id":2,"ok":false,"is_speak":false,"fragment":"","latency_ms":6.0,"input_offset_ms":5000,"input_duration_ms":1000,"seen_at_us":6000000}'
)
Write-Utf8Lines -Path $normalSource -Lines $normalLines
$normalRoot = Join-Path $testRoot "normal results with spaces"
& $runner -Profile v2-contract -Cadence official-1hz -ResultRoot $normalRoot `
    -MockResultSource $normalSource -MockBoundary session_end_drain
$normalRun = Get-LatestRun -ResultRoot $normalRoot
$normalSummary = Get-Content -LiteralPath (Join-Path $normalRun "summary.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$normalRaw = @(Get-Content -LiteralPath (Join-Path $normalRun "raw-results.jsonl") -Encoding UTF8 |
    Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json })
$normalAggregates = @(
    (Get-Content -LiteralPath (Join-Path $normalRun "aggregations.json") -Raw -Encoding UTF8 |
        ConvertFrom-Json) | Write-Output
)
$normalEnvironment = Get-Content -LiteralPath (Join-Path $normalRun "environment.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($normalSummary.outcome -eq "passed") "normal mock summary must pass"
Assert-True ($normalSummary.input_processed -eq 6 -and $normalSummary.listen_count -eq 2 -and
    $normalSummary.speak_count -eq 3 -and $normalSummary.runtime_failure_count -eq 1) "normal counters mismatch"
Assert-True ($normalSummary.valid_three_batch_count -eq 1 -and $normalSummary.invalid_payload_count -eq 0) "validator counters mismatch"
Assert-True ($normalRaw.Count -eq 6 -and $normalRaw[1].fragment.Contains("中文一")) "UTF-8 JSONL did not round-trip"
Assert-True ($normalAggregates.Count -eq 2 -and $normalAggregates[0].payload_schema_state -eq "schema_valid") "aggregation mismatch"
Assert-True ($normalEnvironment.summary_present -eq $true -and $normalEnvironment.cleanup_idempotent -eq $true -and
    $normalEnvironment.cleanup_attempts -eq 2) "runner summary or repeated cleanup evidence mismatch"
Assert-True (@($normalEnvironment.cleanup_actions).Count -eq 2 -and
    $normalEnvironment.cleanup_actions[1].process_was_running -eq $false) "cleanup helper was not invoked idempotently"
Assert-True (Test-Path -LiteralPath (Join-Path $normalRun "sha256sums.txt") -PathType Leaf) "evidence hashes missing"

$emptySource = Join-Path $testRoot "empty.jsonl"
Write-Utf8Lines -Path $emptySource -Lines @()
$emptyRoot = Join-Path $testRoot "empty results"
& $runner -Profile v2-contract -Cadence official-1hz -ResultRoot $emptyRoot `
    -MockResultSource $emptySource -MockBoundary timeout
$emptyRun = Get-LatestRun -ResultRoot $emptyRoot
$emptySummary = Get-Content -LiteralPath (Join-Path $emptyRun "summary.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$emptyAggregates = @(
    (Get-Content -LiteralPath (Join-Path $emptyRun "aggregations.json") -Raw -Encoding UTF8 |
        ConvertFrom-Json) | Write-Output
)
Assert-True ($emptySummary.input_processed -eq 0 -and $emptyAggregates.Count -eq 0) "empty result source misreported evidence"

$malformedSource = Join-Path $testRoot "malformed.jsonl"
Write-Utf8Lines -Path $malformedSource -Lines @('{not-json')
$malformedRoot = Join-Path $testRoot "malformed results"
$caught = $null
try {
    & $runner -Profile v2-contract -Cadence official-1hz -ResultRoot $malformedRoot `
        -MockResultSource $malformedSource -MockBoundary input_exhausted
} catch {
    $caught = $_.Exception.Message
}
Assert-True ($caught -match "line 1: malformed JSON") "malformed JSON primary error was not propagated"
$malformedRun = Get-LatestRun -ResultRoot $malformedRoot
$malformedSummary = Get-Content -LiteralPath (Join-Path $malformedRun "summary.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$malformedEvidence = Get-Content -LiteralPath (Join-Path $malformedRun "evidence.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($malformedSummary.outcome -eq "failed" -and $malformedSummary.error_count -eq 1) "malformed summary misreported success"
Assert-True ($malformedEvidence.primary_error -eq $malformedSummary.primary_error) "summary/evidence primary errors diverged"

$combinedRoot = Join-Path $testRoot "combined errors"
$caught = $null
try {
    & $runner -Profile v2-contract -Cadence official-1hz -ResultRoot $combinedRoot `
        -MockResultSource $malformedSource -MockBoundary input_exhausted -MockCleanupError "cleanup boom"
} catch {
    $caught = $_.Exception.Message
}
Assert-True ($caught.StartsWith("line 1: malformed JSON") -and $caught.Contains("cleanup boom")) "cleanup error masked the primary error"
$combinedRun = Get-LatestRun -ResultRoot $combinedRoot
$combinedEnvironment = Get-Content -LiteralPath (Join-Path $combinedRun "environment.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True ($combinedEnvironment.primary_error -match "malformed JSON" -and
    $combinedEnvironment.cleanup_error -eq "cleanup boom" -and $combinedEnvironment.cleanup -eq "failed") "combined error evidence mismatch"

$timeoutSource = Join-Path $testRoot "timeout source.jsonl"
$writer = New-Object IO.StreamWriter($timeoutSource, $false, (New-Object Text.UTF8Encoding($false)))
try {
    for ($index = 1; $index -le 5000; $index += 1) {
        $writer.WriteLine("{`"user_seq`":$index,`"frame_id`":$index,`"generation_id`":1,`"ok`":true,`"is_speak`":false,`"fragment`":`"`"}")
    }
} finally {
    $writer.Dispose()
}
$timeoutRoot = Join-Path $testRoot "bounded timeout results"
$caught = $null
try {
    & $runner -Profile v2-contract -Cadence official-1hz -ResultRoot $timeoutRoot `
        -MockResultSource $timeoutSource -MockBoundary input_exhausted -ProcessTimeoutSeconds 0
} catch {
    $caught = $_.Exception.Message
}
Assert-True ($caught -match "Mock result replay timed out after 0 seconds") "mock wait was not bounded"
$timeoutRun = Get-LatestRun -ResultRoot $timeoutRoot
$timeoutEnvironment = Get-Content -LiteralPath (Join-Path $timeoutRun "environment.json") -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-True (@($timeoutEnvironment.cleanup_actions).Count -eq 2 -and
    $timeoutEnvironment.cleanup_actions[0].process_was_running -eq $true -and
    $timeoutEnvironment.cleanup_actions[1].process_was_running -eq $false -and
    $timeoutEnvironment.cleanup_idempotent -eq $true) "timeout did not perform idempotent process-tree cleanup"

Write-Host "PASS Windows PowerShell 5.1 no-GPU smoke"
