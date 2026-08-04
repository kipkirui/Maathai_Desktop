#!/usr/bin/env python3
"""Run ARC-Easy via lm_eval + maathai_llama_cpp; print one accuracy JSON row."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Ensure this scripts/ dir is importable for maathai_lm_eval_model
sys.path.insert(0, str(Path(__file__).resolve().parent))

import maathai_lm_eval_model  # noqa: F401  — registers model
from lm_eval import simple_evaluate


def _fast_model_path(path: str) -> str:
    """Prefer a native Linux path; /mnt/* (9p/drvfs) is too slow for lm_eval."""
    import os
    import shutil
    from pathlib import Path as P

    src = P(path).resolve()
    posix = str(src)
    if not (posix.startswith("/mnt/") or posix.startswith("C:")):
        return posix
    dest_dir = P("/tmp/maathai-model")
    dest_dir.mkdir(parents=True, exist_ok=True)
    dest = dest_dir / src.name
    if not dest.exists() or dest.stat().st_size != src.stat().st_size:
        print(f"→ copying GGUF to {dest} for faster accuracy (avoid /mnt)", file=sys.stderr)
        shutil.copy2(src, dest)
    return str(dest)


def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--model-path", required=True)
    p.add_argument("--task", default="arc_easy")
    p.add_argument("--limit", type=int, default=50)
    p.add_argument("--seed", type=int, default=42)
    p.add_argument("--language", default="en")
    args = p.parse_args()

    model_path = _fast_model_path(args.model_path)

    results = simple_evaluate(
        model="maathai_llama_cpp",
        model_args=f"model_path={model_path},n_ctx=512,n_threads=4,n_gpu_layers=0",
        tasks=[args.task],
        limit=args.limit,
        random_seed=args.seed,
        numpy_random_seed=args.seed,
        torch_random_seed=args.seed,
        fewshot_random_seed=args.seed,
    )
    if results is None:
        print("FAIL: simple_evaluate returned None", file=sys.stderr)
        return 1

    task_results = results["results"].get(args.task)
    if not task_results:
        print(f"FAIL: task {args.task} missing: {list(results.get('results', {}))}", file=sys.stderr)
        return 1

    score = (
        task_results.get("acc_norm,none")
        or task_results.get("acc,none")
        or 0.0
    )
    metric = "acc_norm" if "acc_norm,none" in task_results else "acc"
    row = {
        "benchmark": args.task,
        "dataset_version": "lm-eval-harness",
        "language": args.language,
        "samples": args.limit,
        "score": round(float(score), 4),
        "metric": metric,
    }
    print(json.dumps(row))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
