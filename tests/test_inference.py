"""Model loading and inference tests — require GGUF model on disk."""

from __future__ import annotations

import re
import threading

import psutil
import pytest

from src.llm.inference import LlamaInference

RAM_LIMIT_MB = 7168
RAM_TARGET_MB = 3500


def _peak_rss_mb() -> float:
    return psutil.Process().memory_info().rss / (1024 * 1024)


@pytest.fixture(scope="module")
def model(requires_model):
    llm = LlamaInference(model_path=str(requires_model))
    yield llm
    llm.release()


@pytest.mark.inference
def test_model_loads(model):
    assert model.is_loaded()


@pytest.mark.inference
def test_model_within_ram_limit(model):
    rss = _peak_rss_mb()
    assert rss < RAM_LIMIT_MB, f"DISQUALIFICATION RISK: peak RSS {rss:.0f} MB >= {RAM_LIMIT_MB} MB"


@pytest.mark.inference
def test_model_within_target_ram(model):
    rss = _peak_rss_mb()
    assert rss < RAM_TARGET_MB, f"RAM target exceeded: {rss:.0f} MB (target: {RAM_TARGET_MB} MB)"


@pytest.mark.inference
def test_generates_tokens(model):
    response = model.generate(
        "What is the best fertilizer for maize in Kenya?", max_tokens=64
    )
    assert isinstance(response, str)
    assert len(response.strip()) > 10


@pytest.mark.inference
def test_stream_yields_tokens(model):
    chunks = list(model.generate_stream("Name one common maize disease.", max_tokens=32))
    assert len(chunks) > 0
    assert all(isinstance(c, str) for c in chunks)


@pytest.mark.inference
def test_response_no_emojis(model):
    response = model.generate("What causes yellowing maize leaves?", max_tokens=64)
    emoji_pattern = re.compile(
        r"[\U00010000-\U0010ffff]|[\U0001F600-\U0001F64F]|[\U0001F300-\U0001F5FF]",
        flags=re.UNICODE,
    )
    assert not emoji_pattern.search(response), f"Emoji found in response: {response[:100]}"


@pytest.mark.inference
def test_cancel_stops_generation(model):
    results: list[str] = []

    def generate():
        for chunk in model.generate_stream(
            "Tell me everything about agriculture.", max_tokens=512
        ):
            results.append(chunk)
            if len(results) >= 5:
                model.cancel()
                break

    t = threading.Thread(target=generate)
    t.start()
    t.join(timeout=30)
    assert len(results) >= 1
