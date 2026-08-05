#!/usr/bin/env bash
# Full Gate 1 verify (llama-bench + accuracy limit=50). Expect 6–10 hours on WSL.
set -euo pipefail
cd "$(dirname "$0")/.."
export HOME=/home/kipkirui
export HF_HOME=/home/kipkirui/.cache/huggingface
mkdir -p "$HF_HOME"

MODEL_SRC="$PWD/model/qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_DST=/home/kipkirui/maathai-model/qwen2.5-3b-instruct-q4_k_m.gguf
mkdir -p "$(dirname "$MODEL_DST")"
if [[ ! -f "$MODEL_DST" ]] || [[ "$(stat -c%s "$MODEL_DST" 2>/dev/null || echo 0)" -ne "$(stat -c%s "$MODEL_SRC")" ]]; then
  echo "→ copying GGUF to $MODEL_DST"
  cp -f "$MODEL_SRC" "$MODEL_DST"
fi

sed -i 's/\r$//' scripts/gate1_verify.sh scripts/*.py 2>/dev/null || true
# Ensure accuracy runner patch is applied
.venv-wsl/bin/python3.11 scripts/patch_adtc_accuracy_runner.py

echo "=== starting FULL gate1_verify at $(date -Is) ==="
bash scripts/gate1_verify.sh
echo "=== finished FULL gate1_verify at $(date -Is) ==="
