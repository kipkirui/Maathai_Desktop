#!/usr/bin/env python3
"""Patch adtc-profiler accuracy.py so lm_eval gguf uses a real llama-server URL.

Upstream currently passes base_url=local, but lm-eval's gguf backend expects
an OpenAI-compatible HTTP base (e.g. http://127.0.0.1:8080).
"""
from __future__ import annotations

import sys
from pathlib import Path

OLD = 'f"base_url=local,pretrained={model_path}"'
NEW = 'f"base_url=http://127.0.0.1:8080,pretrained={model_path}"'


def main() -> int:
    try:
        import adtc_profiler.accuracy as accuracy
    except ImportError as exc:
        print(f"FAIL: cannot import adtc_profiler.accuracy: {exc}")
        return 1

    path = Path(accuracy.__file__)
    text = path.read_text(encoding="utf-8")
    if NEW in text:
        print(f"✓ already patched: {path}")
        return 0
    if OLD not in text:
        print(f"FAIL: expected snippet not found in {path}")
        return 1
    path.write_text(text.replace(OLD, NEW, 1), encoding="utf-8")
    print(f"✓ patched {path}")
    print("  base_url=local → http://127.0.0.1:8080")
    return 0


if __name__ == "__main__":
    sys.exit(main())
