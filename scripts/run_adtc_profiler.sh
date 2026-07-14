#!/usr/bin/env bash
# Run adtc-profiler (participant mode) — same tool judges use for TPS + RAM.
# Requires: model GGUF, llama-bench in tools/llama-linux/, adtc-profiler in .venv-wsl
# Setup once: bash scripts/wsl_profiler_setup.sh
# Usage:      bash scripts/run_adtc_profiler.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLAMA_DIR="$REPO_ROOT/tools/llama-linux"
VENV="$REPO_ROOT/.venv-wsl"
MODEL="$REPO_ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"

if [[ ! -f "$MODEL" ]]; then
  echo "Model missing: $MODEL"
  echo "Run: bash download_model.sh"
  exit 1
fi

if [[ ! -x "$LLAMA_DIR/llama-bench" ]]; then
  echo "llama-bench not found. Running one-time profiler setup..."
  sed -i 's/\r$//' "$SCRIPT_DIR/wsl_profiler_setup.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/wsl_profiler_setup.sh" --install-only
fi

if [[ ! -x "$VENV/bin/adtc-profiler" ]]; then
  echo "adtc-profiler not found in .venv-wsl. Running setup..."
  sed -i 's/\r$//' "$SCRIPT_DIR/wsl_profiler_setup.sh" 2>/dev/null || true
  bash "$SCRIPT_DIR/wsl_profiler_setup.sh" --install-only
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
export PATH="$LLAMA_DIR:$PATH"
cd "$REPO_ROOT"

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
export MKL_NUM_THREADS=4

PROFILER_CMD=(adtc-profiler run)
if command -v taskset >/dev/null 2>&1; then
  PROFILER_CMD=(taskset -c 0-3 adtc-profiler run)
fi

echo ""
echo "→ adtc-profiler (participant, --skip-accuracy) — judge-like benchmark..."
echo "   Uses llama-bench -p 512 -n 128 (same as competition audit)."
echo "   Takes ~3–8 minutes."
"${PROFILER_CMD[@]}" \
  --submission . \
  --mode participant \
  --output submission.json \
  --skip-accuracy

python3 <<'PY'
import json
import sys
from pathlib import Path

p = Path("submission.json")
s = json.loads(p.read_text())
ram = s["memory"]["peak_rss_mb"]
tps = s["throughput"]["tokens_per_second_generation"]
ftl = s["throughput"]["first_token_latency_ms"]
seff = (7168 - ram) / 7168 * 100
sperf = min(tps / 15, 1.0) * 100

print()
print("=== adtc-profiler results ===")
print(f"Peak RAM     : {ram:.0f} MB  (limit 7168)  -> Seff {seff:.1f}")
print(f"Gen TPS      : {tps:.2f}       (ref 15)      -> Sperf {sperf:.1f}")
print(f"First token  : {ftl:.0f} ms")
print(f"OS           : {s['environment']['os']}")
print(f"Output       : {p.resolve()}")
print()
print("=== Competition gates ===")
ram_ok = ram < 7168
tps_target = tps >= 15.0
print(f"  RAM < 7168 MB (hard)    : {'PASS' if ram_ok else 'FAIL — DISQUALIFICATION RISK'}")
print(f"  TPS >= 15 (Sperf=100)   : {'PASS' if tps_target else 'below target (scoring only)'}")
if not tps_target:
    print("  Note: WSL dev laptops often report ~9–10 t/s; audit i5 native Ubuntu is faster.")

if not ram_ok:
    sys.exit(1)
PY
