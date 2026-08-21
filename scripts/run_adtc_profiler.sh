#!/usr/bin/env bash
# Run adtc-profiler (participant mode) — same tool judges use for TPS + RAM.
# Requires: model GGUF, llama-bench in tools/llama-linux/, adtc-profiler in .venv-wsl
# Setup once: bash scripts/wsl_profiler_setup.sh
# Usage:
#   bash scripts/run_adtc_profiler.sh           # smoke (skip accuracy) — fast iterate
#   bash scripts/run_adtc_profiler.sh --full    # Gate 1 final (accuracy ON)
# Prefer: bash scripts/gate1_verify.sh

set -euo pipefail

FULL=0
for arg in "$@"; do
  case "$arg" in
    --full) FULL=1 ;;
    -h|--help)
      sed -n '2,10p' "$0"
      exit 0
      ;;
  esac
done

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
if [[ -d "$LLAMA_DIR/llama-b10509" ]]; then
  export LD_LIBRARY_PATH="$LLAMA_DIR/llama-b10509${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi
for d in "$VENV"/lib/python*/site-packages/lib; do
  if [[ -e "$d/libggml-cpu.so.0" || -e "$d/libggml-cpu.so" ]]; then
    export GGML_BACKEND_DIR="$d"
    export LD_LIBRARY_PATH="$d${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    break
  fi
done
cd "$REPO_ROOT"

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
export MKL_NUM_THREADS=4

PROFILER_CMD=(adtc-profiler run)
if command -v taskset >/dev/null 2>&1; then
  PROFILER_CMD=(taskset -c 0-3 adtc-profiler run)
fi

echo ""
if [[ "$FULL" -eq 1 ]]; then
  echo "→ adtc-profiler (participant, FULL / accuracy ON) — Gate 1 artifact..."
  echo "   Can take several hours (ARC-Easy limit=50)."
  python3 "$SCRIPT_DIR/patch_adtc_accuracy_runner.py"
  "${PROFILER_CMD[@]}" \
    --submission . \
    --mode participant \
    --output submission.json
else
  echo "→ adtc-profiler (participant, --skip-accuracy) — smoke benchmark..."
  echo "   Uses llama-bench -p 512 -n 128 (same as competition audit)."
  echo "   Takes ~3–8 minutes. For Gate 1 final: re-run with --full"
  "${PROFILER_CMD[@]}" \
    --submission . \
    --mode participant \
    --output submission.json \
    --skip-accuracy
fi

python3 <<'PY'
import json
import sys
from pathlib import Path

p = Path("submission.json")
s = json.loads(p.read_text())
ram = s["memory"]["peak_rss_mb"]
tps = s["throughput"]["tokens_per_second_generation"]
ftl = s["throughput"]["first_token_latency_ms"]
acc = s.get("accuracy") or []
seff = (7168 - ram) / 7168 * 100
sperf = min(tps / 15, 1.0) * 100

print()
print("=== adtc-profiler results ===")
print(f"Peak RAM     : {ram:.0f} MB  (limit 7168)  -> Seff {seff:.1f}")
print(f"Gen TPS      : {tps:.2f}       (ref 15 prov) -> Sperf {sperf:.1f}")
print(f"First token  : {ftl:.0f} ms")
print(f"Accuracy     : {len(acc)} entries")
print(f"OS           : {s['environment']['os']}")
print(f"Output       : {p.resolve()}")
print()
print("=== Competition gates ===")
ram_ok = ram < 7168
tps_target = tps >= 15.0
print(f"  RAM < 7168 MB (hard)    : {'PASS' if ram_ok else 'FAIL — DISQUALIFICATION RISK'}")
print(f"  TPS >= 15 (provisional) : {'PASS' if tps_target else 'below target (scoring only)'}")
print(f"  Accuracy present        : {'PASS' if acc else 'MISSING — run with --full for Gate 1'}")
if not tps_target:
    print("  Note: WSL/dev laptops often report ~8–10 t/s; audit i5 native Ubuntu is faster.")
    print("  Official Sperf uses TPSact/TPSmax across submissions.")

if not ram_ok:
    sys.exit(1)
PY
