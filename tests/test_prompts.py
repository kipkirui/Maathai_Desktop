"""Domain accuracy tests on competition prompts (metadata.json tp_001, tp_002)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest

from src.llm.inference import LlamaInference
from src.llm.prompt_engine import PromptEngine
from src.rag.tfidf_retriever import TfidfRetriever

REPO_ROOT = Path(__file__).parent.parent


def _load_test_prompts() -> dict[str, str]:
    meta = json.loads((REPO_ROOT / "metadata.json").read_text(encoding="utf-8"))
    return {p["prompt_id"]: p["prompt"] for p in meta["test_prompts"]}


@pytest.fixture(scope="module")
def system(requires_model):
    llm = LlamaInference(model_path=str(requires_model))
    prompt_engine = PromptEngine()
    retriever = TfidfRetriever()
    retriever.initialize()
    yield llm, prompt_engine, retriever
    llm.release()


def _ask(system, question, max_tokens=256, country="Kenya", region="Western Kenya"):
    llm, prompt_engine, retriever = system
    context_chunks = retriever.retrieve(question, top_k=3)
    prompt = prompt_engine.build_contextual_prompt(
        user_query=question,
        rag_context=context_chunks,
        country=country,
        region=region,
    )
    return llm.generate(prompt, max_tokens=max_tokens)


@pytest.mark.accuracy
def test_tp001_maize_yellowing(system):
    """tp_001 from metadata.json — maize yellowing / nutrient or disease."""
    prompts = _load_test_prompts()
    response = _ask(system, prompts["tp_001"])

    assert len(response) > 100, "Response too short"
    response_lower = response.lower()
    assert any(
        w in response_lower
        for w in ["nitrogen", "nutrient", "deficiency", "fertilizer", "disease", "can", "urea"]
    ), "Response did not identify nutrient deficiency or disease"
    assert any(
        w in response_lower for w in ["urea", "can", "fertilizer", "apply", "top-dress", "treat"]
    ), "Response did not recommend a concrete action"


@pytest.mark.accuracy
def test_tp002_tomato_farm(system):
    """tp_002 from metadata.json — commercial tomato farm near Arusha."""
    prompts = _load_test_prompts()
    response = _ask(
        system,
        prompts["tp_002"],
        max_tokens=384,
        country="Tanzania",
        region="Arusha",
    )

    assert len(response) > 100, "Response too short"
    response_lower = response.lower()
    assert any(
        w in response_lower for w in ["tomato", "variety", "varieties", "plant", "disease"]
    ), "Response did not address tomato farming"
    assert any(
        w in response_lower
        for w in ["price", "market", "kg", "kilogram", "sell", "tzs", "income", "commercial"]
    ), "Response did not mention market expectations"


@pytest.mark.accuracy
def test_hidden_fall_armyworm(system):
    response = _ask(
        system,
        "My maize crop has caterpillars inside the whorls of young plants. "
        "The leaves show ragged holes and there is frass inside the whorl. "
        "What pest is this and how do I control it organically?",
    )
    response_lower = response.lower()
    assert any(
        w in response_lower for w in ["armyworm", "spodoptera", "fall", "pest"]
    )
    assert any(
        w in response_lower
        for w in ["neem", "organic", "biological", "trichogramma", "manual", "bt"]
    )


@pytest.mark.accuracy
def test_hidden_coffee_disease(system):
    response = _ask(
        system,
        "My coffee berries are turning black and rotting on the tree before they ripen. "
        "This is happening on berries that look fine on the outside until I open them. "
        "What disease is this and how should I manage it?",
    )
    response_lower = response.lower()
    assert any(
        w in response_lower
        for w in ["coffee berry", "cbd", "colletotrichum", "anthracnose", "fungal", "berry"]
    )
    assert any(
        w in response_lower
        for w in ["fungicide", "copper", "prune", "harvest", "control", "spray"]
    )


@pytest.mark.accuracy
def test_hidden_goat_milk_drop(system):
    """Simulated hidden prompt — goat lethargy and milk drop."""
    response = _ask(
        system,
        "I have 20 dairy goats and their milk production has dropped significantly over "
        "the past two weeks. They are eating but seem lethargic. What are the possible "
        "causes and what steps should I take to diagnose and treat this?",
    )
    response_lower = response.lower()
    assert any(
        w in response_lower
        for w in ["parasite", "worm", "infection", "disease", "nutrition", "ppr"]
    )
    assert any(
        w in response_lower
        for w in ["veterinarian", "vet", "test", "treat", "diagnose"]
    )


@pytest.mark.accuracy
def test_swahili_response(system):
    llm, prompt_engine, retriever = system
    query_sw = "Mahindi yangu yana njano. Ni tatizo gani na ninafanya nini?"

    context_chunks = retriever.retrieve(query_sw, top_k=2, language="sw")
    prompt = prompt_engine.build_contextual_prompt(
        user_query=query_sw,
        rag_context=context_chunks,
        country="Kenya",
        language="sw",
    )
    response = llm.generate(prompt, max_tokens=128)

    assert len(response.strip()) > 20, "Swahili response too short"
    swahili_words = ["mahindi", "mbolea", "udongo", "kilimo", "mmea", "mazao", "shamba", "can", "nitrogen"]
    assert any(w in response.lower() for w in swahili_words), (
        f"Response does not appear relevant: {response[:200]}"
    )
