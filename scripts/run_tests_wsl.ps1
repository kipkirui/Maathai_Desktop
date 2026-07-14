# Run full pytest on Ubuntu 22.04 WSL (judge-like environment).
# Usage: powershell -ExecutionPolicy Bypass -File scripts/run_tests_wsl.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot

$winPath = ($RepoRoot -replace '\\', '/')
if ($winPath -match '^([A-Za-z]):(.*)$') {
    $wslRepo = "/mnt/$($Matches[1].ToLower())$($Matches[2])"
} else {
    throw "Unexpected repo path: $RepoRoot"
}

Write-Host ""
Write-Host "Maathai Desktop — judge-like tests (Ubuntu 22.04 WSL)" -ForegroundColor Cyan
Write-Host ""

wsl -d Ubuntu-22.04 -u root bash -c "cd '$wslRepo'; sed -i 's/\r$//' scripts/run_tests_wsl.sh; bash scripts/run_tests_wsl.sh"
