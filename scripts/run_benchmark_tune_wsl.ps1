# Sweep llama-bench thread/batch/mmap settings in WSL (competition tuning).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run_benchmark_tune_wsl.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$winPath = ($RepoRoot -replace '\\', '/')
if ($winPath -match '^([A-Za-z]):(.*)$') {
    $wslRepo = "/mnt/$($Matches[1].ToLower())$($Matches[2])"
} else {
    throw "Unexpected repo path: $RepoRoot"
}

Write-Host "Maathai TPS tuning via WSL (llama-bench sweep)" -ForegroundColor Cyan
wsl -d Ubuntu-22.04 -u root bash -lc "cd '$wslRepo' && sed -i 's/\r$//' scripts/benchmark_tune_wsl.sh && bash scripts/benchmark_tune_wsl.sh"
