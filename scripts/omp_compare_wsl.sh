#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/tools/llama-linux/llama-b9777:${LD_LIBRARY_PATH:-}"
BENCH="$ROOT/tools/llama-linux/llama-bench"
MODEL="$ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"

run_one() {
  local label="$1"
  shift
  echo -n "$label: "
  "$BENCH" -m "$MODEL" -p 512 -n 128 --output json 2>/dev/null | python3 -c "
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get('n_gen', 0) > 0)
print(f\"{tg['avg_ts']:.2f} t/s\")
"
}

echo "=== OMP thread limit comparison ==="
run_one "default (no OMP export)"
export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
run_one "OMP_NUM_THREADS=4"
