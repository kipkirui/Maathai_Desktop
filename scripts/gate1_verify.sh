#!/usr/bin/env bash
# -----------------------------------------------------------------------------
# Gate 1 close-out runbook — Ubuntu 22.04 / WSL
#
# Verifies download → profiler → hard gates, then prints the remaining
# human checklist (public repo, video, DevPost).
#
# Usage (from repo root):
#   bash scripts/gate1_verify.sh              # full participant run (accuracy ON)
#   bash scripts/gate1_verify.sh --smoke      # skip accuracy (faster iterate)
#   bash scripts/gate1_verify.sh --checklist  # print remaining Gate 1 tasks only
# -----------------------------------------------------------------------------
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SMOKE=0
CHECKLIST_ONLY=0
for arg in "$@"; do
  case "$arg" in
    --smoke) SMOKE=1 ;;
    --checklist) CHECKLIST_ONLY=1 ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      exit 2
      ;;
  esac
done

print_checklist() {
  local repo_public="[ ]"
  if curl -fsS "https://api.github.com/repos/kipkirui/Maathai_Desktop" 2>/dev/null \
    | python3 -c 'import json,sys; print("public" if not json.load(sys.stdin).get("private") else "private")' 2>/dev/null \
    | grep -q public; then
    repo_public="[x]"
  fi
  local gguf_ok="[x]"
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ -n "$(git ls-files '*.gguf' 'model/*.gguf' 2>/dev/null || true)" ]]; then
      gguf_ok="[ ]"
    fi
  fi
  cat <<EOF

=== Gate 1 remaining checklist (human) ===
  $repo_public GitHub repo is PUBLIC (required at evaluation)
  $gguf_ok *.gguf / model/ not committed (check: git ls-files '*.gguf')
  [ ] submission.json from FULL profiler (accuracy not empty) committed or attached
  [ ] REPORT.md benchmarks match latest submission.json
  [ ] Offline proof: airplane mode / unplug, one EN + one SW query
  [ ] Demo video ≤ 2 min recorded + uploaded (see GATE1.md shot list)
  [ ] DevPost submission draft filled; submit before Aug 25, 2026
      (DevPost clock: Aug 24, 2026 @ 11:45pm PDT)

EOF
}

if [[ "$CHECKLIST_ONLY" -eq 1 ]]; then
  print_checklist
  exit 0
fi

echo "=== Maathai Desktop — Gate 1 verify ==="
echo "Repo  : $REPO_ROOT"
echo "Mode  : $([[ "$SMOKE" -eq 1 ]] && echo 'SMOKE (--skip-accuracy)' || echo 'FULL (accuracy included)')"
echo ""

# --- metadata sanity ---
python3 - <<'PY'
import json
import sys
from pathlib import Path

p = Path("metadata.json")
if not p.exists():
    print("FAIL: metadata.json missing")
    sys.exit(1)
m = json.loads(p.read_text(encoding="utf-8"))
required = [
    "team_id", "domain", "language_scope", "african_alpha_claim",
    "budget_laptop_claim", "submitter", "cross_disciplinary_pairing",
    "test_prompts", "model", "_runtime",
]
missing = [k for k in required if k not in m]
if missing:
    print("FAIL: metadata.json missing keys:", ", ".join(missing))
    sys.exit(1)
prompts = m.get("test_prompts") or []
if len(prompts) != 2:
    print(f"FAIL: need exactly 2 test_prompts, found {len(prompts)}")
    sys.exit(1)
if m.get("model", {}).get("runtime") != "llama.cpp":
    print("FAIL: model.runtime must be llama.cpp")
    sys.exit(1)
path = m["_runtime"]["model_path"]
print(f"✓ metadata.json OK  team={m['team_id']}  domain={m['domain']}  model_path={path}")
if not m.get("african_alpha_claim"):
    print("⚠ african_alpha_claim is false — Swahili bonus not claimed")
if not m.get("budget_laptop_claim"):
    print("FAIL: budget_laptop_claim must be true")
    sys.exit(1)
PY

# --- no weights in git index ---
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  tracked_gguf="$(git ls-files '*.gguf' 'model/*.gguf' 2>/dev/null || true)"
  if [[ -n "$tracked_gguf" ]]; then
    echo "FAIL: GGUF files are tracked by git:"
    echo "$tracked_gguf"
    exit 1
  fi
  echo "✓ no .gguf tracked in git"
fi

# --- download model ---
echo ""
echo "→ download_model.sh"
bash download_model.sh

MODEL_PATH="$(python3 -c 'import json; print(json.load(open("metadata.json"))["_runtime"]["model_path"])')"
if [[ ! -f "$MODEL_PATH" ]]; then
  echo "FAIL: model missing at $MODEL_PATH after download_model.sh"
  exit 1
fi
echo "✓ model present: $MODEL_PATH ($(du -h "$MODEL_PATH" | cut -f1))"

# --- prefer repo llama-bench / venv if present; else PATH ---
LLAMA_DIR="$REPO_ROOT/tools/llama-linux"
VENV="$REPO_ROOT/.venv-wsl"
if [[ -x "$LLAMA_DIR/llama-bench" ]]; then
  export PATH="$LLAMA_DIR:$PATH"
fi
# Prefer Python 3.11 entrypoints — mixed 3.10/3.11 venvs put lm_eval only on 3.11
ADTC_BIN=""
if [[ -x "$VENV/bin/python3.11" && -x "$VENV/bin/adtc-profiler" ]]; then
  export PATH="$VENV/bin:$PATH"
  ADTC_BIN="$VENV/bin/adtc-profiler"
  # Verify accuracy import on the same interpreter adtc-profiler uses
  if ! "$VENV/bin/python3.11" -c "import lm_eval" >/dev/null 2>&1; then
    echo "⚠ lm_eval missing for python3.11 — installing accuracy stack..."
    "$VENV/bin/python3.11" -m pip install -q "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"
  fi
