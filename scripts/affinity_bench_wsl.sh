#!/usr/bin/env bash
# Pin llama-bench to 4 CPUs (ADTC profile) — can reduce HT contention on WSL.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export LD_LIBRARY_PATH="$ROOT/tools/llama-linux/llama-b9777:${LD_LIBRARY_PATH:-}"
BENCH="$ROOT/tools/llama-linux/llama-bench"
MODEL="$ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"

run() {
  local label="$1"
  shift
  echo -n "$label: "
  "$@" 2>/dev/null | python3 -c "
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get('n_gen', 0) > 0)
print(f\"{tg['avg_ts']:.2f} t/s\")
"
}

echo "=== CPU affinity (competition -p 512 -n 128) ==="
run "no affinity" "$BENCH" -m "$MODEL" -p 512 -n 128 --output json
if command -v taskset >/dev/null 2>&1; then
  run "taskset 0-3" taskset -c 0-3 "$BENCH" -m "$MODEL" -p 512 -n 128 --output json
  run "taskset 0-3 -t 4" taskset -c 0-3 "$BENCH" -m "$MODEL" -p 512 -n 128 -t 4 --output json
fi
