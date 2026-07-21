#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/tools/llama-linux/llama-b9777:${LD_LIBRARY_PATH:-}"
export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
BENCH="$ROOT/tools/llama-linux/llama-bench"
MODEL="${MAATHAI_NATIVE_MODEL:-$HOME/maathai/model/qwen2.5-3b-instruct-q4_k_m.gguf}"
echo "Confirm: -t 4 -b 2048 -fa on"
"$BENCH" -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -fa on --output json 2>/dev/null | python3 -c '
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get("n_gen", 0) > 0)
print("%.2f t/s" % tg["avg_ts"])
'
