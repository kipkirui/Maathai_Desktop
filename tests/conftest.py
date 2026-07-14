"""
Maathai Desktop — pytest configuration

Registers custom markers and shared fixtures.
"""

from __future__ import annotations

import json
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent


def pytest_configure(config: pytest.Config) -> None:
    config.addinivalue_line("markers", "unit: fast unit tests that do not require the model")
    config.addinivalue_line("markers", "inference: tests that load the GGUF model")
    config.addinivalue_line("markers", "rag: tests that require the knowledge base")
    config.addinivalue_line("markers", "offline: tests that verify network isolation")
    config.addinivalue_line("markers", "accuracy: domain accuracy tests on competition prompts")
    config.addinivalue_line("markers", "perf: performance regression tests (TPS, RAM)")
    config.addinivalue_line("markers", "submission: final pre-submission validation gate")


@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture(scope="session")
def model_path(repo_root: Path) -> Path:
    meta = json.loads((repo_root / "metadata.json").read_text(encoding="utf-8"))
    return repo_root / meta["_runtime"]["model_path"]


@pytest.fixture(scope="session")
def requires_model(model_path: Path) -> Path:
    if not model_path.exists():
        pytest.skip(f"Model not found at {model_path}. Run: bash download_model.sh")
    return model_path


@pytest.fixture(scope="module")
def retriever():
    from src.rag.tfidf_retriever import TfidfRetriever

    r = TfidfRetriever()
    assert r.initialize(), "Knowledge base failed to load from assets/knowledge_base/"
    return r
