"""
Maathai Desktop — RAG Retriever

Provides semantic retrieval over the offline agricultural knowledge base
using ChromaDB (embedded, file-backed) and sentence-transformers embeddings.

The knowledge base is built once by build_index.py and stored in data/chroma_db/.
At runtime, retrieval adds ~30–50ms per query — imperceptible on desktop.
"""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from src.config import CHROMA_DIR, RAG_CONFIG
from src.rag.embedder import Embedder

logger = logging.getLogger(__name__)


class Retriever:
    """
    Semantic retriever over the Maathai agricultural knowledge base.

    Usage:
        retriever = Retriever()
        chunks = retriever.retrieve("maize yellow leaves nitrogen", top_k=3)
        for chunk in chunks:
            print(chunk["text"], chunk["source"])
    """

    def __init__(self) -> None:
        self._collection = None
        self._embedder: Optional[Embedder] = None
        self._ready = False

    def initialize(self) -> bool:
        """
        Initialize ChromaDB client and load the collection.
        Returns True if collection exists and is ready; False if index needs building.
        """
        try:
            import chromadb  # noqa: PLC0415

            client = chromadb.PersistentClient(path=str(CHROMA_DIR))
            collection_name = RAG_CONFIG["collection_name"]

            existing = [c.name for c in client.list_collections()]
            if collection_name not in existing:
                logger.warning(
                    "Knowledge base index not found at %s. "
                    "Run: python -m src.rag.build_index",
                    CHROMA_DIR,
                )
                return False

            self._collection = client.get_collection(collection_name)
            self._embedder = Embedder()
            self._ready = True
            count = self._collection.count()
            logger.info("RAG retriever ready: %d chunks in collection", count)
            return True

        except ImportError:
            logger.error("chromadb not installed. Run: pip install chromadb")
            return False
        except Exception as exc:
            logger.error("Failed to initialize retriever: %s", exc)
            return False

    @property
    def is_ready(self) -> bool:
        return self._ready

    def retrieve(
        self,
        query: str,
        top_k: Optional[int] = None,
        language: str = "en",
        category_filter: Optional[str] = None,
    ) -> list[dict]:
        """
        Retrieve top-k most relevant chunks for the given query.

        Returns a list of dicts with keys:
            text    — the passage text (may be Swahili if language='sw' and available)
            source  — category/title label
            score   — relevance score (0–1, higher is better)
        """
        if not self._ready:
            logger.warning("Retriever not initialized — returning empty results")
            return []

        k = top_k or RAG_CONFIG["top_k"]
        query_embedding = self._embedder.embed(query)

        where = {}
        if category_filter:
            where["category"] = {"$eq": category_filter}

        results = self._collection.query(
            query_embeddings=[query_embedding],
            n_results=k,
            where=where if where else None,
            include=["documents", "metadatas", "distances"],
        )

        chunks = []
        docs = results.get("documents", [[]])[0]
        metas = results.get("metadatas", [[]])[0]
        dists = results.get("distances", [[]])[0]

        for doc, meta, dist in zip(docs, metas, dists):
            # ChromaDB uses L2 distance — convert to similarity (0–1)
            score = max(0.0, 1.0 - dist / 2.0)
            if score < 0.05:
                continue  # skip very low relevance

            # Use Swahili content if available and requested
            if language == "sw" and meta.get("content_sw"):
                text = meta["content_sw"]
            else:
                text = doc

            chunks.append({
                "text": text,
                "source": f"{meta.get('category', '')} · {meta.get('title', '')}",
                "category": meta.get("category", ""),
                "score": round(score, 3),
            })

        logger.debug("Retrieved %d chunks for query: %.60s…", len(chunks), query)
        return chunks
