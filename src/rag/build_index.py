"""
Maathai Desktop — Knowledge Base Index Builder

Reads all JSON files from assets/knowledge_base/, extracts text passages,
embeds them with sentence-transformers/all-MiniLM-L6-v2, and stores in ChromaDB.

Run once before first use (or after adding new knowledge base files):
    python -m src.rag.build_index

The index is stored in data/chroma_db/ and reused on subsequent app launches.
This process requires internet access to download the embedding model the FIRST time;
after that it runs 100% offline — compliant with ADTC evaluation rules.
"""

from __future__ import annotations

import json
import logging
import sys
from pathlib import Path

logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
logger = logging.getLogger(__name__)

# Allow running as __main__ from repo root
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from src.config import CHROMA_DIR, RAG_CONFIG  # noqa: E402
from src.rag.embedder import Embedder  # noqa: E402

KNOWLEDGE_BASE_DIR = Path(__file__).parent.parent.parent / "assets" / "knowledge_base"
CATEGORIES = ["crops", "pests", "soil", "markets", "calendars"]


def load_knowledge_base() -> list[dict]:
    """Load all JSON files from the knowledge base directory."""
    documents = []

    for category in CATEGORIES:
        category_dir = KNOWLEDGE_BASE_DIR / category
        if not category_dir.exists():
            logger.warning("Category directory not found: %s", category_dir)
            continue

        for json_file in category_dir.glob("*.json"):
            try:
                entries = json.loads(json_file.read_text(encoding="utf-8"))
                for entry in entries:
                    if not isinstance(entry, dict):
                        continue
                    entry["category"] = category
                    documents.append(entry)
                logger.info("Loaded %d entries from %s", len(entries), json_file.name)
            except (json.JSONDecodeError, OSError) as exc:
                logger.error("Failed to load %s: %s", json_file, exc)

    return documents


def chunk_document(doc: dict) -> list[dict]:
    """
    Split a document into overlapping chunks for more granular retrieval.
    Smaller chunks = better retrieval precision.
    """
    content = doc.get("content", "")
    content_sw = doc.get("content_sw", "")
    title = doc.get("title", "")
    category = doc.get("category", "")
    doc_id = doc.get("id", "")
    tags = doc.get("tags", [])

    chunk_size = RAG_CONFIG["chunk_size"] * 4  # chars (~400 tokens * 4 chars/token)
    overlap = RAG_CONFIG["chunk_overlap"] * 4

    chunks = []

    # Split content into paragraphs first
    paragraphs = [p.strip() for p in content.split("\n\n") if p.strip()]

    current_chunk = []
    current_len = 0

    for para in paragraphs:
        para_len = len(para)

        if current_len + para_len > chunk_size and current_chunk:
            chunk_text = "\n\n".join(current_chunk)
            chunks.append({
                "text": chunk_text,
                "content_sw": content_sw[:800] if content_sw else "",
                "title": title,
                "category": category,
                "doc_id": doc_id,
                "tags": tags,
            })
            # Overlap: keep last paragraph
            current_chunk = current_chunk[-1:] if overlap > 0 else []
            current_len = len(current_chunk[0]) if current_chunk else 0

        current_chunk.append(para)
        current_len += para_len

    if current_chunk:
        chunks.append({
            "text": "\n\n".join(current_chunk),
            "content_sw": content_sw[:800] if content_sw else "",
            "title": title,
            "category": category,
            "doc_id": doc_id,
            "tags": tags,
        })

    # Also add a title + tags chunk for better keyword recall
    tags_text = f"{title}. Topics: {', '.join(tags)}. Category: {category}."
    chunks.insert(0, {
        "text": tags_text,
        "content_sw": "",
        "title": title,
        "category": category,
        "doc_id": f"{doc_id}_tags",
        "tags": tags,
    })

    return chunks


def build_index(force_rebuild: bool = False) -> int:
    """
    Build the ChromaDB vector index from the knowledge base JSON files.
    Returns the number of chunks indexed.
    """
    import chromadb  # noqa: PLC0415

    CHROMA_DIR.mkdir(parents=True, exist_ok=True)
    client = chromadb.PersistentClient(path=str(CHROMA_DIR))
    collection_name = RAG_CONFIG["collection_name"]

    # Delete existing collection if rebuilding
    existing = [c.name for c in client.list_collections()]
    if collection_name in existing:
        if not force_rebuild:
            logger.info("Index already exists (%s). Use --force to rebuild.", collection_name)
            collection = client.get_collection(collection_name)
            return collection.count()
        logger.info("Rebuilding index: deleting existing collection")
        client.delete_collection(collection_name)

    collection = client.create_collection(
        name=collection_name,
        metadata={"hnsw:space": "l2"},
    )

    # Load documents
    documents = load_knowledge_base()
    if not documents:
        logger.error("No documents found in %s", KNOWLEDGE_BASE_DIR)
        return 0

    logger.info("Loaded %d documents; chunking...", len(documents))

    # Chunk all documents
    all_chunks = []
    for doc in documents:
        all_chunks.extend(chunk_document(doc))

    logger.info("Created %d chunks; embedding...", len(all_chunks))

    # Embed in batches
    embedder = Embedder()
    batch_size = 64
    total_indexed = 0

    for i in range(0, len(all_chunks), batch_size):
        batch = all_chunks[i : i + batch_size]
        texts = [c["text"] for c in batch]

        embeddings = embedder.embed_batch(texts)

        ids = [f"{c['doc_id']}_{i + j}" for j, c in enumerate(batch)]
        metadatas = [
            {
                "title": c["title"],
                "category": c["category"],
                "doc_id": c["doc_id"],
                "content_sw": c.get("content_sw", ""),
                "tags": ",".join(c.get("tags", [])),
            }
            for c in batch
        ]

        collection.add(
            ids=ids,
            embeddings=embeddings,
            documents=texts,
            metadatas=metadatas,
        )
        total_indexed += len(batch)
        logger.info("  Indexed %d/%d chunks", total_indexed, len(all_chunks))

    logger.info("✓ Index built: %d chunks in collection '%s'", total_indexed, collection_name)
    return total_indexed


if __name__ == "__main__":
    force = "--force" in sys.argv
    count = build_index(force_rebuild=force)
    print(f"\n✓ Knowledge base index ready: {count} chunks")
