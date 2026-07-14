"""
Maathai Desktop — Runtime Configuration
"""

from pathlib import Path

# ─── Paths ─────────────────────────────────────────────────────────────────────
ROOT_DIR = Path(__file__).parent.parent
MODEL_DIR = ROOT_DIR / "model"
DATA_DIR = ROOT_DIR / "data"
CHROMA_DIR = DATA_DIR / "chroma_db"
KNOWLEDGE_BASE_DIR = Path(__file__).parent / "rag" / "knowledge_base"
ASSETS_KNOWLEDGE_BASE_DIR = ROOT_DIR / "assets" / "knowledge_base"
I18N_DIR = Path(__file__).parent / "ui" / "i18n"

# ─── Model Configuration ───────────────────────────────────────────────────────
def _resolve_model_path() -> Path:
    """Read model path from metadata.json (ADTC submission source of truth)."""
    meta_path = ROOT_DIR / "metadata.json"
    if meta_path.exists():
        import json

        meta = json.loads(meta_path.read_text(encoding="utf-8"))
        rel = meta.get("_runtime", {}).get("model_path", "")
        if rel:
            return ROOT_DIR / rel
    return MODEL_DIR / "qwen2.5-3b-instruct-q4_k_m.gguf"


MODEL_PATH = _resolve_model_path()
MODEL_FILENAME = MODEL_PATH.name

# llama.cpp inference parameters
# Ported from ModelController.dart in the Maathai mobile app
INFERENCE_CONFIG = {
    "n_ctx": 4096,          # context window
    "n_threads": 4,         # match ADTC 4 vCPU; do not exceed to avoid thermal throttling
    "n_batch": 2048,        # llama.cpp default; matches adtc-profiler llama-bench
    "n_gpu_layers": 0,      # no discrete GPU on ADTC target hardware
    "use_mmap": True,       # llama-bench default; faster load + inference
    "verbose": False,       # suppress llama.cpp log spam
}

# Sampler parameters — tuned in production Maathai mobile app
SAMPLER_CONFIG = {
    "temperature": 0.7,
    "top_k": 40,
    "top_p": 0.95,
    "repeat_penalty": 1.1,
    "max_tokens": 512,
}

# Dynamic token budget: context_length − estimated_prompt_tokens − buffer
# Matches ModelController.calculateDynamicMaxTokens() in the mobile app
TOKEN_BUFFER = 100
TOKENS_PER_CHAR_ESTIMATE = 4  # rough approximation

# ─── RAG Configuration ─────────────────────────────────────────────────────────
RAG_CONFIG = {
    "embedding_model": "sentence-transformers/all-MiniLM-L6-v2",
    "top_k": 3,              # number of chunks to retrieve
    "chunk_size": 400,       # tokens per chunk
    "chunk_overlap": 50,     # overlap between chunks
    "collection_name": "maathai_agri",
}

# ─── Language Configuration ────────────────────────────────────────────────────
DEFAULT_LANGUAGE = "en"
SUPPORTED_LANGUAGES = ["en", "sw"]

# When True: system prompt stays in English even if UI is in Swahili
# This matches the mobile app's use_english_prompting default=True
# (better compatibility with small models)
USE_ENGLISH_PROMPTING = True

# Default location context injected into {{location}} in system prompt
# Override via user settings
DEFAULT_LOCATION = "East Africa"

# ─── UI Configuration ──────────────────────────────────────────────────────────
APP_NAME = "Maathai Desktop"
APP_VERSION = "1.0.0"
WINDOW_MIN_WIDTH = 900
WINDOW_MIN_HEIGHT = 600
BENCHMARK_POLL_INTERVAL_MS = 2000   # RAM/TPS/temp polling interval
RAM_WARN_THRESHOLD_MB = 6500        # Warn in UI if approaching 7 GB limit
CPU_TEMP_WARN_C = 80                # Warn in UI if approaching 85°C penalty threshold
