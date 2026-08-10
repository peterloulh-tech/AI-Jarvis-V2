#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$PackageRoot,
    [Parameter(Mandatory = $true)][string]$SourceCommit,
    [Parameter(Mandatory = $true)][string]$CudaVersion,
    [Parameter(Mandatory = $true)][string]$CudaLicenseRoot,
    [string]$ArtifactName = "AIJARVISV2-92-o-reference-harness-v2-windows-x64-cuda"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$PackageRoot = [IO.Path]::GetFullPath($PackageRoot)
$CudaLicenseRoot = [IO.Path]::GetFullPath($CudaLicenseRoot)

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$cudaLicenses = @(
    [pscustomobject]@{
        component="cuda_cudart"
        version="12.8.90"
        source="cuda_cudart-LICENSE.txt"
        package_path="licenses\NVIDIA-CUDA\cuda_cudart-LICENSE.txt"
        sha256="e2c71babfd18a8e69542dd7e9ca018f9caa438094001a58e6bc4d8c999bf0d07"
    },
    [pscustomobject]@{
        component="libcublas"
        version="12.8.4.1"
        source="libcublas-LICENSE.txt"
        package_path="licenses\NVIDIA-CUDA\libcublas-LICENSE.txt"
        sha256="e2c71babfd18a8e69542dd7e9ca018f9caa438094001a58e6bc4d8c999bf0d07"
    }
)
foreach ($license in $cudaLicenses) {
    $source = Join-Path $CudaLicenseRoot $license.source
    if ((Get-Sha256 -Path $source) -ne $license.sha256) {
        throw "CUDA redistributable license mismatch: $($license.component)"
    }
    $destination = Join-Path $PackageRoot $license.package_path
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

$required = @(
    "bin\o-reference-harness-v2.exe", "run-o-reference-harness-v2.ps1",
    "runner-config.json", "README.md", "gpu-capacity.ps1", "model-provenance.template.json",
    "profiles\official-runtime-reference.json", "profiles\v2-contract.json",
    "fixtures\official-1hz\manifest.json", "fixtures\legacy-3s-replay\manifest.json",
    "licenses\llama.cpp-omni\LICENSE.llama.cpp-omni", "licenses\llama.cpp-omni\NOTICE.md",
    "licenses\NVIDIA-CUDA\cuda_cudart-LICENSE.txt", "licenses\NVIDIA-CUDA\libcublas-LICENSE.txt"
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $PackageRoot $relative) -PathType Leaf)) {
        throw "portable package is missing $relative"
    }
}

$dlls = @(Get-ChildItem -LiteralPath (Join-Path $PackageRoot "bin") -Filter "*.dll" -File)
foreach ($pattern in @("cudart64_*.dll", "cublas64_*.dll", "cublasLt64_*.dll")) {
    if (@($dlls | Where-Object Name -Like $pattern).Count -eq 0) { throw "missing runtime DLL: $pattern" }
}
$forbidden = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object {
    $_.Extension -in @(".gguf", ".safetensors") -or
    $_.Name -in @("git.exe", "cmake.exe", "nvcc.exe", "python.exe", "node.exe")
})
if ($forbidden.Count -ne 0) { throw "portable package contains model or development files" }

$toolRoot = Join-Path $RepositoryRoot "tools\o-reference-harness-v2"
$buildManifest = [ordered]@{
    schema_version = 1
    artifact_name = $ArtifactName
    source_commit = $SourceCommit
    architecture = "windows-x64"
    cuda_toolkit_version = $CudaVersion
    runtime_revision = "b9d15b83ee353b2eaeee4d9318c98a35a1347486"
    runtime_patch_sha256 = "cc8b1c4abb62a736cf190da3fdb1c29a260130f4b6cb3651696479703150783e"
    runtime_license_sha256 = "94f29bbed6a22c35b992c5c6ebf0e7c92f13b836b90f36f461c9cf2f0f1d010d"
    cuda_redistributable_licenses = @($cudaLicenses | ForEach-Object {
        [ordered]@{
            component = $_.component
            version = $_.version
            path = $_.package_path.Replace("\", "/")
            sha256 = $_.sha256
        }
    })
    executable_sha256 = Get-Sha256 -Path (Join-Path $PackageRoot "bin\o-reference-harness-v2.exe")
    cmake_source_sha256 = Get-Sha256 -Path (Join-Path $toolRoot "CMakeLists.txt")
    models_included = 0
    deterministic_fixture_profiles = @("official-1hz", "legacy-3s-replay")
    runtime_dlls = @($dlls | Sort-Object Name | ForEach-Object {
        [ordered]@{ path="bin/$($_.Name)"; size=$_.Length; sha256=Get-Sha256 -Path $_.FullName }
    })
}
$buildManifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PackageRoot "portable-build-manifest.json") -Encoding UTF8

$files = @(Get-ChildItem -LiteralPath $PackageRoot -Recurse -File | Where-Object Name -ne "portable-manifest.json" | Sort-Object FullName | ForEach-Object {
    [ordered]@{
        path = [IO.Path]::GetRelativePath($PackageRoot, $_.FullName).Replace("\", "/")
        size = $_.Length
        sha256 = Get-Sha256 -Path $_.FullName
    }
})
[ordered]@{
    schema_version = 1
    artifact_name = $ArtifactName
    source_commit = $SourceCommit
    runtime_revision = $buildManifest.runtime_revision
    runtime_patch_sha256 = $buildManifest.runtime_patch_sha256
    runtime_license_sha256 = $buildManifest.runtime_license_sha256
    model_strategy = "external locked three-file no-TTS"
    files = $files
} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $PackageRoot "portable-manifest.json") -Encoding UTF8
