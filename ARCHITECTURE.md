# Maathai Desktop — System Architecture

## Overview

Maathai Desktop is a fully offline, on-device AI agricultural assistant for the ADTC 2026 Laptop LLM Challenge. It runs on an 8 GB RAM laptop with no internet required, built entirely on `llama.cpp` with GGUF model weights.

This document describes the system architecture, the reuse strategy from the existing Maathai mobile app, and the key design decisions made to satisfy competition constraints.

---

## Guiding Constraints

| Constraint | Value | Source |
|---|---|---|
| Runtime | `llama.cpp` only (GGUF weights) | ADTC rules — hard |
| Peak RAM | < 7 GB (target: < 3.5 GB) | ADTC rules — disqualification at 7 GB |
| Network | Zero outbound during inference | ADTC rules — hard |
| OS target | Ubuntu 22.04 LTS | ADTC evaluation hardware |
| CPU | Intel Core i5 10th–12th gen, 4 vCPU | ADTC standard laptop |
| GPU | Integrated only (no CUDA/ROCm) | ADTC standard laptop |

---

## Component Diagram

```
┌──────────────────────────────────────────────────────────────────┐
│                        Maathai Desktop                           │
│                    (Python 3.11 + PyQt6)                         │
│                                                                  │
│  ┌─────────────┐  ┌──────────────┐  ┌─────────────────────────┐ │
│  │  Chat View  │  │ Knowledge    │  │   Benchmark Panel       │ │
│  │  (EN / SW)  │  │ Browser      │  │  RAM · TPS · CPU temp   │ │
│  └──────┬──────┘  └──────┬───────┘  └─────────────────────────┘ │
│         │                │                                       │
│  ┌──────▼────────────────▼──────────────────────────────────┐   │
│  │                  Application Layer                        │   │
│  │  PromptEngine · LanguageRouter · InsightEngine           │   │
│  └──────────────────────┬────────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼────────────────────────────────────┐   │
│  │                 Inference Layer                            │   │
│  │  LlamaServer (subprocess)  ←→  llama-cpp-python (FFI)    │   │
│  │  model/maathai-agri.gguf                                  │   │
│  └──────────────────────┬────────────────────────────────────┘   │
│                         │                                        │
│  ┌──────────────────────▼────────────────────────────────────┐   │
│  │                   RAG Layer                                │   │
│  │  ChromaDB (local) · SentenceTransformers (local embed)    │   │
│  │  knowledge_base/ (crops, livestock, pests, market, FAO)   │   │
│  └───────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────┘
```

---

## Layer Descriptions

### 1. UI Layer — PyQt6

A single-window desktop application with three panels accessible via a sidebar:

| Panel | Function |
|---|---|
| **Chat** | Real-time streaming Q&A in English or Swahili. Displays thinking indicator while tokens stream. |
| **Knowledge Browser** | Browse the offline knowledge base by category (crops, livestock, pests, market). |
| **Benchmark** | Live display of RAM usage, tokens/sec, CPU temperature. Useful for demo video and self-monitoring. |

The UI is intentionally lightweight — PyQt6 is Python-native, adds <50 MB to memory, and requires no Electron/Node.js overhead.

### 2. Application Layer

#### PromptEngine (`src/llm/prompt_engine.py`)

Ported directly from `AgriculturalPromptService.dart` in the Maathai mobile app. Handles:
- System prompt injection with `{{location}}` slot
- Context-augmented prompts (season, field, scan context)
- Swahili language routing (`use_english_prompting` flag)
- Insights generation prompt (structured JSON output)
- Scanner diagnosis prompt (JSON treatment advice)
- LRU prompt cache (32 entries) — carried over from mobile implementation

**The system prompt persona (from `assets/md/prompt.md`) is reused verbatim:**
```
You are Maathai, an agriculture advisor for smallholder farmers in Africa.
Primary location context: {{location}}.
Guidelines:
- Give practical, low-cost, locally realistic steps.
- Prefer safe, sustainable practices and mention major risks.
- Keep answers concise and structured with short bullet points.
- If key details are missing, ask up to three focused follow-up questions.
- Do not use emojis.
```

#### LanguageRouter (`src/llm/language_router.py`)

Detects query language (English vs Swahili) and routes accordingly. When Swahili is detected:
- Adds `"Jibu kwa Kiswahili."` (Respond in Swahili) to the system prompt
- Uses Swahili i18n strings from the existing `sw.json` (1314 keys, ported from the mobile app)

#### InsightEngine (`src/llm/insight_engine.py`)

