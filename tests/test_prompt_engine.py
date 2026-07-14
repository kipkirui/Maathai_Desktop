"""
Tests for PromptEngine — ported logic from AgriculturalPromptService.dart
"""

import pytest
from src.llm.prompt_engine import PromptEngine


@pytest.fixture
def engine():
    return PromptEngine()


class TestBuildContextualPrompt:
    def test_includes_user_query(self, engine):
        prompt = engine.build_contextual_prompt(
            user_query="How do I control Fall Armyworm?"
        )
        assert "Fall Armyworm" in prompt
        assert "User:" in prompt or "Human:" in prompt

    def test_includes_region_context(self, engine):
        prompt = engine.build_contextual_prompt(
            user_query="What should I plant?",
            region="Nakuru",
            country="Kenya",
        )
        assert "Kenya" in prompt or "Nakuru" in prompt

    def test_includes_season_context(self, engine):
        prompt = engine.build_contextual_prompt(
            user_query="Is this a good time to plant?",
            season="Long Rains (Mar–May)",
        )
        assert "Long Rains" in prompt or "Season" in prompt

    def test_injects_rag_context(self, engine):
        rag_chunks = [
            {
                "text": "Fall Armyworm can be controlled with Emamectin benzoate.",
                "source": "pests",
                "score": 0.92,
            }
        ]
        prompt = engine.build_contextual_prompt(
            user_query="How do I control FAW?",
            rag_context=rag_chunks,
        )
        assert "Emamectin" in prompt
        assert "Knowledge Base Context" in prompt

    def test_swahili_instruction_when_language_sw(self):
        engine = PromptEngine(use_english_prompting=False)
        prompt = engine.build_contextual_prompt(
            user_query="Mahindi yangu yana magonjwa gani?",
            language="sw",
        )
        assert "Kiswahili" in prompt or "Jibu kwa Kiswahili" in prompt

    def test_no_swahili_in_system_when_use_english_prompting_true(self, engine):
        """Default behavior: system prompt stays in English for better small-model compatibility."""
        prompt = engine.build_agriculture_prompt(language="sw")
        assert "Jibu kwa Kiswahili" not in prompt  # use_english_prompting=True by default

    def test_ends_with_assistant_marker(self, engine):
        prompt = engine.build_contextual_prompt(user_query="Test question?")
        assert prompt.strip().endswith("Assistant:")


class TestBuildInsightsPrompt:
    def test_returns_string(self, engine):
        prompt = engine.build_insights_prompt({
            "timestamp": "2026-06-01T10:00:00",
            "weather": {"temp_c": 24, "rain_mm": 5},
            "fields": [{"name": "North field", "crop": "maize"}],
        })
        assert isinstance(prompt, str)
        assert len(prompt) > 50

    def test_contains_json_instruction(self, engine):
        prompt = engine.build_insights_prompt({"timestamp": "2026-06-01T10:00:00"})
        assert "JSON" in prompt


class TestBuildScannerDiagnosisPrompt:
    def test_returns_string(self, engine):
        prompt = engine.build_scanner_diagnosis_prompt(
            predicted_label="Maize Common Rust",
            confidence=0.87,
            top_k_labels=["Maize Common Rust", "Healthy", "Maize Leaf Blight"],
        )
        assert isinstance(prompt, str)
        assert "Maize Common Rust" in prompt
        assert "87.0%" in prompt

    def test_healthy_label_severity_hint(self, engine):
        prompt = engine.build_scanner_diagnosis_prompt(
            predicted_label="Healthy",
            confidence=0.95,
            top_k_labels=["Healthy"],
        )
        assert "none" in prompt.lower() or "severity" in prompt.lower()


class TestPromptCache:
    def test_cache_hit_returns_same_result(self, engine):
        p1 = engine.build_agriculture_prompt(country="Kenya", region="Nakuru")
        p2 = engine.build_agriculture_prompt(country="Kenya", region="Nakuru")
        assert p1 == p2

    def test_different_locations_differ(self, engine):
        p1 = engine.build_agriculture_prompt(country="Kenya")
        p2 = engine.build_agriculture_prompt(country="Tanzania")
        assert p1 != p2


class TestTokenBudget:
    def test_prompt_length_reasonable(self, engine):
        """Prompt should not exceed context window (4096 tokens ≈ 16384 chars)."""
        long_rag = [
            {"text": "x" * 400, "source": f"doc{i}", "score": 0.9}
            for i in range(10)
        ]
        prompt = engine.build_contextual_prompt(
            user_query="How do I grow maize?",
            rag_context=long_rag,
        )
        estimated_tokens = len(prompt) // 4
        assert estimated_tokens < 4096, (
            f"Prompt too long: {estimated_tokens} estimated tokens"
        )
