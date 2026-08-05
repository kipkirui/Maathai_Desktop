#!/usr/bin/env bash
# Quick check: patch + llama-server + lm_eval arc_easy limit=2
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$(pwd)/tools/llama-linux:$(pwd)/.venv-wsl/bin:$PATH"
PY="$(pwd)/.venv-wsl/bin/python3.11"
SERVER_BIN="$(command -v llama-server)"
MODEL="model/qwen2.5-3b-instruct-q4_k_m.gguf"

"$PY" scripts/patch_adtc_accuracy_base_url.py
"$PY" scripts/patch_lm_eval_gguf_logprobs.py

"$SERVER_BIN" -m "$MODEL" --host 127.0.0.1 --port 8080 -c 2048 -t 4 -ngl 0 --log-disable \
  >/tmp/maathai_acc_smoke_server.log 2>&1 &
SPID=$!
cleanup() { kill "$SPID" 2>/dev/null || true; }
trap cleanup EXIT

for _ in $(seq 1 60); do
  curl -fsS http://127.0.0.1:8080/v1/models >/dev/null 2>&1 && break
  sleep 2
done
curl -fsS http://127.0.0.1:8080/v1/models >/dev/null

echo "→ lm_eval limit=2"
OUT=/tmp/adtc_acc_smoke
rm -rf "$OUT"; mkdir -p "$OUT"
lm_eval \
  --model gguf \
  --model_args "base_url=http://127.0.0.1:8080,pretrained=$MODEL" \
  --tasks arc_easy \
  --limit 2 \
  --seed 42 \
  --output_path "$OUT/results.json"
echo "✓ accuracy smoke OK"
find "$OUT" -name 'results*.json' -print
