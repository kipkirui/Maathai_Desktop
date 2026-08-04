#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Maathai Desktop – Model Download & Setup Script
# ADTC 2026 Submission: Africa Deep Tech Challenge
#
# Downloads Qwen2.5-3B-Instruct Q4_K_M GGUF (~1.86 GB) to model/
# Idempotent – safe to run multiple times without re-downloading.
# Requires: curl OR wget  |  No credentials needed (public HuggingFace repos)
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODEL_DIR="$SCRIPT_DIR/model"
MODEL_FILENAME="qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_FILE="$MODEL_DIR/$MODEL_FILENAME"
MODEL_URL="https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
MODEL_URL_FALLBACK="https://huggingface.co/bartowski/Qwen2.5-3B-Instruct-GGUF/resolve/main/Qwen2.5-3B-Instruct-Q4_K_M.gguf"
MIN_SIZE_BYTES=1800000000

_do_download() {
  local url="$1"
  echo "Downloading from: $url"
  if command -v curl &>/dev/null; then
    curl -L --progress-bar --retry 3 --retry-delay 5 -o "$MODEL_FILE" "$url"
  elif command -v wget &>/dev/null; then
    wget -q --show-progress --tries=3 -O "$MODEL_FILE" "$url"
  else
    echo "Error: neither curl nor wget found. Please install one and retry."
    exit 1
  fi
}

echo "=== Maathai Desktop — Model Download ==="
echo "Model  : Qwen2.5-3B-Instruct Q4_K_M"
echo "Target : $MODEL_FILE"
echo ""

mkdir -p "$MODEL_DIR"

SKIP_DOWNLOAD=false
if [ -f "$MODEL_FILE" ]; then
  EXISTING=$(stat -c%s "$MODEL_FILE" 2>/dev/null || stat -f%z "$MODEL_FILE" 2>/dev/null || echo 0)
  if [ "$EXISTING" -ge "$MIN_SIZE_BYTES" ]; then
    echo "✓ Model already present ($((EXISTING / 1024 / 1024)) MB). Skipping download."
    SKIP_DOWNLOAD=true
  else
    echo "⚠ Incomplete file ($((EXISTING / 1024 / 1024)) MB). Re-downloading..."
    rm -f "$MODEL_FILE"
  fi
fi

if [ "$SKIP_DOWNLOAD" = false ]; then
  if ! _do_download "$MODEL_URL"; then
    echo "Primary URL failed. Trying fallback..."
    rm -f "$MODEL_FILE"
    _do_download "$MODEL_URL_FALLBACK"
  fi

  FINAL=$(stat -c%s "$MODEL_FILE" 2>/dev/null || stat -f%z "$MODEL_FILE" 2>/dev/null || echo 0)
  if [ "$FINAL" -lt "$MIN_SIZE_BYTES" ]; then
    echo "Error: file too small ($((FINAL / 1024 / 1024)) MB). Possibly corrupt."
    rm -f "$MODEL_FILE"
    exit 1
  fi
  echo "✓ Download complete ($((FINAL / 1024 / 1024)) MB)"
fi

echo ""
echo "=== Setup complete ==="
echo "✓ GGUF model : $MODEL_FILE"
echo "✓ RAG corpus : assets/knowledge_base/ (bundled; TF-IDF index built at app startup)"
echo ""
echo "Start the app     : flutter pub get && flutter run -d linux"
echo "Gate 1 full check : bash scripts/gate1_verify.sh"
echo "Profiler (final)  : adtc-profiler run --submission . --mode participant --output submission.json"
echo "Profiler (smoke)  : adtc-profiler run --submission . --mode participant --output submission.json --skip-accuracy"
