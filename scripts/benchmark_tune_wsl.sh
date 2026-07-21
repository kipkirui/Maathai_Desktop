#!/usr/bin/env bash
# Sweep llama-bench settings to maximize TPS while staying under 7168 MB RAM.
# Competition profiler uses: llama-bench -m model -p 512 -n 128 -t 4 (default)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODEL_WIN="$ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"
BENCH="$ROOT/tools/llama-linux/llama-bench"
LLAMA_DIR="$ROOT/tools/llama-linux/llama-b9777"
MODEL_NATIVE="${MAATHAI_NATIVE_MODEL:-$HOME/maathai/model/qwen2.5-3b-instruct-q4_k_m.gguf}"

export LD_LIBRARY_PATH="$LLAMA_DIR:${LD_LIBRARY_PATH:-}"

if [[ ! -x "$BENCH" ]]; then
  echo "Run scripts/wsl_profiler_setup.sh first (llama-bench missing)."
  exit 1
fi

if [[ ! -f "$MODEL_WIN" ]]; then
  echo "Model not found: $MODEL_WIN"
  exit 1
fi

extract_tps() {
  python3 -c "
import json, sys
rows = json.load(sys.stdin)
tg = next(r for r in rows if r.get('n_gen', 0) > 0)
print(f\"{tg['avg_ts']:.2f}\")
"
}

run_bench() {
  local label="$1"
  shift
  echo -n "  $label ... "
  local tps
  tps=$("$BENCH" "$@" --output json 2>/dev/null | extract_tps)
  echo "${tps} t/s"
}

echo "=== Maathai TPS tuning (llama-bench -p 512 -n 128) ==="
echo "CPU threads available: $(nproc)"
echo ""

# Optional: copy model to native ext4 for faster I/O (WSL /mnt/d is slow)
if [[ "${SKIP_NATIVE_COPY:-0}" != "1" ]]; then
  mkdir -p "$(dirname "$MODEL_NATIVE")"
  if [[ ! -f "$MODEL_NATIVE" ]]; then
    echo "Copying model to native WSL filesystem (one-time ~1.8 GB)..."
    cp "$MODEL_WIN" "$MODEL_NATIVE"
  fi
  MODEL="$MODEL_NATIVE"
  echo "Using native model: $MODEL"
else
  MODEL="$MODEL_WIN"
  echo "Using Windows mount model: $MODEL"
fi
echo ""

echo "--- Thread sweep (competition default t=4) ---"
for t in 2 4 6 8; do
  run_bench "t=$t" -m "$MODEL" -p 512 -n 128 -t "$t"
done
echo ""

echo "--- Batch size (t=4, competition prompt 512) ---"
for b in 512 1024 2048; do
  run_bench "b=$b" -m "$MODEL" -p 512 -n 128 -t 4 -b "$b"
done
echo ""

echo "--- mmap flag (t=4) ---"
run_bench "no-mmap" -m "$MODEL" -p 512 -n 128 -t 4 -mmp 0
run_bench "mmap (default)" -m "$MODEL" -p 512 -n 128 -t 4 -mmp 1
echo ""

echo "--- Competition exact command ---"
run_bench "profiler default" -m "$MODEL" -p 512 -n 128 -t 4
echo ""

echo "--- Flash attention (t=4 -b 2048) ---"
run_bench "fa=on"  -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -fa on
run_bench "fa=off" -m "$MODEL" -p 512 -n 128 -t 4 -b 2048 -fa off
echo ""

echo "Target: >= 10 t/s minimum (tests), >= 15 t/s for full Sperf score"
echo "Hard gate: peak RAM < 7168 MB (run adtc-profiler for official numbers)"
echo "App defaults: --threads 4 --batch-size 2048 --flash-attn on --mlock"
