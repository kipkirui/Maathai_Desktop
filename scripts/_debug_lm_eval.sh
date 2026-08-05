#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$(pwd)/tools/llama-linux:$(pwd)/.venv-wsl/bin:$PATH"
PY="$(pwd)/.venv-wsl/bin/python3.11"

echo "=== load test ==="
"$PY" <<'PY'
from llama_cpp import Llama
m = Llama(
    model_path="model/qwen2.5-3b-instruct-q4_k_m.gguf",
    n_ctx=512,
    n_threads=4,
    verbose=False,
)
print("load ok", m.n_ctx())
out = m("Q: 2+2=\nA:", max_tokens=8, echo=False)
print("gen ok", out["choices"][0]["text"][:80])
PY

echo ""
echo "=== lm_eval arc_easy limit=2 ==="
OUT=/tmp/adtc_lm_eval_debug
rm -rf "$OUT"
mkdir -p "$OUT"
set +e
lm_eval \
  --model gguf \
  --model_args "base_url=local,pretrained=model/qwen2.5-3b-instruct-q4_k_m.gguf" \
  --tasks arc_easy \
  --limit 2 \
  --seed 42 \
  --output_path "$OUT/results.json" \
  >"$OUT/stdout.txt" 2>"$OUT/stderr.txt"
RC=$?
set -e
echo "exit=$RC"
echo "--- stderr (tail) ---"
tail -n 80 "$OUT/stderr.txt" || true
echo "--- stdout (tail) ---"
tail -n 40 "$OUT/stdout.txt" || true
ls -la "$OUT" || true
