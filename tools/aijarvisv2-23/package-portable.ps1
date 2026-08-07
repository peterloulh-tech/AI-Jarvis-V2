#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$SourceCommit,
    [Parameter(Mandatory = $true)][string]$CudaVersion,
    [string]$ArtifactName = "AIJARVISV2-23-windows-x64-cuda-portable"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$requiredFiles = @(
    "bin\aijarvisv2-task23-poc.exe",
    "run-aijarvisv2-23.ps1",
    "gpu-capacity.ps1",
    "README.md",
    "model-provenance.template.json",
    "o-in-07-manifest.template.json",
    "templates\performance-sample-record.csv",
    "templates\resource-trend-record.csv",
    "templates\reliability-event-record.csv",
    "licenses\llama.cpp-omni\LICENSE.llama.cpp-omni",
    "licenses\llama.cpp-omni\NOTICE.md"
)
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relativePath) -PathType Leaf)) {
        throw "Portable package is missing $relativePath"
    }
}

$cudaEulaCandidates = @(
    (Join-Path $env:CUDA_PATH "EULA.txt"),
    (Join-Path $env:CUDA_PATH "doc\EULA.txt")
)
$cudaEula = $cudaEulaCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $cudaEula) { throw "CUDA EULA was not found under CUDA_PATH" }
Copy-Item -LiteralPath $cudaEula -Destination (Join-Path $PackageRoot "licenses\NVIDIA-CUDA-EULA.txt") -Force

$dlls = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot "bin") -Filter "*.dll" -File)
if (@($dlls | Where-Object Name -Like "cublas64_*.dll").Count -eq 0 -or
    @($dlls | Where-Object Name -Like "cublasLt64_*.dll").Count -eq 0) {
    throw "Portable package does not contain the required cuBLAS runtime DLLs"
}

$forbidden = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {
    $_.Extension -in @(".gguf", ".safetensors", ".wav", ".jpg", ".jpeg", ".png") -or
    $_.Name -in @("git.exe", "cmake.exe", "nvcc.exe", "python.exe", "node.exe")
})
if ($forbidden.Count -ne 0) {
    throw "Portable package contains forbidden model, input, or development files: $($forbidden.Name -join ', ')"
}

$toolRoot = Join-Path $RepositoryRoot "tools\aijarvisv2-23"
$buildManifest = [ordered]@{
    schema_version = 1
    artifact_name = $ArtifactName
    source_commit = $SourceCommit
    architecture = "windows-x64"
    cuda_toolkit_version = $CudaVersion
    runtime_revision = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"
    runtime_patch_sha256 = "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e"
    runtime_license_sha256 = "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"
    harness_source_sha256 = Get-Sha256 -Path (Join-Path $toolRoot "poc_main.cpp")
    cmake_source_sha256 = Get-Sha256 -Path (Join-Path $toolRoot "CMakeLists.txt")
    executable_sha256 = Get-Sha256 -Path (Join-Path $PackageRoot "bin\aijarvisv2-task23-poc.exe")
    runtime_dlls = @($dlls | Sort-Object Name | ForEach-Object {
        [ordered]@{ path = "bin/$($_.Name)"; size = $_.Length; sha256 = Get-Sha256 -Path $_.FullName }
    })
    models_included = 0
    o_in_07_assets_included = 0
    generated_at = (Get-Date).ToUniversalTime().ToString("o")
}
$buildManifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $PackageRoot "portable-build-manifest.json") -Encoding UTF8

$files = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object Name -ne "portable-manifest.json" | Sort-Object FullName | ForEach-Object {
    $relative = [IO.Path]::GetRelativePath($PackageRoot, $_.FullName).Replace("\", "/")
    [ordered]@{ path = $relative; size = $_.Length; sha256 = Get-Sha256 -Path $_.FullName }
})
$manifest = [ordered]@{
    schema_version = 1
    artifact_name = $ArtifactName
    source_commit = $SourceCommit
    runtime_revision = $buildManifest.runtime_revision
    runtime_patch_sha256 = $buildManifest.runtime_patch_sha256
    runtime_license_sha256 = $buildManifest.runtime_license_sha256
    portable_run_minimum = "NVIDIA GPU with at least 12GB nominal VRAM"
    task23_formal_minimum = "NVIDIA GPU with at least 16GB nominal VRAM"
    files = $files
}
$manifest | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath (Join-Path $PackageRoot "portable-manifest.json") -Encoding UTF8

Write-Host "Portable package ready: $PackageRoot"
