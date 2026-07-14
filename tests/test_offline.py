"""Offline isolation tests — no network during inference or RAG."""

from __future__ import annotations

import socket

import pytest

from src.llm.inference import LlamaInference
from src.rag.tfidf_retriever import TfidfRetriever


@pytest.mark.offline
def test_rag_loads_with_network_disabled():
    original_connect = socket.socket.connect

    def blocked_connect(self, address):
        raise OSError(f"Network blocked during offline test. Attempted: {address}")

    socket.socket.connect = blocked_connect
    try:
        retriever = TfidfRetriever()
        assert retriever.initialize()
        results = retriever.retrieve("maize nitrogen deficiency", top_k=2)
        assert isinstance(results, list)
    finally:
        socket.socket.connect = original_connect


@pytest.mark.offline
def test_model_loads_with_network_disabled(requires_model):
    original_connect = socket.socket.connect

    def blocked_connect(self, address):
        raise OSError(f"Network blocked during offline test. Attempted: {address}")

    socket.socket.connect = blocked_connect
    llm = None
    try:
        llm = LlamaInference(model_path=str(requires_model))
        response = llm.generate("What grows well in dry regions?", max_tokens=32)
        assert len(response.strip()) > 5
    finally:
        socket.socket.connect = original_connect
        if llm is not None:
            llm.release()


@pytest.mark.offline
def test_no_http_calls_during_generation(requires_model, monkeypatch):
    import urllib.request

    http_calls: list[str] = []

    def tracking_urlopen(url, *args, **kwargs):
        http_calls.append(str(url))
        raise OSError("HTTP blocked during offline test")

    monkeypatch.setattr(urllib.request, "urlopen", tracking_urlopen)

    llm = LlamaInference(model_path=str(requires_model))
    try:
        llm.generate("Describe maize growing conditions.", max_tokens=32)
    finally:
        llm.release()

    assert len(http_calls) == 0, f"HTTP call attempted during offline inference: {http_calls}"
