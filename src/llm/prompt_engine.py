"""
Maathai Desktop — Prompt Engine

Direct Python port of AgriculturalPromptService.dart from the Maathai mobile app.
Source: D:/Github/v2/Maathai_app-main/example/lib/services/agricultural_prompt_service.dart

Key decisions carried over from the mobile app:
- Compact system prompt to minimize prefill time (faster time-to-first-token)
- {{location}} placeholder resolved from user config
- Prompt LRU cache (32 entries) to avoid rebuilding identical prompts
- use_english_prompting flag: keeps system prompt in English for better small-model
  compatibility, while UI and query can be in Swahili
"""

from __future__ import annotations

import json
import logging
from pathlib import Path
from typing import Optional

from src.config import (
    DEFAULT_LANGUAGE,
    DEFAULT_LOCATION,
    KNOWLEDGE_BASE_DIR,
    USE_ENGLISH_PROMPTING,
)

logger = logging.getLogger(__name__)

_LOCATION_PLACEHOLDER = "{{location}}"
_MAX_PROMPT_CACHE_ENTRIES = 32
_PROMPT_ASSET_PATH = KNOWLEDGE_BASE_DIR / "system_prompt.md"


class PromptEngine:
    """
    Builds agriculture-domain prompts for all four scenarios used in Maathai:
      1. build_agriculture_prompt()      — system prompt with location context
      2. build_contextual_prompt()       — system + user query (main chat)
      3. build_insights_prompt()         — structured JSON output for dashboard
      4. build_scanner_diagnosis_prompt() — JSON treatment advice after TFLite label

    Ported from AgriculturalPromptService.dart. API surface is kept close to
    the original to make cross-referencing easy during development.
    """

    _prompt_template_cache: Optional[str] = None
    _prompt_cache: dict[str, str] = {}

    def __init__(self, use_english_prompting: bool = USE_ENGLISH_PROMPTING) -> None:
        self.use_english_prompting = use_english_prompting

    # ─── Public API ────────────────────────────────────────────────────────────

    def build_agriculture_prompt(
        self,
        country: Optional[str] = None,
        region: Optional[str] = None,
        language: Optional[str] = None,
    ) -> str:
        """
        Build agriculture-focused system prompt with location context.
        Equivalent to AgriculturalPromptService.buildAgriculturePrompt().
        """
        location = self._resolve_location(country, region)
        lang_suffix = f"|{language}" if language and language != DEFAULT_LANGUAGE else ""
        prompting_suffix = "|en_prompt" if self.use_english_prompting else "|native_prompt"
        cache_key = f"sys|{location}{lang_suffix}{prompting_suffix}"
        if cached := self._prompt_cache.get(cache_key):
            return cached

        template = self._load_prompt_template()
        if _LOCATION_PLACEHOLDER in template:
            resolved = template.replace(_LOCATION_PLACEHOLDER, location).strip()
        else:
            resolved = f"{template}\n\nLocation context: {location}".strip()

        # Optionally append language instruction (Swahili support)
        if not self.use_english_prompting and language and language != DEFAULT_LANGUAGE:
            lang_instruction = self._language_instruction(language)
            if lang_instruction:
                resolved = f"{resolved}\n{lang_instruction}"

        self._cache_prompt(cache_key, resolved)
        return resolved

    def build_contextual_prompt(
        self,
        user_query: str,
        country: Optional[str] = None,
        region: Optional[str] = None,
        language: Optional[str] = None,
        season: Optional[str] = None,
        rag_context: Optional[list[dict]] = None,
    ) -> str:
        """
        Build contextual prompt with user query and optional RAG context.
        Equivalent to AgriculturalPromptService.buildContextualPrompt().

        The RAG context (list of retrieved chunks) is injected before the user
        query — this is new in the desktop version (mobile had no RAG layer).
        """
        system_prompt = self.build_agriculture_prompt(
            country=country, region=region, language=language
        )

        parts = [system_prompt]

        if season:
            parts.append(
                f"\nCurrent Season: {season} — Consider seasonal timing for all recommendations."
            )

        if rag_context:
            context_text = self._format_rag_context(rag_context)
            if context_text:
                parts.append(f"\nKnowledge Base Context:\n{context_text}")

        parts.append(f"\nUser: {user_query.strip()}\n\nAssistant:")
        return "".join(parts)

    def build_insights_prompt(self, context_data: dict) -> str:
        """
        Build prompt for offline dashboard insights from aggregated farm context.
        Equivalent to AgriculturalPromptService.buildInsightsPrompt().
        Output contract: JSON array of insight objects.
        """
        system_prompt = self.build_agriculture_prompt()
        context_json = json.dumps(context_data, ensure_ascii=False)
        from datetime import datetime, timedelta
        timestamp = context_data.get("timestamp", datetime.now().isoformat())
        try:
            expires_example = (
                datetime.fromisoformat(timestamp) + timedelta(days=5)
            ).isoformat()
        except ValueError:
            expires_example = (datetime.now() + timedelta(days=5)).isoformat()

        return f"""{system_prompt}

TASK: Generate 3 to 5 short agricultural insights for the farmer home dashboard using ONLY the facts in CONTEXT. Do not invent scans, weather readings, tasks, or fields that are not in CONTEXT.

CONTEXT (JSON):
{context_json}

OUTPUT: Reply with ONLY a JSON array (no markdown fences, no commentary). Each element must be an object with:
- "id": unique string
- "text": practical advice, max 200 characters, no emojis
- "type": one of scan, weather, task, preventive, general
- "priority": one of critical, high, medium, low
- "fieldId": string or null
- "fieldName": string or null
- "expiresAt": ISO-8601 datetime string (3 to 7 days after {timestamp}) or null

Rules:
- Use type "scan" only when derived from scans in CONTEXT; "weather" from weather; "task" from tasks; otherwise preventive or general.
- Use critical or high priority only when CONTEXT shows an urgent issue.
- Do not recommend specific chemical products or dosages unless they appear in CONTEXT.
- If CONTEXT has no actionable data, return a single general insight encouraging the farmer to add fields, scans, or tasks.

JSON array:""".strip()

    def build_scanner_diagnosis_prompt(
        self,
        predicted_label: str,
        confidence: float,
        top_k_labels: list[str],
        country: Optional[str] = None,
        region: Optional[str] = None,
    ) -> str:
        """
        Build prompt for plant scan advice after TFLite classification.
        Equivalent to AgriculturalPromptService.buildScannerDiagnosisPrompt().
        Output contract: JSON object with description, treatmentName, treatmentDescription, severity.
        """
        system_prompt = self.build_agriculture_prompt(country=country, region=region)
        top_k = ", ".join(top_k_labels)
        confidence_pct = f"{confidence * 100:.1f}"

        return f"""{system_prompt}

TASK: Write brief farmer-facing advice for a plant scan. The on-device vision model already chose the label — do NOT change the diagnosis name.

CLASSIFIER OUTPUT:
- predicted_label: {predicted_label}
- confidence: {confidence_pct}%
- top_k: {top_k}

OUTPUT: Reply with ONLY a JSON object (no markdown):
{{
  "description": "2-3 sentences explaining the issue in plain language",
  "treatmentName": "short treatment title",
  "treatmentDescription": "practical steps without inventing product names or dosages",
  "severity": "none|low|moderate|high|critical"
}}

Rules:
- Use only facts implied by the label; if label contains "healthy", severity must be "none".
- Do not invent chemical products or exact dosages.
- Keep each field under 300 characters. No emojis.""".strip()

    @staticmethod
    def get_default_agriculture_prompt() -> str:
        """
        Fallback prompt when the asset file cannot be loaded.
        Ported from AgriculturalPromptService.getDefaultAgriculturePrompt().
        """
        return (
            "You are Maathai, an agriculture advisor for smallholder farmers in Africa. "
            "Provide practical, low-cost, locally realistic guidance with clear safety notes "
            "for chemicals and tools. If essential details are missing, ask up to three brief "
            "questions or recommend consulting a local extension officer. Use short sections "
            "with bullet-point steps and no emojis."
        )

    @classmethod
    def warmup(cls) -> None:
        """Preload template cache so the first chat send is not blocked."""
        engine = cls()
        engine.build_agriculture_prompt()

    # ─── Private helpers ───────────────────────────────────────────────────────

    def _resolve_location(self, country: Optional[str], region: Optional[str]) -> str:
        c = country or DEFAULT_LOCATION
        if region:
            return f"{c}, {region}"
        return c

    def _load_prompt_template(self) -> str:
        if PromptEngine._prompt_template_cache:
            return PromptEngine._prompt_template_cache

        try:
            content = _PROMPT_ASSET_PATH.read_text(encoding="utf-8").strip()
            if content:
                PromptEngine._prompt_template_cache = content
                return content
        except (FileNotFoundError, OSError) as exc:
            logger.warning("Could not load prompt template from %s: %s", _PROMPT_ASSET_PATH, exc)

        fallback = self.get_default_agriculture_prompt()
        PromptEngine._prompt_template_cache = fallback
        return fallback

    @staticmethod
    def _language_instruction(language: str) -> str:
        instructions = {
            "sw": "Jibu kwa Kiswahili.",
            "ha": "Amsa da Hausa.",
            "zu": "Phendula ngesiZulu.",
            "am": "በአማርኛ ምላሽ ስጥ።",
        }
        return instructions.get(language, "")

    @staticmethod
    def _format_rag_context(chunks: list[dict]) -> str:
        """Format retrieved RAG chunks for injection into the prompt."""
        parts = []
        for i, chunk in enumerate(chunks, 1):
            source = chunk.get("source", "knowledge base")
            text = chunk.get("text", "").strip()
            if text:
                parts.append(f"[{i}] ({source})\n{text}")
        return "\n\n".join(parts)

    @classmethod
    def _cache_prompt(cls, key: str, value: str) -> None:
        """LRU-style cache eviction when at capacity. Ported from mobile app."""
        if len(cls._prompt_cache) >= _MAX_PROMPT_CACHE_ENTRIES:
            oldest_key = next(iter(cls._prompt_cache))
            del cls._prompt_cache[oldest_key]
        cls._prompt_cache[key] = value
