"""
Maathai Desktop — LLM Inference Layer

Wraps llama-cpp-python to provide synchronous generation and token streaming.
Architecture ported from ModelController.dart + maathai_llamma_bridge.cpp in
the Maathai mobile app (github.com/kipkirui/Maathai_llama).

All inference is CPU-only (n_gpu_layers=0) to match the ADTC standard laptop
hardware profile (integrated GPU only, no CUDA/ROCm).
"""

from __future__ import annotations

import logging
from typing import Generator, Optional

from src.config import INFERENCE_CONFIG, SAMPLER_CONFIG, TOKEN_BUFFER, TOKENS_PER_CHAR_ESTIMATE

logger = logging.getLogger(__name__)


class LlamaInference:
    """
    llama-cpp-python wrapper with streaming support.

    Mirrors the public API of MaathaiLlamma (Dart) and ModelController.dart:
      - initialize() / release()
      - load_model(path)
      - generate(prompt, max_tokens) -> str
      - generate_stream(prompt, max_tokens) -> Generator[str]
      - cancel()
    """

    def __init__(self, model_path: Optional[str] = None) -> None:
        self._model = None
        self._model_path: Optional[str] = None
        self._cancelled = False

        # Sampler params — ported from ModelController.dart
        self.temperature: float = SAMPLER_CONFIG["temperature"]
        self.top_k: int = SAMPLER_CONFIG["top_k"]
        self.top_p: float = SAMPLER_CONFIG["top_p"]
        self.repeat_penalty: float = SAMPLER_CONFIG["repeat_penalty"]
        self.max_tokens: int = SAMPLER_CONFIG["max_tokens"]

        if model_path:
            self._load(model_path)

    # ─── Public API ────────────────────────────────────────────────────────────

    def is_loaded(self) -> bool:
        return self._model is not None

    def load_model(self, model_path: str) -> bool:
        """Load a GGUF model. Returns True on success."""
        try:
            self._load(model_path)
            return True
        except Exception as exc:
            logger.error("Failed to load model: %s", exc)
            return False

    def generate(self, prompt: str, max_tokens: Optional[int] = None) -> str:
        """Synchronous generation. Returns the full response string."""
        self._assert_loaded()
        tokens = max_tokens or self._dynamic_max_tokens(prompt)
        chunks = list(self.generate_stream(prompt, max_tokens=tokens))
        return "".join(chunks)

    def generate_stream(
        self, prompt: str, max_tokens: Optional[int] = None
    ) -> Generator[str, None, None]:
        """
        Token streaming. Yields string chunks as they are generated.
        Ported from ModelController.generateStream() in the mobile app.
        """
        self._assert_loaded()
        self._cancelled = False
        tokens = max_tokens or self._dynamic_max_tokens(prompt)

        logger.debug("GenerateStream: max_tokens=%d, prompt_len=%d", tokens, len(prompt))

        from llama_cpp import Llama  # noqa: PLC0415
        assert isinstance(self._model, Llama)

        stream = self._model.create_completion(
            prompt=prompt,
            max_tokens=tokens,
            temperature=self.temperature,
            top_k=self.top_k,
            top_p=self.top_p,
            repeat_penalty=self.repeat_penalty,
            stream=True,
            stop=["### Human:", "### User:", "<|im_end|>", "</s>", "\nUser:"],
        )
        for chunk in stream:
            if self._cancelled:
                logger.debug("Generation cancelled by user")
                break
            text = chunk["choices"][0]["text"]
            if text:
                yield text

    def cancel(self) -> None:
        """Signal the streaming generator to stop after the next chunk."""
        self._cancelled = True
        logger.info("Generation cancel requested")

    def release(self) -> None:
        """Release model weights and free memory."""
        if self._model is not None:
            # llama-cpp-python releases on GC, but explicitly del for clarity
            del self._model
            self._model = None
            self._model_path = None
            logger.info("Model released")

    def update_sampler(
        self,
        temperature: Optional[float] = None,
        top_k: Optional[int] = None,
        top_p: Optional[float] = None,
        repeat_penalty: Optional[float] = None,
    ) -> None:
        """Update sampler parameters at runtime. Ported from ModelController.updateSamplerParams."""
        if temperature is not None:
            self.temperature = temperature
        if top_k is not None:
            self.top_k = top_k
        if top_p is not None:
            self.top_p = top_p
        if repeat_penalty is not None:
            self.repeat_penalty = repeat_penalty

    # ─── Private helpers ───────────────────────────────────────────────────────

    def _load(self, model_path: str) -> None:
        """
        Load the GGUF model via llama-cpp-python.
        Ported from ModelController.loadModel() and maathai_llamma_bridge.cpp.
        """
        import os
        if not os.path.exists(model_path):
            raise FileNotFoundError(
                f"GGUF model not found: {model_path}\n"
                "Run 'bash download_model.sh' to download the weights."
            )

        logger.info("Loading model: %s", model_path)

        from llama_cpp import Llama  # noqa: PLC0415

        self._model = Llama(
            model_path=model_path,
            n_ctx=INFERENCE_CONFIG["n_ctx"],
            n_threads=INFERENCE_CONFIG["n_threads"],
            n_batch=INFERENCE_CONFIG["n_batch"],
            n_gpu_layers=INFERENCE_CONFIG["n_gpu_layers"],
            use_mmap=INFERENCE_CONFIG["use_mmap"],
            use_mlock=INFERENCE_CONFIG.get("use_mlock", False),
            flash_attn=INFERENCE_CONFIG.get("flash_attn", False),
            verbose=INFERENCE_CONFIG["verbose"],
        )
        self._model_path = model_path
        logger.info("Model loaded: %s", model_path)

    def _dynamic_max_tokens(self, prompt: str) -> int:
        """
        Calculate max tokens based on prompt length and context window.
        Ported from ModelController.calculateDynamicMaxTokens() in the mobile app.

        Formula: context_length − estimated_prompt_tokens − buffer
        Matches mobile app: 1 token ≈ 4 characters (rough approximation)
        Minimum: 50 tokens for a meaningful response.
        """
        n_ctx = INFERENCE_CONFIG["n_ctx"]
        estimated_prompt_tokens = len(prompt) // TOKENS_PER_CHAR_ESTIMATE
        available = n_ctx - estimated_prompt_tokens - TOKEN_BUFFER
        dynamic = min(self.max_tokens, available) if available > 0 else self.max_tokens
        return max(dynamic, 50)

    def _assert_loaded(self) -> None:
        if self._model is None:
            raise RuntimeError(
                "No model loaded. Call load_model(path) first or "
                "pass model_path to the constructor."
            )
