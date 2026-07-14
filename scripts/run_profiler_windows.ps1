# Run ADTC profiler on Windows (participant mode).
# Requires: pip install "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"
#           tools/llama/llama-bench.exe (same zip as llama-server — run install_llama_server_windows.ps1)
#
# Usage (from repo root):
#   powershell -ExecutionPolicy Bypass -File scripts/run_profiler_windows.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = Split-Path -Parent $PSScriptRoot
$LlamaDir = Join-Path $RepoRoot "tools\llama"
$Bench = Join-Path $LlamaDir "llama-bench.exe"
$Model = Join-Path $RepoRoot "model\qwen2.5-3b-instruct-q4_k_m.gguf"
$Out = Join-Path $RepoRoot "submission.json"
$Profiler = Join-Path $env:APPDATA "Python\Python314\Scripts\adtc-profiler.exe"

if (-not (Test-Path $Model)) {
    throw "Model not found: $Model`nRun download_model.sh (WSL) or download manually."
}
if (-not (Test-Path $Bench)) {
    throw "llama-bench.exe not found. Run: scripts/install_llama_server_windows.ps1"
}
if (-not (Test-Path $Profiler)) {
    throw "adtc-profiler not installed. Run: pip install `"git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git`""
}

chcp 65001 | Out-Null
$env:PYTHONIOENCODING = "utf-8"
$env:PYTHONUTF8 = "1"
$env:PATH = "$LlamaDir;$env:PATH"

Write-Host ""
Write-Host "ADTC profiler — participant mode (Windows)" -ForegroundColor Cyan
Write-Host "  Model   : $Model"
Write-Host "  Output  : $Out"
Write-Host "  llama   : $Bench"
Write-Host ""

Push-Location $RepoRoot
try {
    & $Profiler run --submission . --mode participant --output submission.json --skip-accuracy
} finally {
    Pop-Location
}

if (Test-Path $Out) {
    Write-Host ""
    python -c @"
import json
with open(r'$Out', encoding='utf-8') as f:
    s = json.load(f)
ram = s['memory']['peak_rss_mb']
tps = s['throughput']['tokens_per_second_generation']
ftl = s['throughput']['first_token_latency_ms']
seff = (7168 - ram) / 7168 * 100
sperf = min(tps / 15, 1.0) * 100
print(f'Peak RAM     : {ram:.0f} MB  (limit 7168)  -> Seff {seff:.1f}')
print(f'Gen TPS      : {tps:.2f}       (ref 15)      -> Sperf {sperf:.1f}')
print(f'First token  : {ftl:.0f} ms')
print(f'OS           : {s[\"environment\"][\"os\"]}')
"@
}
