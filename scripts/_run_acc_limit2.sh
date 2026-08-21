#!/usr/bin/env bash
set -euo pipefail
cd /mnt/d/Github/v2/Maathai_Desktop
sed -i 's/\r$//' scripts/*.py scripts/*.sh 2>/dev/null || true

export HOME=/home/kipkirui
export HF_HOME=/home/kipkirui/.cache/huggingface
mkdir -p "$HF_HOME"

MODEL_SRC="$PWD/model/qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_DST=/home/kipkirui/maathai-model/qwen2.5-3b-instruct-q4_k_m.gguf
mkdir -p "$(dirname "$MODEL_DST")"
if [[ ! -f "$MODEL_DST" ]] || [[ "$(stat -c%s "$MODEL_DST")" -ne "$(stat -c%s "$MODEL_SRC")" ]]; then
  echo "→ copying GGUF to $MODEL_DST"
  cp -f "$MODEL_SRC" "$MODEL_DST"
fi
# Keep /tmp copy too for scripts that hardcode it
mkdir -p /tmp/maathai-model
cp -f "$MODEL_DST" /tmp/maathai-model/qwen2.5-3b-instruct-q4_k_m.gguf

echo "HF_HOME=$HF_HOME"
echo "MODEL=$MODEL_DST"
/usr/bin/time -f 'ELAPSED %e' \
  .venv-wsl/bin/python scripts/run_maathai_accuracy.py \
  --model-path "$MODEL_DST" \
  --limit 2
