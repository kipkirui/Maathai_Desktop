# Installs llama-server for Maathai Desktop on Windows (CPU x64).
# Run from repo root: powershell -ExecutionPolicy Bypass -File scripts/install_llama_server_windows.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$ToolsDir = Join-Path $RepoRoot "tools\llama"
$ZipPath = Join-Path $RepoRoot "tools\llama-win.zip"

Write-Host "=== Maathai Desktop — llama-server (Windows) ===" -ForegroundColor Green

$release = Invoke-RestMethod -Uri "https://api.github.com/repos/ggml-org/llama.cpp/releases/latest" `
    -Headers @{ "User-Agent" = "MaathaiDesktop" }
$asset = $release.assets | Where-Object { $_.name -match "bin-win-cpu-x64\.zip$" } | Select-Object -First 1
if (-not $asset) {
    throw "Could not find Windows CPU x64 binary in release $($release.tag_name)"
}

Write-Host "Release: $($release.tag_name)"
Write-Host "Downloading: $($asset.name)"

New-Item -ItemType Directory -Force -Path (Split-Path $ToolsDir) | Out-Null
Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $ZipPath -UseBasicParsing

if (Test-Path $ToolsDir) { Remove-Item -Recurse -Force $ToolsDir }
Expand-Archive -Path $ZipPath -DestinationPath $ToolsDir -Force
Remove-Item $ZipPath -Force

$server = Join-Path $ToolsDir "llama-server.exe"
if (-not (Test-Path $server)) {
    throw "llama-server.exe not found after extract"
}

Write-Host ""
Write-Host "Installed: $server" -ForegroundColor Green
Write-Host ""
Write-Host "Maathai Desktop will auto-detect tools\llama\llama-server.exe."
Write-Host "Optional — add to user PATH:"
Write-Host "  setx PATH `"%PATH%;$ToolsDir`""

& $server --version 2>&1 | Select-Object -First 3
