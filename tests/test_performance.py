"""Performance regression tests — TPS and RAM.

Note: Judges use adtc-profiler + llama-bench (see scripts/run_adtc_profiler.sh).
These pytest checks use llama-cpp-python for quick local regression only.
Run the authoritative benchmark: bash scripts/run_adtc_profiler.sh
"""

from __future__ import annotations

import time

import psutil
import pytest

from src.llm.inference import LlamaInference

TPS_MINIMUM = 10.0
TPS_TARGET = 15.0
RAM_HARD_LIMIT_MB = 7168
RAM_TARGET_MB = 3500


@pytest.fixture(scope="module")
def model(requires_model):
    llm = LlamaInference(model_path=str(requires_model))
    yield llm
    llm.release()


@pytest.mark.perf
def test_tps_meets_minimum(model):
    prompt = (
        "You are a farming advisor. A farmer asks: "
        "My tomato plants have brown spots with yellow halos on the leaves. "
        "What disease is this and how do I treat it? Give step-by-step advice."
    )

    start = time.perf_counter()
    tokens = list(model.generate_stream(prompt, max_tokens=128))
    elapsed = time.perf_counter() - start

    tps = len(tokens) / elapsed if elapsed > 0 else 0
    print(f"\nTPS measurement: {tps:.1f} t/s over {len(tokens)} tokens ({elapsed:.2f}s)")

    assert tps >= TPS_MINIMUM, f"TPS {tps:.1f} is below minimum {TPS_MINIMUM}"
    if tps < TPS_TARGET:
        print(f"WARNING: TPS {tps:.1f} is below target {TPS_TARGET}. Sperf will be reduced.")


@pytest.mark.perf
def test_ram_within_hard_limit(model):
    rss = psutil.Process().memory_info().rss / (1024 * 1024)
    print(f"\nCurrent RSS: {rss:.0f} MB")
    assert rss < RAM_HARD_LIMIT_MB, (
        f"DISQUALIFICATION: {rss:.0f} MB >= {RAM_HARD_LIMIT_MB} MB hard limit"
    )


@pytest.mark.perf
def test_ram_within_target(model):
    rss = psutil.Process().memory_info().rss / (1024 * 1024)
    seff = (7168 - rss) / 7168 * 100
    print(f"\nRAM: {rss:.0f} MB | Seff estimate: {seff:.1f}")
    assert rss < RAM_TARGET_MB, (
        f"RAM {rss:.0f} MB exceeds target {RAM_TARGET_MB} MB (Seff={seff:.1f})"
    )


@pytest.mark.perf
def test_first_token_latency(model):
    prompt = "What are the signs of fall armyworm on maize?"

    first_token_time = None
    start = time.perf_counter()

    for chunk in model.generate_stream(prompt, max_tokens=64):
        if chunk.strip() and first_token_time is None:
            first_token_time = time.perf_counter() - start
            break

    assert first_token_time is not None, "No tokens generated"
    print(f"\nFirst token latency: {first_token_time * 1000:.0f} ms")
    assert first_token_time < 2.0, (
        f"First token latency {first_token_time * 1000:.0f} ms exceeds 2000 ms"
    )


@pytest.mark.perf
def test_sustained_generation_no_crash(model):
    prompts = [
        "Describe the best practices for maize farming in East Africa.",
        "What livestock vaccines are essential for a cattle farmer in Kenya?",
        "How do I control fall armyworm without chemical pesticides?",
        "What is the best time to plant beans in western Kenya?",
        "How do I improve yield on a farm with poor sandy soil?",
    ]

    for i, prompt in enumerate(prompts):
        tokens = list(model.generate_stream(prompt, max_tokens=128))
        rss = psutil.Process().memory_info().rss / (1024 * 1024)
        assert len(tokens) > 0, f"Prompt {i + 1} generated no tokens"
        assert rss < RAM_HARD_LIMIT_MB, f"OOM risk after prompt {i + 1}: {rss:.0f} MB"
        print(f"Prompt {i + 1}: {len(tokens)} tokens, RSS {rss:.0f} MB")
