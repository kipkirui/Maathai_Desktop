#!/usr/bin/env bash
# Extra llama-bench sweeps beyond scripts/benchmark_tune_wsl.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/tools/llama-linux/llama-b9777:${LD_LIBRARY_PATH:-}"
export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
BENCH="$ROOT/tools/llama-linux/llama-bench"
MODEL="${MAATHAI_NATIVE_MODEL:-$HOME/maathai/model/qwen2.5-3b-instruct-q4_k_m.gguf}"

if [[ ! -f "$MODEL" ]]; then
  MODEL="$ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"
fi

extract_tps() {
  python3 -c '
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get("n_gen", 0) > 0)
print("%.2f" % tg["avg_ts"])
'
}

run_bench() {
  local label="$1"
  shift
  echo -n "  $label ... "
  local tps
  tps=$("$BENCH" "$@" --output json 2>/dev/null | extract_tps)
  echo "${tps} t/s"
}

echo "=== Extra flag sweep ==="
echo "Model: $MODEL"
echo ""

echo "--- Flash attention / KV cache / ubatch (t=4 -b 2048) ---"
run_bench "baseline"        -m "$MODEL" -p 512 -n 128 -t 4 -b 2048
run_bench "flash-attn on"   -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -fa on
run_bench "flash-attn off"  -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -fa off
run_bench "ctk/v q8_0"      -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -ctk q8_0 -ctv q8_0
run_bench "ctk/v q4_0"      -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -ctk q4_0 -ctv q4_0
run_bench "ubatch 256"      -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -ub 256
run_bench "ubatch 512"      -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -ub 512
echo ""

echo "--- Thread split (gen vs batch) ---"
run_bench "t=4 tb=4" -m "$MODEL" -p 512 -n 128 -t 4 -tb 4 -b 2048
run_bench "t=4 tb=2" -m "$MODEL" -p 512 -n 128 -t 4 -tb 2 -b 2048
run_bench "t=2 tb=4" -m "$MODEL" -p 512 -n 128 -t 2 -tb 4 -b 2048
run_bench "t=2 tb=2" -m "$MODEL" -p 512 -n 128 -t 2 -tb 2 -b 2048
echo ""

echo "Done."
