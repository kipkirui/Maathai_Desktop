#!/usr/bin/env bash
# Quick competition-style llama-bench (same args as adtc-profiler).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/tools/llama-linux/llama-b9777:${LD_LIBRARY_PATH:-}"
export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
BENCH="$ROOT/tools/llama-linux/llama-bench"
MODEL="$ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"
echo "Competition command: llama-bench -m model -p 512 -n 128"
"$BENCH" -m "$MODEL" -p 512 -n 128 --output json 2>/dev/null | python3 -c "
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get('n_gen', 0) > 0)
pp = next((r for r in rows if r.get('n_gen', 0) == 0 and r.get('n_prompt', 0) > 0), None)
print(f'Gen TPS: {tg[\"avg_ts\"]:.2f} t/s')
if pp:
    print(f'PP rate: {pp[\"avg_ts\"]:.2f} t/s (512 prompt tokens)')
"
