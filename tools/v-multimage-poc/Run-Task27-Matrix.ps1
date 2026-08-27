[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$HardwareProfileId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("high-performance-ac", "balanced-ac", "UNCONFIRMED")]
    [string]$PowerPolicy,

    [ValidateRange(1, 10000)]
    [int]$Samples = 20,

    [ValidateRange(0, 100)]
    [int]$Warmup = 1,

    [string]$RunPrefix = (Get-Date -Format "yyyyMMdd-HHmmss"),

    [ValidateSet("V-C01", "V-C02")]
    [string[]]$Profiles = @("V-C01", "V-C02"),

    [switch]$PrepareRuntime
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($PrepareRuntime) { & (Join-Path $Root "Prepare-V-Windows-Test.ps1") }

$RuntimeState = Get-Content -LiteralPath (Join-Path $Root "prepared-runtime.json") -Raw | ConvertFrom-Json
$OutputDir = Join-Path $Root "Evidence"
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

foreach ($Profile in $Profiles) {
    $ModelsDir = Join-Path $Root (Join-Path "Models" $Profile)
    if (-not (Test-Path -LiteralPath $ModelsDir)) { throw "Missing model directory: $ModelsDir" }
    foreach ($Slots in 1..3) {
        foreach ($ImageCount in 1..3) {
            $RunId = "$RunPrefix-$Profile-s$Slots-i$ImageCount"
            & (Join-Path $Root "run-v-poc.ps1") -Mode Benchmark -Profile $Profile `
                -Python $RuntimeState.python -Server $RuntimeState.server -ModelsDir $ModelsDir `
                -OutputDir $OutputDir -Slots $Slots -ImageCount $ImageCount -Samples $Samples `
                -Warmup $Warmup -RunId $RunId -AppVersion "task27-v-win-package-v1" `
                -HardwareProfileId $HardwareProfileId -PowerPolicy $PowerPolicy
            if ($LASTEXITCODE -ne 0) { throw "Normal group failed: $RunId" }
        }
    }
    foreach ($Fault in "cancel", "server-exit", "global-reset") {
        $RunId = "$RunPrefix-$Profile-s3-i3-$Fault"
        & (Join-Path $Root "run-v-poc.ps1") -Mode Benchmark -Profile $Profile `
            -Python $RuntimeState.python -Server $RuntimeState.server -ModelsDir $ModelsDir `
            -OutputDir $OutputDir -Slots 3 -ImageCount 3 -Samples $Samples -Warmup $Warmup `
            -Fault $Fault -RunId $RunId -AppVersion "task27-v-win-package-v1" `
            -HardwareProfileId $HardwareProfileId -PowerPolicy $PowerPolicy
        if ($LASTEXITCODE -ne 0) { throw "Fault group failed: $RunId" }
    }
}

Write-Host "Task27 matrix completed. Evidence: $OutputDir"
