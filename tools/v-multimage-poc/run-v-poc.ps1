param(
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
    [string]$FullShaPurpose = ""
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

& $Python "$scriptDir/run_v_poc.py" run `
    --profile $Profile `
    --server $Server `
    --models-dir $ModelsDir `
    --output $OutputDir
exit $LASTEXITCODE
