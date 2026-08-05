#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$(pwd)/tools/llama-linux:$PATH"
pkill -f 'llama-server.*--port 8080' 2>/dev/null || true
sleep 1
llama-server -m model/qwen2.5-3b-instruct-q4_k_m.gguf \
  --host 127.0.0.1 --port 8080 -c 2048 -t 4 -ngl 0 --log-disable \
  >/tmp/ls_probe.log 2>&1 &
SPID=$!
cleanup() { kill "$SPID" 2>/dev/null || true; }
trap cleanup EXIT
for _ in $(seq 1 40); do
  curl -fsS http://127.0.0.1:8080/v1/models >/dev/null 2>&1 && break
  sleep 1
done
python3 <<'PY'
import json, urllib.request
context = "Question: What is 2+2?\nAnswer:"
continuation = " 4"
prompt = context + continuation
req = {
    "prompt": prompt,
    "max_tokens": 1,
    "echo": True,
    "logprobs": 5,
    "temperature": 0.0,
}
data = json.dumps(req).encode()
r = urllib.request.Request(
    "http://127.0.0.1:8080/v1/completions",
    data=data,
    headers={"Content-Type": "application/json"},
)
with urllib.request.urlopen(r, timeout=120) as resp:
    body = json.load(resp)
choice = body["choices"][0]
lp = choice.get("logprobs") or {}
content = lp.get("content") or []
print("context_len", len(context))
print("prompt_len", len(prompt))
print("text_len", len(choice.get("text") or ""))
print("content_tokens", len(content))
joined = "".join((c.get("token") or "") for c in content)
print("joined_len", len(joined))
print("joined_startswith_context", joined.startswith(context[:20]) if joined else None)
print("first3", [c.get("token") for c in content[:3]])
print("last3", [c.get("token") for c in content[-3:]])
# Also try completion-only without relying on echo offsets:
print("text_tail", repr((choice.get("text") or "")[-40:]))
PY
