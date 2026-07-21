# Maathai Desktop — System Architecture

## Overview

Maathai Desktop is a fully offline, on-device AI agricultural assistant for the ADTC 2026 Laptop LLM Challenge. It runs on an 8 GB RAM laptop with no internet required, built on `llama.cpp` with GGUF model weights.

**Primary stack:** Flutter desktop UI + `llama-server` subprocess + pure-Dart TF-IDF RAG over bilingual JSON assets.

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
┌──────────────────────────────────────────────────────────────┐
│               Maathai Desktop (Flutter Linux)                 │
│                                                              │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────┐  │
│  │  Chat Screen │  │ Knowledge Base │  │  Settings        │  │
│  │  EN / SW     │  │ Browser        │  │  Model · Locale  │  │
│  └──────┬───────┘  └────────┬───────┘  └──────────────────┘  │
│         │                   │                                 │
│  ┌──────▼───────────────────▼───────────────────────────────┐ │
│  │   PromptService + RagService (TF-IDF, in-memory)          │ │
│  └──────────────────────────┬────────────────────────────────┘ │
│                             │ localhost HTTP / SSE            │
│  ┌──────────────────────────▼────────────────────────────────┐ │
│  │         llama-server subprocess (offline)                  │ │
│  │         model/qwen2.5-3b-instruct-q4_k_m.gguf             │ │
│  └───────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

---

## Layer Descriptions

### 1. UI Layer — Flutter Desktop

| Screen | Function |
|---|---|
| **Chat** | Streaming Q&A with farm context panel, RAG source citations, `<think>` collapse |
| **Knowledge** | Browse/search bilingual corpus by category |
| **Models** | Discover, import, load/unload GGUF files via `llama-server` |
| **Settings** | Language (EN/SW), theme, sampler params (temperature, top-p, max tokens, threads) |

### 2. Application Layer (Dart)

| Service / Controller | Role |
|---|---|
| `PromptService` | ChatML prompt assembly within 4096-token budget |
| `RagService` | Pure Dart TF-IDF + cosine similarity over `assets/knowledge_base/` |
| `LlmService` | Spawn/manage `llama-server`; stream completions over localhost |
| `ModelController` | Model lifecycle + sampler configuration |
| `ChatController` | Conversation state, farm context injection, Markdown export |
| `TranslationController` | Loads `assets/i18n/{en,sw}.json` |

### 3. Inference Layer

- Binary: `llama-server` from llama.cpp (must be on `PATH`)
- Weights: GGUF Q4_K_M under `model/` (downloaded via `download_model.sh`, gitignored)
- Config: `n_ctx=4096`, `n_threads=4`, `n_gpu_layers=0`

### 4. RAG Layer

- Corpus: bilingual JSON (`content` + `content_sw`) under `assets/knowledge_base/`
- Categories: crops, pests, soil, markets, calendars, livestock
- No embedding model, no ChromaDB, no Python at Flutter runtime

---

## Competition Packaging

| Artifact | Purpose |
|---|---|
| `metadata.json` | ADTC submission metadata + test prompts |
| `download_model.sh` | Idempotent GGUF download before profiling |
| `REPORT.md` | Technical writeup + participant benchmarks |
| `submission.json` | Output of `adtc-profiler run --mode participant` |
| `LICENSE` | GNU GPL v3 |

---

## Legacy Python helpers

The `src/` and `tests/` Python trees remain for pytest helpers and historical prototyping. They are **not** required to run the Flutter desktop app. Prefer the Flutter architecture above when documenting the submission.
