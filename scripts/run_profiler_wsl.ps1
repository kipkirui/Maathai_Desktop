# Run ADTC profiler inside Ubuntu 22.04 WSL (competition-like environment).
# Requires: Ubuntu-22.04 WSL distro, model at model/qwen2.5-3b-instruct-q4_k_m.gguf
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File scripts/run_profiler_wsl.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$distroList = (wsl -l -v 2>&1 | Out-String) -replace "`0", ""
if ($distroList -notmatch 'Ubuntu-22.04') {
    Write-Host "Ubuntu-22.04 not found. Install with:" -ForegroundColor Yellow
    Write-Host "  wsl --install -d Ubuntu-22.04"
    exit 1
}

Write-Host ""
Write-Host "Maathai Desktop - ADTC profiler via WSL Ubuntu 22.04" -ForegroundColor Cyan
Write-Host "Repo (Windows): $RepoRoot"
Write-Host ""

$winPath = ($RepoRoot -replace '\\', '/')
if ($winPath -match '^([A-Za-z]):(.*)$') {
    $drive = $Matches[1].ToLower()
    $rest = $Matches[2]
    $wslRepo = "/mnt/$drive$rest"
} else {
    throw "Unexpected repo path: $RepoRoot"
}

wsl -d Ubuntu-22.04 -u root bash -lc "cd '$wslRepo' && sed -i 's/\r$//' scripts/wsl_profiler_setup.sh && bash scripts/wsl_profiler_setup.sh"

Write-Host ""
Write-Host "Done." -ForegroundColor Green
Write-Host (Join-Path $RepoRoot 'submission.json')
