#!/usr/bin/env python3
"""Point adtc-profiler accuracy.run_benchmark at scripts/run_maathai_accuracy.py.

Upstream uses lm_eval --model gguf with base_url=local, which is incompatible
with current llama-server OpenAI logprobs. Our runner uses llama-cpp-python.
"""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "MAATHAI_ACCURACY_RUNNER"

NEW_IMPL = '''
def run_benchmark(
    model_path: Path,
    *,
    task: str = "arc_easy",
    limit: int = 50,
    language: str = "en",
    seed: int = 42,
) -> dict:
    """Run lm_eval via Maathai llama-cpp-python runner; return one accuracy row."""
    # {MARKER}
    repo_scripts = Path(__file__).resolve()
    # Prefer repo scripts/ next to cwd when profiler is invoked from submission root
    runner = Path.cwd() / "scripts" / "run_maathai_accuracy.py"
    if not runner.is_file():
        raise AccuracyError(f"missing accuracy runner: {runner}")

    import os
    import sys as _sys

    py = _sys.executable
    cmd = [
        py,
        str(runner),
        "--model-path", str(model_path),
        "--task", task,
        "--limit", str(limit),
        "--seed", str(seed),
        "--language", language,
    ]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False, env=os.environ.copy())
    if proc.returncode != 0:
        raise AccuracyError(
            f"maathai accuracy runner exited {proc.returncode}\\n"
            f"stdout:\\n{proc.stdout[:1000]}\\nstderr:\\n{proc.stderr[:2000]}"
        )
    line = (proc.stdout or "").strip().splitlines()[-1]
    try:
        return json.loads(line)
    except json.JSONDecodeError as exc:
        raise AccuracyError(f"invalid accuracy JSON: {line!r}") from exc
'''.replace("{MARKER}", MARKER)


def main() -> int:
    try:
        import adtc_profiler.accuracy as accuracy
    except ImportError as exc:
        print(f"FAIL: {exc}")
        return 1

    path = Path(accuracy.__file__)
    text = path.read_text(encoding="utf-8")
    if MARKER in text:
        print(f"✓ already patched: {path}")
        return 0

    # Replace existing run_benchmark function body by cutting from def to next top-level def/EOF
    import re

    pattern = r"\ndef run_benchmark\([\s\S]*?(?=\nDefDummy|\Z)"
    # Match until end of file — run_benchmark is last function
    m = re.search(r"\ndef run_benchmark\(", text)
    if not m:
        print("FAIL: run_benchmark not found")
        return 1
    text = text[: m.start()] + "\n" + NEW_IMPL
    # Ensure json/subprocess imports exist
    if "import json" not in text:
        text = text.replace("from __future__ import annotations\n", "from __future__ import annotations\n\nimport json\n")
    if "import subprocess" not in text:
        text = text.replace("import json\n", "import json\nimport subprocess\n")

    path.write_text(text, encoding="utf-8")
    for pyc in path.parent.glob("__pycache__/accuracy*.pyc"):
        pyc.unlink(missing_ok=True)
    print(f"✓ patched {path} → maathai accuracy runner")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
