#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$RuntimeArchive,
    [Parameter(Mandatory = $true)][string]$CudartArchive,
    [Parameter(Mandatory = $true)][string]$PythonArchive,
    [Parameter(Mandatory = $true)][string]$SourceCommit,
    [string]$ArtifactName = "AIJARVISV2-27-v-windows-x64-cuda-portable"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)

function Assert-File([string]$Path, [string]$Label) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing $Label`: $Path" }
}

function Copy-Required([string]$Source, [string]$Destination) {
    Assert-File $Source "package input"
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Find-One([string]$Root, [string]$Name) {
    $matches = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Name)
    if ($matches.Count -ne 1) { throw "expected one $Name under $Root, found $($matches.Count)" }
    return $matches[0].FullName
}

function Sha256([string]$Path) {
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

Assert-File $RuntimeArchive "llama.cpp runtime archive"
Assert-File $CudartArchive "CUDA runtime archive"
Assert-File $PythonArchive "embedded Python archive"

$scratch = Join-Path ([IO.Path]::GetTempPath()) ("aijarvisv2-27-package-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $scratch -Force | Out-Null
try {
    $runtimeExtract = Join-Path $scratch "runtime"
    $cudartExtract = Join-Path $scratch "cudart"
    $pythonExtract = Join-Path $scratch "python"
    Expand-Archive -LiteralPath $RuntimeArchive -DestinationPath $runtimeExtract
    Expand-Archive -LiteralPath $CudartArchive -DestinationPath $cudartExtract
    Expand-Archive -LiteralPath $PythonArchive -DestinationPath $pythonExtract

    $server = Find-One $runtimeExtract "llama-server.exe"
    $python = Find-One $pythonExtract "python.exe"
    New-Item -ItemType Directory -Path $PackageRoot -Force | Out-Null
    Copy-Required $server (Join-Path $PackageRoot "bin\llama-server.exe")

    foreach ($root in @($runtimeExtract, $cudartExtract)) {
        # Keep every DLL shipped by the official runtime archive, including CPU and OpenMP sidecars.
        Get-ChildItem -LiteralPath $root -Recurse -File -Filter "*.dll" | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackageRoot "bin\$($_.Name)") -Force
        }
    }
    foreach ($pattern in @("cudart64_*.dll", "cublas64_*.dll", "cublasLt64_*.dll")) {
        if (@(Get-ChildItem -LiteralPath (Join-Path $PackageRoot "bin") -File -Filter $pattern).Count -eq 0) {
            throw "portable package is missing $pattern"
        }
    }

    New-Item -ItemType Directory -Path (Join-Path $PackageRoot "python") -Force | Out-Null
    Get-ChildItem -LiteralPath $pythonExtract -Force | Copy-Item -Destination (Join-Path $PackageRoot "python") -Recurse -Force
    # The embeddable distribution enables isolated mode through python*._pth.
    # Add the package root so the bundled script can import the sibling v_poc package.
    $pth = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot "python") -File -Filter "python*._pth")
    if ($pth.Count -ne 1) { throw "expected one embedded Python _pth file, found $($pth.Count)" }
    $pthLines = @(Get-Content -LiteralPath $pth[0].FullName)
    if ($pthLines -notcontains "..") {
        Add-Content -LiteralPath $pth[0].FullName -Value ".." -Encoding ascii
    }

    $toolRoot = Join-Path $RepositoryRoot "tools\v-multimage-poc"
    foreach ($file in @("run_v_poc.py", "run-v-poc.ps1", "Run-Task27-Matrix.ps1", "profiles.json", "README.md", "README-Windows-Package.md")) {
        Copy-Required (Join-Path $toolRoot $file) (Join-Path $PackageRoot $file)
    }
    Copy-Item -LiteralPath (Join-Path $toolRoot "v_poc") -Destination (Join-Path $PackageRoot "v_poc") -Recurse -Force
    Copy-Required (Join-Path $RepositoryRoot "docs\v2\requirements\v-model-runtime-candidate-lock.json") (Join-Path $PackageRoot "v-model-runtime-candidate-lock.json")
    Copy-Required (Join-Path $RepositoryRoot "LICENSE") (Join-Path $PackageRoot "licenses\AI-Jarvis-V2\LICENSE")

    New-Item -ItemType Directory -Path (Join-Path $PackageRoot "Models\V-C01"), (Join-Path $PackageRoot "Models\V-C02"), (Join-Path $PackageRoot "Fixtures") -Force | Out-Null
    "Place the locked V-C01 GGUF and mmproj files here." | Set-Content (Join-Path $PackageRoot "Models\V-C01\README.txt") -Encoding utf8NoBOM
    "Place the locked V-C02 GGUF and mmproj files here." | Set-Content (Join-Path $PackageRoot "Models\V-C02\README.txt") -Encoding utf8NoBOM
    "Synthetic fixture is generated automatically by run_v_poc.py. Add licensed real images only when a separate input contract is provided." | Set-Content (Join-Path $PackageRoot "Fixtures\README.txt") -Encoding utf8NoBOM

    # Materialize the deterministic fixture in the ZIP so the operator can inspect it before running.
    $previousPythonPath = $env:PYTHONPATH
    $env:PYTHONPATH = $PackageRoot
    & (Join-Path $PackageRoot "python\python.exe") (Join-Path $PackageRoot "run_v_poc.py") prepare --profile V-C01 --output (Join-Path $PackageRoot "Fixtures") *> $null
    if ($null -eq $previousPythonPath) { Remove-Item Env:PYTHONPATH -ErrorAction SilentlyContinue } else { $env:PYTHONPATH = $previousPythonPath }
    if ($LASTEXITCODE -ne 0) { throw "fixture generation failed" }

    $manifest = [ordered]@{
        schema_version = 1
        artifact_name = $ArtifactName
        task = "AIJARVISV2-27"
        source_commit = $SourceCommit
        runtime = "llama.cpp b10369 official Windows CUDA x64 asset"
        runtime_archives = @((Split-Path -Leaf $RuntimeArchive), (Split-Path -Leaf $CudartArchive))
        models_included = 0
        test_media_included = 0
        network = "runtime and benchmark are local; internet may remain connected"
        required_operator_inputs = @("Models/V-C01/*.gguf", "Models/V-C02/*.gguf")
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $PackageRoot "package-manifest.json") -Encoding utf8NoBOM

    $files = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        [ordered]@{ path = [IO.Path]::GetRelativePath($PackageRoot, $_.FullName).Replace("\", "/"); size = $_.Length; sha256 = Sha256 $_.FullName }
    })
    [ordered]@{ schema_version = 1; artifact_name = $ArtifactName; source_commit = $SourceCommit; files = $files } |
        ConvertTo-Json -Depth 16 | Set-Content (Join-Path $PackageRoot "portable-manifest.json") -Encoding utf8NoBOM
} finally {
    if (Test-Path -LiteralPath $scratch) { Remove-Item -LiteralPath $scratch -Recurse -Force }
}

Write-Host "V portable package ready: $PackageRoot"
