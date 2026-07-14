"""
TF-IDF retriever over assets/knowledge_base — mirrors lib/services/rag_service.dart.

Used by pytest for RAG quality tests without ChromaDB or embedding models.
"""

from __future__ import annotations

import json
import math
import re
from pathlib import Path

from src.config import ASSETS_KNOWLEDGE_BASE_DIR, ROOT_DIR

_STOP_WORDS = {
    "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
    "of", "with", "by", "from", "is", "are", "was", "were", "be", "been",
    "has", "have", "had", "do", "does", "did", "will", "would", "could",
    "should", "may", "might", "can", "this", "that", "these", "those",
    "it", "its", "my", "your", "our", "their", "what", "how", "when",
    "where", "why", "which", "who", "all", "also", "not", "more", "very",
}


def _stem(word: str) -> str:
    if word.endswith("ing") and len(word) > 5:
        return word[:-3]
    if word.endswith("tion") and len(word) > 5:
        return word[:-4]
    if word.endswith("ment") and len(word) > 5:
        return word[:-4]
    if word.endswith("ness") and len(word) > 5:
        return word[:-4]
    if word.endswith("ies") and len(word) > 4:
        return word[:-3] + "y"
    if word.endswith("es") and len(word) > 4:
        return word[:-2]
    if word.endswith("ed") and len(word) > 4:
        return word[:-2]
    if word.endswith("er") and len(word) > 4:
        return word[:-2]
    if word.endswith("s") and len(word) > 3:
        return word[:-1]
    return word


def _tokenize(text: str) -> dict[str, float]:
    words = [
        _stem(w)
        for w in re.sub(r"[^a-z\s]", " ", text.lower()).split()
        if len(w) > 2 and w not in _STOP_WORDS
    ]
    if not words:
        return {}
    tf: dict[str, float] = {}
    for word in words:
        tf[word] = tf.get(word, 0.0) + 1.0
    for key in tf:
        tf[key] /= len(words)
    return tf


class _Document:
    def __init__(self, entry: dict, category: str) -> None:
        self.id = entry.get("id", "")
        self.title = entry.get("title", "")
        self.category = category
        self.content_en = entry.get("content", "")
        self.content_sw = entry.get("content_sw")
        full_text = f"{self.title} {self.content_en} {' '.join(entry.get('tags', []))}".lower()
        words = [
            _stem(w)
            for w in re.sub(r"[^a-z\s]", " ", full_text).split()
            if len(w) > 2 and w not in _STOP_WORDS
        ]
        self.terms: dict[str, float] = {}
        for word in words:
            self.terms[word] = self.terms.get(word, 0.0) + 1.0
        if words:
            for key in self.terms:
                self.terms[key] /= len(words)

    def passage(self, language: str = "en") -> str:
        content = self.content_sw if language == "sw" and self.content_sw else self.content_en
        trimmed = content[:800] + "…" if len(content) > 800 else content
        return f"[{self.category}: {self.title}]\n{trimmed}"


class TfidfRetriever:
    """In-memory TF-IDF retriever — same algorithm as Flutter RagService."""

    def __init__(self, kb_dir: Path | None = None) -> None:
        self._kb_dir = kb_dir or ASSETS_KNOWLEDGE_BASE_DIR
        self._documents: list[_Document] = []
        self._idf: dict[str, float] = {}
        self._ready = False

    def initialize(self) -> bool:
        self._documents.clear()
        if not self._kb_dir.exists():
            return False

        for json_path in sorted(self._kb_dir.rglob("*.json")):
            category = json_path.parent.name
            try:
                entries = json.loads(json_path.read_text(encoding="utf-8"))
            except (json.JSONDecodeError, OSError):
                continue
            if not isinstance(entries, list):
                continue
            for entry in entries:
                if isinstance(entry, dict):
                    self._documents.append(_Document(entry, category))

        self._build_idf()
        self._ready = bool(self._documents)
        return self._ready

    def is_ready(self) -> bool:
        return self._ready

    def _build_idf(self) -> None:
        df: dict[str, int] = {}
        for doc in self._documents:
            for term in doc.terms:
                df[term] = df.get(term, 0) + 1
        n = float(len(self._documents))
        self._idf = {
            term: math.log((n + 1) / (count + 1)) + 1.0
            for term, count in df.items()
        }

    def _cosine(self, query: dict[str, float], doc_tf: dict[str, float]) -> float:
        dot = query_norm = doc_norm = 0.0
        for term, q_tf in query.items():
            idf = self._idf.get(term, 1.0)
            q_tfidf = q_tf * idf
            d_tfidf = doc_tf.get(term, 0.0) * idf
            dot += q_tfidf * d_tfidf
            query_norm += q_tfidf * q_tfidf
        for term, d_tf in doc_tf.items():
            idf = self._idf.get(term, 1.0)
            d_tfidf = d_tf * idf
            doc_norm += d_tfidf * d_tfidf
        if query_norm == 0 or doc_norm == 0:
            return 0.0
        return dot / (math.sqrt(query_norm) * math.sqrt(doc_norm))

    def retrieve(
        self,
        query: str,
        top_k: int = 3,
        language: str = "en",
        min_score: float = 0.05,
    ) -> list[dict]:
        if not self._ready:
            return []

        query_terms = _tokenize(query)
        if not query_terms:
            return []

        scores = [
            (i, self._cosine(query_terms, doc.terms))
            for i, doc in enumerate(self._documents)
        ]
        scores.sort(key=lambda x: x[1], reverse=True)

        results = []
        for idx, score in scores:
            if score < min_score or len(results) >= top_k:
                break
            doc = self._documents[idx]
            results.append({
                "text": doc.passage(language),
                "source": f"{doc.category} · {doc.title}",
                "category": doc.category,
                "score": round(score, 3),
            })
        return results
