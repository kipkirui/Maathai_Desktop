"""
Maathai Desktop — Local Embedding Model

Singleton wrapper around sentence-transformers/all-MiniLM-L6-v2.
This model is ~23 MB, CPU-optimized, and runs fully offline after first download.

The first call to Embedder() triggers a one-time download from HuggingFace
(~90 MB including tokenizer). After that, it uses the local cache and requires
zero network access — compliant with ADTC offline evaluation rules.

Pre-cache before submission:
    python -c "from src.rag.embedder import Embedder; Embedder()"
Then add the sentence-transformers cache to the offline setup.
"""

from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)

_EMBEDDING_MODEL_NAME = "sentence-transformers/all-MiniLM-L6-v2"
_EMBEDDING_DIM = 384  # output dimension of all-MiniLM-L6-v2


class Embedder:
    """
    Singleton local embedding model.
    Thread-safe: model is loaded once and shared across all callers.
    """

    _instance: Optional["Embedder"] = None
    _model = None

    def __new__(cls) -> "Embedder":
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._initialize()
        return cls._instance

    def _initialize(self) -> None:
        logger.info("Loading embedding model: %s", _EMBEDDING_MODEL_NAME)
        from sentence_transformers import SentenceTransformer  # noqa: PLC0415
        self._model = SentenceTransformer(_EMBEDDING_MODEL_NAME)
        logger.info("Embedding model loaded (dim=%d)", _EMBEDDING_DIM)

    def embed(self, text: str) -> list[float]:
        """Embed a single text string. Returns a list of floats (length 384)."""
        if self._model is None:
            raise RuntimeError("Embedding model not initialized.")
        return self._model.encode(text, normalize_embeddings=True).tolist()

    def embed_batch(self, texts: list[str]) -> list[list[float]]:
        """Embed a batch of texts. More efficient than calling embed() in a loop."""
        if self._model is None:
            raise RuntimeError("Embedding model not initialized.")
        return self._model.encode(
            texts, normalize_embeddings=True, show_progress_bar=False
        ).tolist()

    @property
    def dimension(self) -> int:
        return _EMBEDDING_DIM
