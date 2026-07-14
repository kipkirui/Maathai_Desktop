# Run Maathai Desktop on Windows and capture Flutter verbose output to a file.
# App-level logs (chat, llama-server, model load) are written separately to:
#   %APPDATA%\com.example\maathai_desktop\logs\maathai.log
#
# Usage:
#   .\scripts\run_with_logs.ps1
#   .\scripts\run_with_logs.ps1 -Release

param(
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $repoRoot "logs"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$flutterLog = Join-Path $logDir "flutter-run-$timestamp.log"
$appLogHint = Join-Path $env:APPDATA "com.example\maathai_desktop\logs\maathai.log"

Write-Host ""
Write-Host "Maathai Desktop — debug run with log capture" -ForegroundColor Cyan
Write-Host "  Flutter verbose log : $flutterLog"
Write-Host "  App log (Dart)        : $appLogHint"
Write-Host ""
Write-Host "Reproduce the hang/crash, then inspect both files."
Write-Host "Tail app log:  Get-Content '$appLogHint' -Wait -Tail 40"
Write-Host ""

Push-Location $repoRoot
try {
    if ($Release) {
        flutter run -d windows --release -v 2>&1 | Tee-Object -FilePath $flutterLog
    } else {
        flutter run -d windows -v 2>&1 | Tee-Object -FilePath $flutterLog
    }
} finally {
    Pop-Location
}