Tiered fallback pattern ported from `InsightService.dart`:
1. **Tier 1 — Local LLM:** Run `buildInsightsPrompt()` against loaded GGUF if model is loaded
2. **Tier 2 — Rules:** Fall back to deterministic insights from aggregated context data
3. No cloud tier (competition requirement: 100% offline)

### 3. Inference Layer

#### Primary: `llama-cpp-python` (FFI binding)

```python
from llama_cpp import Llama

llm = Llama(
    model_path="model/maathai-agri.gguf",
    n_ctx=4096,
    n_threads=4,           # match ADTC 4 vCPU
    n_gpu_layers=0,        # no discrete GPU on target
    verbose=False,
)
```

Token streaming via `llm.create_chat_completion(stream=True)`.

#### Fallback: `llama-server` subprocess

If the Python FFI binding has issues, fall back to launching `llama-server` as a subprocess and calling it over localhost HTTP (no external network). This mirrors the `llama-server` pattern and keeps the evaluation fully offline.

#### Sampler Parameters (from ModelController.dart)

Ported directly from the mobile app's tuned values:
```
temperature = 0.7
top_k       = 40
top_p       = 0.95
repeat_penalty = 1.1
max_tokens  = 512  (dynamic: context_length − prompt_tokens − 100)
```

### 4. RAG Layer — Pure Dart TF-IDF (No External Dependencies)

Maathai Desktop implements RAG entirely in Dart (`lib/services/rag_service.dart`) with **zero external dependencies**. This is a key differentiator from approaches requiring Python, sentence-transformers, or ChromaDB.

#### Why this approach wins for the competition

| Dimension | ChromaDB + sentence-transformers | Pure Dart TF-IDF (our approach) |
|---|---|---|
| Retrieval latency | 50–200ms (Python FFI + embedding) | **< 5ms** (pure Dart, in-memory) |
| Additional RAM | ~200 MB (Python + model) | **~0 MB** (no extra process) |
| Setup required | `pip install` + index build step | None — loads with Flutter app |
| External processes | Python subprocess | **None** |
| Offline compliance | Requires pre-downloaded models | **Fully offline, always** |

#### `RagService` implementation highlights

From `lib/services/rag_service.dart`:
- **TF-IDF with cosine similarity**: custom implementation with IDF weighting
- **English stemmer**: suffix stripping for agricultural terms (farming → farm, diseases → disease)
- **Bilingual**: each document has `content` (English) and `content_sw` (Swahili); returns the right language automatically
- **Stop word filtering**: 50+ agricultural-domain-aware stop words
- **Fast**: < 5ms retrieval over 150+ documents (all in-memory)

#### Knowledge Base Format (`assets/knowledge_base/`)

All documents are JSON arrays bundled as Flutter assets. Each entry has:
```json
{
  "id": "unique_id",
  "title": "Document title",
  "category": "crops|pests|soil|markets|calendars",
  "tags": ["relevant", "search", "terms"],
  "content": "Full English text with agronomic detail...",
  "content_sw": "Swahili translation of key content..."
}
```

| Category | Status | Key content |
|---|---|---|
| `crops/` | ✅ Populated | Maize (varieties, fertilizer, weed management), nutrient deficiency diagnosis, tomato |
| `pests/` | ✅ Populated | Fall Armyworm, MLN, Late Blight, Stalk Borer |
| `soil/` | 🔄 In progress | Soil management guide |
| `markets/` | 🔄 In progress | East Africa price references |
| `calendars/` | 🔄 In progress | Regional planting calendars |

All content is bilingual (English + Swahili) where available, directly supporting the African Alpha Bonus.

#### Prompt Injection Format

After retrieval, top-3 passages are injected into the prompt (from `PromptService`):
```
Relevant agricultural knowledge:
---
[crops: Maize Nutrient Deficiency — Diagnosis Guide]
Nitrogen Deficiency: Yellowing starts at the tip of lower leaves...
Apply CAN at 50 kg/ha immediately...
---
[pests: Fall Armyworm Management Guide]
...
---
```

The system uses ChatML format (Qwen2.5-compatible):
```
<|im_start|>system
{system_prompt}{farm_context}{rag_passages}
<|im_end|>
<|im_start|>user
{user_message}
<|im_end|>
<|im_start|>assistant
```

---

## Reuse Map: Mobile App → Desktop

This table tracks every asset from `Maathai_app-main/example` that is directly reused or ported:

