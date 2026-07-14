"""Language routing tests — Swahili prompt instructions."""

from __future__ import annotations

import pytest

from src.llm.prompt_engine import PromptEngine


@pytest.fixture
def engine():
    return PromptEngine(use_english_prompting=False)


@pytest.mark.unit
def test_swahili_instruction_in_prompt(engine):
    prompt = engine.build_contextual_prompt(
        user_query="Mahindi yangu yana njano",
        language="sw",
        country="Kenya",
    )
    assert "Kiswahili" in prompt or "Swahili" in prompt or "swahili" in prompt.lower()


@pytest.mark.unit
def test_english_prompt_no_swahili_instruction(engine):
    prompt = engine.build_contextual_prompt(
        user_query="Why are my maize leaves yellow?",
        language="en",
        country="Kenya",
    )
    assert "Mahindi" not in prompt or "Why are my maize" in prompt


@pytest.mark.unit
def test_swahili_rag_passage_injection(engine):
    rag_chunks = [{"text": "Weka CAN kilo 50 kwa hekta mara moja.", "source": "crops · maize"}]
    prompt = engine.build_contextual_prompt(
        user_query="Ninafanya nini?",
        rag_context=rag_chunks,
        language="sw",
    )
    assert "CAN" in prompt or "hekta" in prompt
