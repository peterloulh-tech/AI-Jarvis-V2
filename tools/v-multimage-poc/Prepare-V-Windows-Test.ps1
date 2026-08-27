[CmdletBinding()]
param(
    [string]$PythonVersion = "3.11.9",
    [switch]$ForceDownload
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Downloads = Join-Path $Root "_downloads"
$RuntimeRoot = Join-Path $Root "Runtime"
$PythonRoot = Join-Path $RuntimeRoot "python"

$Artifacts = @(
    @{
        Name = "llama-b10369-bin-win-cuda-12.4-x64.zip"
        Url = "https://github.com/ggml-org/llama.cpp/releases/download/b10369/llama-b10369-bin-win-cuda-12.4-x64.zip"
        Size = 250748190
        Sha256 = "5eca96bb069281deda8e882843193a605a7b0687c659c6b4123715a4f1642642"
        Destination = (Join-Path $RuntimeRoot "llama")
    },
    @{
        Name = "cudart-llama-bin-win-cuda-12.4-x64.zip"
        Url = "https://github.com/ggml-org/llama.cpp/releases/download/b10369/cudart-llama-bin-win-cuda-12.4-x64.zip"
        Size = 391443627
        Sha256 = "8c79a9b226de4b3cacfd1f83d24f962d0773be79f1e7b75c6af4ded7e32ae1d6"
        Destination = (Join-Path $RuntimeRoot "llama")
    },
    @{
        Name = "python-$PythonVersion-embed-amd64.zip"
        Url = "https://www.python.org/ftp/python/$PythonVersion/python-$PythonVersion-embed-amd64.zip"
        Size = 0
        Sha256 = "UNLOCKED"
        Destination = $PythonRoot
    }
)

function Test-Artifact {
    param([hashtable]$Artifact, [string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    if ($Artifact.Size -gt 0 -and (Get-Item -LiteralPath $Path).Length -ne $Artifact.Size) { return $false }
    if ($Artifact.Sha256 -eq "UNLOCKED") { return $true }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Artifact.Sha256
}

New-Item -ItemType Directory -Force -Path $Downloads, $RuntimeRoot | Out-Null
foreach ($Artifact in $Artifacts) {
    $Archive = Join-Path $Downloads $Artifact.Name
    if ($ForceDownload -or -not (Test-Artifact -Artifact $Artifact -Path $Archive)) {
        Write-Host "Downloading $($Artifact.Name)"
        Invoke-WebRequest -Uri $Artifact.Url -OutFile $Archive
    }
    if (-not (Test-Artifact -Artifact $Artifact -Path $Archive)) {
        throw "Artifact verification failed: $($Artifact.Name)"
    }
    if ($ForceDownload -or -not (Test-Path -LiteralPath $Artifact.Destination)) {
        New-Item -ItemType Directory -Force -Path $Artifact.Destination | Out-Null
        Expand-Archive -LiteralPath $Archive -DestinationPath $Artifact.Destination -Force
    }
}

$Server = Get-ChildItem -Path (Join-Path $RuntimeRoot "llama") -Filter "llama-server.exe" -Recurse |
    Select-Object -First 1
if ($null -eq $Server) { throw "llama-server.exe was not found after extraction" }
if (-not (Test-Path -LiteralPath (Join-Path $PythonRoot "python.exe"))) {
    throw "Embedded Python was not found after extraction"
}

$State = @{
    schema_version = 1
    prepared_at = (Get-Date).ToUniversalTime().ToString("o")
    server = $Server.FullName
    python = (Join-Path $PythonRoot "python.exe")
    artifacts = $Artifacts | ForEach-Object {
        @{
            name = $_.Name
            sha256 = $_.Sha256
            path = (Join-Path $Downloads $_.Name)
        }
    }
}
$State | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Root "prepared-runtime.json") -Encoding utf8
Write-Host "Prepared server: $($Server.FullName)"
