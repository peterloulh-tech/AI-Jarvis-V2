param(
    [ValidateSet("Poc", "Benchmark")]
    [string]$Mode = "Poc",

    [Parameter(Mandatory = $true)]
    [ValidateSet("V-C01", "V-C02")]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [string]$Python,

    [Parameter(Mandatory = $true)]
    [string]$Server,

    [Parameter(Mandatory = $true)]
    [string]$ModelsDir,

    [Parameter(Mandatory = $true)]
    [string]$OutputDir,

    [ValidateSet("", "initial-admission", "changed-artifact", "final-package")]
    [string]$FullShaPurpose = "",

    [ValidateSet(1, 2, 3)]
    [int]$Slots = 1,

    [ValidateSet(1, 2, 3)]
    [int]$ImageCount = 1,

    [ValidateRange(1, 10000)]
    [int]$Samples = 20,

    [ValidateRange(0, 100)]
    [int]$Warmup = 1,

    [ValidateSet("none", "cancel", "server-exit", "global-reset")]
    [string]$Fault = "none",

    [string]$RunId = "",

    [string]$Styles = "friendly-witty-v1",

    [string]$AppVersion = "UNCONFIRMED",

    [string]$HardwareProfileId = "",

    [string]$PowerPolicy = "UNCONFIRMED"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ($FullShaPurpose) {
    & $Python "$scriptDir/run_v_poc.py" admit `
        --profile $Profile `
        --server $Server `
        --models-dir $ModelsDir `
        --output $OutputDir `
        --purpose $FullShaPurpose
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
}

& $Python "$scriptDir/run_v_poc.py" check `
    --profile $Profile `
    --server $Server `
    --models-dir $ModelsDir `
    --output $OutputDir
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

if ($Mode -eq "Benchmark") {
    $benchmarkArgs = @(
        "$scriptDir/run_v_poc.py",
        "benchmark",
        "--profile", $Profile,
        "--server", $Server,
        "--models-dir", $ModelsDir,
        "--output", $OutputDir,
        "--slots", $Slots,
        "--image-count", $ImageCount,
        "--samples", $Samples,
        "--warmup", $Warmup,
        "--fault", $Fault,
        "--styles", $Styles,
        "--app-version", $AppVersion,
        "--power-policy", $PowerPolicy
    )
    if ($RunId) {
        $benchmarkArgs += @("--run-id", $RunId)
    }
    if ($HardwareProfileId) {
        $benchmarkArgs += @("--hardware-profile-id", $HardwareProfileId)
    }
    & $Python @benchmarkArgs
    exit $LASTEXITCODE
}

& $Python "$scriptDir/run_v_poc.py" run `
    --profile $Profile `
    --server $Server `
    --models-dir $ModelsDir `
    --output $OutputDir
exit $LASTEXITCODE
