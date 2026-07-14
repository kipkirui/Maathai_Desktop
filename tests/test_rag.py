"""RAG retrieval quality tests — uses TF-IDF over assets/knowledge_base."""

from __future__ import annotations

import pytest


@pytest.mark.rag
def test_retriever_initializes(retriever):
    assert retriever.is_ready()


@pytest.mark.rag
def test_retrieval_tp001_maize_nakuru(retriever):
    """metadata.json tp_001 — yellow maize leaves, Nakuru, dry weather."""
    query = (
        "maize leaves turning yellow brown spots lower leaves Nakuru Kenya "
        "dry weather nutrient deficiency treatment"
    )
    results = retriever.retrieve(query, top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert any(w in combined for w in ["nitrogen", "can", "urea", "deficiency", "mln"])


@pytest.mark.rag
def test_retrieval_tp002_tomato_arusha(retriever):
    """metadata.json tp_002 — commercial tomato near Arusha, Tanzania."""
    query = (
        "tomato varieties Arusha Tanzania volcanic soil irrigation planting "
        "harvesting schedule diseases market price kilogram"
    )
    results = retriever.retrieve(query, top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert "tomato" in combined
    assert any(w in combined for w in ["anna", "variety", "plant", "disease", "price", "tzs", "kes"])


@pytest.mark.rag
def test_retrieval_maize_disease(retriever):
    results = retriever.retrieve("yellowing leaves on maize plants", top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert any(w in combined for w in ["maize", "corn", "leaf", "nitrogen", "disease"])


@pytest.mark.rag
def test_retrieval_livestock(retriever):
    results = retriever.retrieve("my goats have runny nose and coughing", top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert any(
        w in combined
        for w in ["goat", "respiratory", "pneumonia", "ppr", "livestock"]
    )


@pytest.mark.rag
def test_retrieval_pest(retriever):
    results = retriever.retrieve("caterpillars destroying my maize crop", top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert any(
        w in combined for w in ["armyworm", "caterpillar", "pest", "larvae", "spray"]
    )


@pytest.mark.rag
def test_retrieval_market(retriever):
    results = retriever.retrieve("What is the price of maize in Nairobi?", top_k=3)
    assert len(results) >= 1
    combined = " ".join(r["text"] for r in results).lower()
    assert any(w in combined for w in ["price", "market", "nairobi", "maize", "kg"])


@pytest.mark.rag
def test_retrieval_returns_metadata(retriever):
    results = retriever.retrieve("coffee berry disease treatment", top_k=2)
    for r in results:
        assert "text" in r
        assert "source" in r
        assert "score" in r


@pytest.mark.rag
def test_rag_improves_specificity(retriever):
    results = retriever.retrieve("KALRO recommended bean varieties Kenya", top_k=3)
    combined = " ".join(r["text"] for r in results).lower()
    assert any(
        w in combined for w in ["kalro", "kenya", "bean", "variety", "release", "rose"]
    )


@pytest.mark.parametrize(
    "query,expected_keyword",
    [
        ("tea leaf disease rust Kenya", "tea"),
        ("rice blast disease treatment", "rice"),
        ("sorghum drought tolerance", "sorghum"),
        ("cassava mosaic virus control", "cassava"),
        ("Newcastle disease in chickens", "poultry"),
        ("coffee berries turning black rotting", "coffee"),
        ("goats runny nose coughing lethargic", "goat"),
    ],
)
@pytest.mark.rag
def test_retrieval_cross_topic_coverage(retriever, query, expected_keyword):
    results = retriever.retrieve(query, top_k=3)
    combined = " ".join(r["text"] for r in results).lower()
    assert expected_keyword in combined, (
        f"Expected '{expected_keyword}' in results for query: '{query}'"
    )
