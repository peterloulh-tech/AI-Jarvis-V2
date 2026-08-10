#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$RuntimeSourceRoot,
    [Parameter(Mandatory = $true)][string]$RuntimeBuildRoot,
    [Parameter(Mandatory = $true)][string]$AdapterBuildRoot,
    [Parameter(Mandatory = $true)][string]$CudaLicenseRoot,
    [Parameter(Mandatory = $true)][string]$SourceCommit,
    [string]$ArtifactName = "AIJARVISV2-93-o-official-reference-windows-x64-cuda"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
foreach ($name in @("RepositoryRoot", "PackageRoot", "RuntimeSourceRoot", "RuntimeBuildRoot", "AdapterBuildRoot", "CudaLicenseRoot")) {
    Set-Variable -Name $name -Value ([IO.Path]::GetFullPath((Get-Variable -Name $name -ValueOnly)))
}

function Find-OneFile {
    param([Parameter(Mandatory = $true)][string]$Root, [Parameter(Mandatory = $true)][string]$Name)
    $matches = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter $Name)
    if ($matches.Count -ne 1) { throw "expected exactly one $Name under $Root, found $($matches.Count)" }
    return $matches[0].FullName
}

function Copy-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Destination)
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "missing package source: $Source" }
    New-Item -ItemType Directory -Path (Split-Path -Parent $Destination) -Force | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Get-LowerSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

New-Item -ItemType Directory -Path (Join-Path $PackageRoot "bin") -Force | Out-Null
$serverSource = Find-OneFile -Root $RuntimeBuildRoot -Name "llama-omni-server.exe"
$adapterSource = Find-OneFile -Root $AdapterBuildRoot -Name "aijarvisv2-o-official-adapter.exe"
Copy-RequiredFile -Source $serverSource -Destination (Join-Path $PackageRoot "bin\llama-omni-server.exe")
Copy-RequiredFile -Source $adapterSource -Destination (Join-Path $PackageRoot "bin\aijarvisv2-o-official-adapter.exe")

$toolRoot = Join-Path $RepositoryRoot "tools\o-official-reference"
foreach ($file in @("run-o-official-reference.ps1", "official-config.json", "upstream-lock.json", "README.md", "package-manifest.json")) {
    Copy-RequiredFile -Source (Join-Path $toolRoot $file) -Destination (Join-Path $PackageRoot $file)
}
$fixtureSource = Join-Path $RepositoryRoot "tools\aijarvisv2-23\AIJARVISV2-23-NEXT-WIN-DELTA\O-IN-07-1HZ"
foreach ($file in @("manifest.json", "gold.json", "authorization.md")) {
    Copy-RequiredFile -Source (Join-Path $fixtureSource $file) `
        -Destination (Join-Path $PackageRoot "fixture\O-IN-07\$file")
}
Copy-RequiredFile -Source (Join-Path $RuntimeSourceRoot "LICENSE") `
    -Destination (Join-Path $PackageRoot "licenses\llama.cpp-omni\LICENSE")
if (-not (Test-Path -LiteralPath (Join-Path $RuntimeSourceRoot "licenses") -PathType Container)) {
    throw "pinned llama.cpp-omni licenses directory is missing"
}
Copy-Item -LiteralPath (Join-Path $RuntimeSourceRoot "licenses") `
    -Destination (Join-Path $PackageRoot "licenses\llama.cpp-omni\upstream") -Recurse -Force
Copy-RequiredFile -Source (Join-Path $RepositoryRoot "LICENSE") `
    -Destination (Join-Path $PackageRoot "licenses\AI-Jarvis-V2\LICENSE")
foreach ($file in @("cuda_cudart-LICENSE.txt", "libcublas-LICENSE.txt")) {
    Copy-RequiredFile -Source (Join-Path $CudaLicenseRoot $file) `
        -Destination (Join-Path $PackageRoot "licenses\NVIDIA-CUDA\$file")
}

$binaryDirectories = @(
    (Split-Path -Parent $serverSource),
    (Join-Path $env:CUDA_PATH "bin")
)
foreach ($pattern in @("*.dll")) {
    foreach ($directory in $binaryDirectories) {
        if (Test-Path -LiteralPath $directory -PathType Container) {
            Get-ChildItem -LiteralPath $directory -File -Filter $pattern | ForEach-Object {
                if ($_.Name -match "^(ggml|llama|mtmd|cudart64_|cublas64_|cublasLt64_)") {
                    Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $PackageRoot "bin\$($_.Name)") -Force
                }
            }
        }
    }
}
foreach ($pattern in @("cudart64_*.dll", "cublas64_*.dll", "cublasLt64_*.dll")) {
    if (@(Get-ChildItem -LiteralPath (Join-Path $PackageRoot "bin") -File -Filter $pattern).Count -eq 0) {
        throw "portable package is missing $pattern"
    }
}

$expected = Get-Content -LiteralPath (Join-Path $PackageRoot "package-manifest.json") -Raw -Encoding UTF8 | ConvertFrom-Json
foreach ($relative in @($expected.required_files)) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot ([string]$relative).Replace("/", "\")) -PathType Leaf)) {
        throw "portable package is missing $relative"
    }
}
$forbidden = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {
    $_.Extension -in @(".gguf", ".safetensors", ".wav", ".jpg", ".jpeg", ".png")
})
if ($forbidden.Count -ne 0) { throw "models/media must remain external: $($forbidden.Name -join ', ')" }

$files = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path = [IO.Path]::GetRelativePath($PackageRoot, $_.FullName).Replace("\", "/")
        size = $_.Length
        sha256 = Get-LowerSha256 -Path $_.FullName
    }
})
$portableManifest = [ordered]@{
    schema_version = 1
    artifact_name = $ArtifactName
    source_commit = $SourceCommit
    runtime_commit = "09f5c3f1b484759f17b06fc63574f749c89c8761"
    demo_commit = "d0a002093615b7f1d4d0f87a03fc01cb39bef3f6"
    cuda_toolkit_version = "12.8.1"
    models_included = 0
    o_in_07_media_included = 0
    files = $files
}
$portableManifest | ConvertTo-Json -Depth 16 | Set-Content `
    -LiteralPath (Join-Path $PackageRoot "portable-manifest.json") -Encoding utf8NoBOM
Write-Host "Official-First package ready: $PackageRoot"
