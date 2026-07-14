#!/usr/bin/env bash
# Run the full pytest suite on Ubuntu 22.04 WSL — same OS as ADTC audit / judges.
# Usage (Windows):  powershell -File scripts/run_tests_wsl.ps1
# Usage (WSL):      bash scripts/run_tests_wsl.sh
# Skip profiler:    bash scripts/run_tests_wsl.sh --skip-profiler

set -euo pipefail

SKIP_PROFILER=0
if [[ "${1:-}" == "--skip-profiler" ]]; then
  SKIP_PROFILER=1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Strip Windows CRLF from shell scripts (breaks bash on WSL if edited on Windows)
for _sh in "$SCRIPT_DIR"/*.sh; do
  sed -i 's/\r$//' "$_sh" 2>/dev/null || true
done

VENV="$REPO_ROOT/.venv-wsl"
MODEL="$REPO_ROOT/model/qwen2.5-3b-instruct-q4_k_m.gguf"

echo "=== Maathai Desktop — Ubuntu judge-like test run ==="
echo "Repo : $REPO_ROOT"
echo "OS   : $(. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME" || uname -s)"
echo "CPUs : $(nproc)"
echo ""

if [[ ! -f "$MODEL" ]]; then
  echo "Model missing: $MODEL"
  echo "Run: bash download_model.sh"
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
if ! command -v python3.11 >/dev/null 2>&1; then
  echo "→ Installing Python 3.11..."
  apt-get update -qq
  apt-get install -y -qq software-properties-common >/dev/null
  add-apt-repository -y ppa:deadsnakes/ppa >/dev/null
  apt-get update -qq
  apt-get install -y -qq python3.11 python3.11-venv python3.11-dev build-essential cmake >/dev/null
fi

if [[ ! -x "$VENV/bin/python" ]]; then
  echo "→ Creating .venv-wsl..."
  python3.11 -m venv "$VENV"
fi

# shellcheck disable=SC1091
source "$VENV/bin/activate"
pip install -q --upgrade pip wheel

if ! python -c "import llama_cpp" 2>/dev/null; then
  echo "→ Installing llama-cpp-python (CPU, may take several minutes)..."
  pip install -q --default-timeout=300 "llama-cpp-python>=0.2.90"
fi

echo "→ Installing minimal test dependencies (no torch/PyQt)..."
pip install -q --default-timeout=120 "pytest>=8.0" "pytest-timeout>=2.3" "psutil>=6.0"

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
export MKL_NUM_THREADS=4

cd "$REPO_ROOT"

echo ""
echo "→ pytest (unit + rag + submission + offline + inference + accuracy)..."
pytest tests/ -v \
  --ignore=tests/test_performance.py \
  -m "not perf" \
  --tb=short \
  2>&1 | tee /tmp/maathai_pytest.log

PYTEST_EXIT=${PIPESTATUS[0]}

PROFILER_EXIT=0
if [[ $PYTEST_EXIT -eq 0 && $SKIP_PROFILER -eq 0 ]]; then
  bash "$SCRIPT_DIR/run_adtc_profiler.sh" || PROFILER_EXIT=$?
fi

echo ""
echo "=== Summary ==="
if [[ $PYTEST_EXIT -ne 0 ]]; then
  echo "Core pytest FAILED (exit $PYTEST_EXIT). Fix failures above before submitting."
  exit "$PYTEST_EXIT"
fi

echo "Core pytest PASSED: inference, RAG, offline, accuracy, submission."

if [[ $SKIP_PROFILER -eq 1 ]]; then
  echo "Profiler skipped (--skip-profiler). Run: bash scripts/run_adtc_profiler.sh"
  exit 0
fi

if [[ $PROFILER_EXIT -eq 0 ]]; then
  echo "adtc-profiler PASSED: RAM hard gate OK; submission.json updated."
  echo "Fill metadata.json placeholders before DevPost submission."
else
  echo "adtc-profiler FAILED (exit $PROFILER_EXIT). Check RAM / setup above."
  exit "$PROFILER_EXIT"
fi