elif [[ -x "$VENV/bin/adtc-profiler" ]]; then
  # shellcheck disable=SC1091
  source "$VENV/bin/activate"
  ADTC_BIN="$(command -v adtc-profiler)"
fi

if ! command -v llama-bench >/dev/null 2>&1; then
  echo ""
  echo "llama-bench not on PATH."
  if [[ -f "$SCRIPT_DIR/wsl_profiler_setup.sh" ]]; then
    echo "→ running scripts/wsl_profiler_setup.sh --install-only"
    sed -i 's/\r$//' "$SCRIPT_DIR/wsl_profiler_setup.sh" 2>/dev/null || true
    bash "$SCRIPT_DIR/wsl_profiler_setup.sh" --install-only
    export PATH="$LLAMA_DIR:$VENV/bin:$PATH"
    ADTC_BIN="$VENV/bin/adtc-profiler"
  else
    echo "Install llama.cpp (llama-bench) and adtc-profiler, then re-run."
    exit 1
  fi
fi

if [[ -z "$ADTC_BIN" ]] || [[ ! -x "$ADTC_BIN" ]]; then
  if command -v adtc-profiler >/dev/null 2>&1; then
    ADTC_BIN="$(command -v adtc-profiler)"
  else
    echo "adtc-profiler not found. Install:"
    echo '  python3.11 -m pip install "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"'
    exit 1
  fi
fi

echo "✓ llama-bench : $(command -v llama-bench)"
echo "✓ adtc-profiler: $ADTC_BIN"
if "$VENV/bin/python3.11" -c "import lm_eval" >/dev/null 2>&1; then
  echo "✓ lm_eval     : available (python3.11)"
else
  echo "⚠ lm_eval     : missing — accuracy may be empty"
fi

export OMP_NUM_THREADS=4
export OPENBLAS_NUM_THREADS=4
export MKL_NUM_THREADS=4

PROFILER_CMD=("$ADTC_BIN" run)
if command -v taskset >/dev/null 2>&1; then
  PROFILER_CMD=(taskset -c 0-3 "$ADTC_BIN" run)
fi

echo ""
if [[ "$SMOKE" -eq 1 ]]; then
  echo "→ adtc-profiler participant SMOKE (~3–8 min, no accuracy)..."
  "${PROFILER_CMD[@]}" \
    --submission . \
    --mode participant \
    --output submission.json \
    --skip-accuracy
else
  echo "→ preparing FULL accuracy run (llama-cpp-python lm_eval backend)..."
  # Upstream lm_eval --model gguf + llama-server cannot score loglikelihood on
  # current OpenAI logprobs. Use Maathai runner via patched adtc accuracy.py.
  if [[ -x "$VENV/bin/python3.11" ]]; then
    "$VENV/bin/python3.11" "$SCRIPT_DIR/patch_adtc_accuracy_runner.py"
  else
    python3 "$SCRIPT_DIR/patch_adtc_accuracy_runner.py"
  fi

  echo "→ adtc-profiler participant FULL (includes accuracy; can take 30–90+ min)..."
  "${PROFILER_CMD[@]}" \
    --submission . \
    --mode participant \
    --output submission.json
fi

python3 - <<'PY'
import json
import sys
from pathlib import Path

s = json.loads(Path("submission.json").read_text(encoding="utf-8"))
ram = s["memory"]["peak_rss_mb"]
tps = s["throughput"]["tokens_per_second_generation"]
ftl = s["throughput"]["first_token_latency_ms"]
throttled = s.get("cpu_thermal", {}).get("throttled")
acc = s.get("accuracy") or []
seff = (7168 - ram) / 7168 * 100
sperf_prov = min(tps / 15.0, 1.0) * 100

print()
print("=== Profiler summary ===")
print(f"measured_on : {s.get('environment', {}).get('measured_on')}")
print(f"OS / CPU    : {s.get('environment', {}).get('os')} / {s.get('environment', {}).get('cpu_model')}")
print(f"Peak RAM    : {ram:.2f} MB   Seff≈{seff:.1f}")
print(f"Gen TPS     : {tps:.2f}      Sperf(provisional 15)≈{sperf_prov:.1f}")
print(f"            : official Sperf = 100×(TPSact/TPSmax) on audit hardware")
print(f"First token : {ftl:.0f} ms")
print(f"Throttled   : {throttled}")
print(f"Accuracy    : {len(acc)} entries" + ("  ← EMPTY — re-run without --smoke for Gate 1" if not acc else ""))
print(f"Output      : {Path('submission.json').resolve()}")

print()
print("=== Hard / soft gates ===")
ok = True
if ram >= 7168:
    print("FAIL  peak_rss_mb >= 7168  → disqualification")
    ok = False
else:
    print("PASS  peak_rss_mb < 7168")
if throttled:
    print("WARN  thermal throttling flagged → −10 Pthermal risk")
else:
    print("PASS  no thermal throttle flag")
if tps < 15:
    print(f"WARN  TPS {tps:.2f} < 15 provisional ref (scoring only; maximize for TPSmax race)")
else:
    print("PASS  TPS >= 15 provisional ref")
if not acc:
    print("WARN  accuracy suite empty — do not submit this JSON as final Gate 1 artifact")
else:
    print("PASS  accuracy suite present")

sys.exit(0 if ok else 1)
PY

print_checklist
echo "Done. Next: refresh REPORT.md benchmarks from submission.json, then record video (GATE1.md)."
echo ""
