#!/usr/bin/env bash
# One-time + repeat: install llama-bench + adtc-profiler in Ubuntu WSL, run participant profiler.
# Run from Windows:  wsl -d Ubuntu-22.04 bash scripts/wsl_profiler_setup.sh
# Or:               powershell -File scripts/run_profiler_wsl.ps1
# Install only:     bash scripts/wsl_profiler_setup.sh --install-only

set -euo pipefail

INSTALL_ONLY=0
if [[ "${1:-}" == "--install-only" ]]; then
  INSTALL_ONLY=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LLAMA_DIR="$REPO_ROOT/tools/llama-linux"
MODEL="$REPO_ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"
VENV="$REPO_ROOT/.venv-wsl"

echo "=== Maathai Desktop — WSL profiler setup ==="
echo "Repo : $REPO_ROOT"
echo "Model: $MODEL"
echo ""

if [[ ! -f "$MODEL" ]]; then
  echo "Model missing. Run from repo root: bash download_model.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl ca-certificates software-properties-common unzip >/dev/null

# adtc-profiler requires Python >= 3.11; Ubuntu 22.04 ships 3.10
if ! command -v python3.11 >/dev/null 2>&1; then
  echo "→ Installing Python 3.11 (deadsnakes)..."
  add-apt-repository -y ppa:deadsnakes/ppa >/dev/null
  apt-get update -qq
  apt-get install -y -qq python3.11 python3.11-venv python3.11-dev >/dev/null
fi
PYTHON=python3.11

mkdir -p "$LLAMA_DIR"
if [[ ! -x "$LLAMA_DIR/llama-bench" ]]; then
  echo "→ Downloading llama.cpp Linux CPU binaries..."
  release_json="$(curl -s -H 'User-Agent: MaathaiDesktop' \
    'https://api.github.com/repos/ggml-org/llama.cpp/releases/latest')"
  tag="$(python3 -c "import json,sys; print(json.load(sys.stdin)['tag_name'])" <<<"$release_json")"
  asset_name="$(python3 -c "
import json,sys
assets=json.load(sys.stdin)['assets']
for a in assets:
    n=a['name']
    if n.endswith('.tar.gz') and 'bin-ubuntu-x64' in n and 'vulkan' not in n and 'rocm' not in n and 'sycl' not in n and 'openvino' not in n:
        print(n); break
else:
    for a in assets:
        n=a['name']
        if 'bin-ubuntu-x64' in n and n.endswith('.zip'):
            print(n); break
" <<<"$release_json")"
  if [[ -z "$asset_name" ]]; then
    echo "Could not find Linux x64 bundle in release $tag"
    exit 1
  fi
  url="https://github.com/ggml-org/llama.cpp/releases/download/${tag}/${asset_name}"
  archive="$LLAMA_DIR/llama-archive"
  curl -L --retry 3 -o "$archive" "$url"
  if [[ "$asset_name" == *.tar.gz ]]; then
    tar -xzf "$archive" -C "$LLAMA_DIR"
  else
    unzip -o -q "$archive" -d "$LLAMA_DIR"
  fi
  rm -f "$archive"
  bench="$(find "$LLAMA_DIR" -name llama-bench -type f | head -1)"
  if [[ -z "$bench" ]]; then
    echo "llama-bench not found after extract"
    exit 1
  fi
  chmod +x "$bench"
  ln -sf "$bench" "$LLAMA_DIR/llama-bench"
  server="$(find "$LLAMA_DIR" -name llama-server -type f | head -1)"
  if [[ -n "$server" ]]; then
    chmod +x "$server"
    ln -sf "$server" "$LLAMA_DIR/llama-server"
  fi
  echo "   Installed: $LLAMA_DIR/llama-bench"
fi

if [[ ! -x "$LLAMA_DIR/llama-bench" ]]; then
  echo "llama-bench missing at $LLAMA_DIR/llama-bench"
  exit 1
fi

if [[ ! -x "$VENV/bin/adtc-profiler" ]]; then
  echo "→ Installing adtc-profiler in .venv-wsl (Python 3.11)..."
  "$PYTHON" -m venv "$VENV"
fi

# Always use python3.11 inside the venv when present (avoid mixed 3.10/3.11 site-packages)
if [[ -x "$VENV/bin/python3.11" ]]; then
  VPY="$VENV/bin/python3.11"
else
  VPY="$VENV/bin/python"
fi

echo "→ Ensuring adtc-profiler + lm-eval on $($VPY -V)"
"$VPY" -m pip install -q --upgrade pip
"$VPY" -m pip install -q "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"
if ! "$VPY" -c "import lm_eval" >/dev/null 2>&1; then
  echo "FAIL: lm_eval still missing after install"
  exit 1
fi
echo "✓ lm_eval import OK"

if [[ $INSTALL_ONLY -eq 1 ]]; then
  echo ""
  echo "Setup complete. Run: bash scripts/run_adtc_profiler.sh"
  exit 0
fi

bash "$SCRIPT_DIR/run_adtc_profiler.sh"
