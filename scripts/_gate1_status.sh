#!/usr/bin/env bash
set -euo pipefail
echo "=== processes ==="
ps -eo pid,etime,pcpu,pmem,cmd | grep -E 'run_maathai|adtc-profiler|lm_eval|llama-server' | grep -v grep || echo "(none)"
echo ""
echo "=== /tmp model ==="
ls -lh /tmp/maathai-model 2>/dev/null || echo "(missing)"
echo ""
echo "=== submission.json ==="
python3 - <<'PY'
import json
from pathlib import Path
p = Path("/mnt/d/Github/v2/Maathai_Desktop/submission.json")
if not p.exists():
    print("missing")
else:
    s = json.loads(p.read_text())
    print("tps", s["throughput"]["tokens_per_second_generation"])
    print("ram", s["memory"]["peak_rss_mb"])
    print("acc", s.get("accuracy"))
    print("throttled", s.get("cpu_thermal", {}).get("throttled"))
PY