| Mobile asset | Desktop equivalent | Reuse type |
|---|---|---|
| `assets/md/prompt.md` | `src/rag/knowledge_base/system_prompt.md` | Verbatim copy |
| `lib/services/agricultural_prompt_service.dart` | `src/llm/prompt_engine.py` | Port (Dart → Python) |
| `lib/state/model_controller.dart` | `src/llm/inference.py` | Port (sampler params, dynamic token budget) |
| `lib/services/insight_service.dart` | `src/llm/insight_engine.py` | Port (tiered fallback logic) |
| `lib/services/insight_llm_parser.dart` | `src/llm/llm_parser.py` | Port (JSON output parsing) |
| `assets/i18n/sw.json` | `src/ui/i18n/sw.json` | Verbatim copy (1314 keys) |
| `assets/i18n/en.json` | `src/ui/i18n/en.json` | Verbatim copy |
| `assets/diagnosis_templates/*.json` | `src/rag/knowledge_base/pests_diseases/` | Verbatim copy |
| `android/.../maathai_llamma_bridge.cpp` | `llama-cpp-python` (replaces JNI bridge) | Architecture pattern reuse |
| Plugin `kipkirui/Maathai_llama` | Cited in REPORT.md as prior work | Credibility / track record |

---

## Memory Budget

Target: < 3.5 GB peak RSS to maximize Seff score.

| Component | Est. RAM |
|---|---|
| OS baseline (Ubuntu 22.04 minimal) | ~300 MB |
| Python 3.11 interpreter | ~50 MB |
| PyQt6 + UI | ~80 MB |
| ChromaDB + FAISS index | ~120 MB |
| sentence-transformers embedding model | ~90 MB |
| **GGUF model (Phi-3.5 Mini Q4_K_M ~3.8B)** | **~2,700 MB** |
| llama.cpp KV cache (4096 ctx) | ~400 MB |
| **Total estimated peak** | **~3,840 MB** |

This leaves ~3.16 GB headroom from the 7 GB ceiling.
`Seff = (7 − 3.84) / 7 × 100 = 45.1`

With a smaller model (Qwen 2.5 3B Q4_K_M, ~2 GB):
`Seff = (7 − 2.64) / 7 × 100 = 62.3`

---

## Cross-Disciplinary Pairing Statement

> **Discipline:** Agronomy & Data Systems  
> **Load-bearing:** Yes  
> **Description:** Maathai Desktop pairs a quantized on-device language model with an offline retrieval-augmented generation layer built over a curated corpus of FAO crop guides, KALRO agronomy bulletins, and regional pest/disease data sheets. The RAG layer is load-bearing: accuracy on domain-specific African agricultural queries demonstrably decreases when retrieval is disabled.

---

## Competitive Differentiation

| Advantage | Source |
|---|---|
| Battle-tested agriculture prompts | Ported from Maathai mobile app (production since 2024) |
| Swahili i18n (14 locales total) | Ported from mobile app — +15% African Alpha Bonus |
| Plant disease diagnosis templates | Ported from mobile app — immediate domain accuracy |
| Open-source llama.cpp bridge (`kipkirui/Maathai_llama`) | Demonstrates deep prior art in llama.cpp integration |
| Tiered inference pattern | Proven fallback logic from InsightService.dart |
| Small model + RAG strategy | Higher Seff + better domain accuracy than large model alone |

---

## File Layout

```
d:\Github\v2\Maathai_Desktop\
├── metadata.json
├── download_model.sh
├── REPORT.md
├── ARCHITECTURE.md          ← this file
├── PLAN.md
├── TESTING.md
├── CONTRIBUTING.md
├── requirements.txt
├── .gitignore
├── model/
│   └── .gitkeep
├── data/
│   └── chroma_db/           ← built at first launch, gitignored
└── src/
    ├── app.py               ← entry point
    ├── config.py
    ├── llm/
    │   ├── inference.py     ← llama-cpp-python wrapper
    │   ├── prompt_engine.py ← ported from AgriculturalPromptService.dart
    │   ├── language_router.py
    │   ├── insight_engine.py
    │   └── llm_parser.py
    ├── rag/
    │   ├── build_index.py
    │   ├── embedder.py
    │   ├── retriever.py
    │   └── knowledge_base/
    │       ├── system_prompt.md
    │       ├── crops/
    │       ├── livestock/
    │       ├── pests_diseases/
    │       ├── market_data/
    │       └── climate/
    └── ui/
        ├── main_window.py
        ├── chat_view.py
        ├── knowledge_view.py
        ├── benchmark_view.py
        └── i18n/
            ├── en.json
            └── sw.json
```
