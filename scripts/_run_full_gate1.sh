#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
VENV=".venv-wsl"
# Prefer 3.11 — lm-eval / adtc accuracy stack was installed there
if [[ -x "$VENV/bin/python3.11" ]]; then
  PY="$VENV/bin/python3.11"
elif [[ -x "$VENV/bin/python" ]]; then
  PY="$VENV/bin/python"
else
  echo "Missing $VENV — run: bash scripts/wsl_profiler_setup.sh --install-only"
  exit 1
fi
export PATH="$(pwd)/tools/llama-linux:$VENV/bin:$PATH"
"$PY" -c 'import lm_eval; print("lm_eval", lm_eval.__version__)'
sed -i 's/\r$//' scripts/gate1_verify.sh scripts/patch_adtc_accuracy_base_url.py 2>/dev/null || true
"$PY" scripts/patch_adtc_accuracy_base_url.py
export VIRTUAL_ENV="$(pwd)/$VENV"
hash -r
bash scripts/gate1_verify.sh
