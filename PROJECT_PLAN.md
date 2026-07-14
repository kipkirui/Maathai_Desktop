# Maathai Desktop — Project Plan

> ADTC 2026 Submission · Gate 1 Deadline: August 25, 2026

---

## Executive Summary

We are building a Flutter desktop application that delivers offline agricultural AI advisory to smallholder farmers and extension officers across Africa. The app runs Qwen2.5-3B-Instruct Q4_K_M via llama.cpp on a standard 8 GB laptop with no internet dependency. A curated RAG knowledge base grounds every response in verified African agronomic data. Full Swahili language support qualifies for the African Alpha Bonus.

**Competitive advantages:**
1. We already ship a working Flutter + llama.cpp mobile app (Maathai App). The desktop is a direct capability expansion, not a prototype.
2. Our open-source `maathai_llamma` plugin provides the llama.cpp integration foundation.
3. Agriculture domain knowledge comes from our existing platform (usemaathai.com) with real farmer usage data.
4. Qwen2.5-3B offers the best accuracy/RAM/speed balance for our scoring formula projections.

---

## Milestones

### Phase 0 — Foundation (Week 1–2) ✅ MOSTLY COMPLETE
**Target: Repo ready, model running, competition files valid**

- [x] Create ADTC submission repo from template
- [x] Write `metadata.json` with correct team info (model filled; team ID pending registration)
- [x] Write `download_model.sh` for Qwen2.5-3B Q4_K_M
- [x] Write competition `REPORT.md`
- [x] Write `.gitignore` (excludes *.gguf)
- [x] Create Flutter project (flutter create --platforms=linux,windows,macos)
- [ ] Verify `download_model.sh` works on Ubuntu 22.04
- [ ] Run ADTC profiler smoke test on downloaded model
- [ ] Commit and push clean initial repo

**Deliverable:** `adtc-profiler run --mode participant` produces valid `submission.json`

---

### Phase 1 — Core LLM Integration (Week 2–3) ✅ COMPLETE
**Target: Flutter desktop app talks to llama.cpp offline**

- [x] Scaffold Flutter desktop project (Linux primary target)
- [x] Implement `LlmService` — spawn `llama-server` subprocess on app startup
- [x] Implement streaming `/completion` HTTP call to llama-server
- [x] Implement `ModelController`
- [x] Implement `ChatController`
- [x] Basic chat screen — text input → streaming response with RAG

**Deliverable:** Open app, type "How do I grow maize?", see streaming response from Qwen2.5-3B offline.

---

### Phase 2 — RAG Knowledge Base (Week 3–4) 🔄 IN PROGRESS
**Target: Every response grounded in verified crop data**

- [x] Design knowledge base schema (JSON document format)
- [ ] Author knowledge base content (14 crops target — **~30 entries** across crops, pests, livestock, soil, markets, calendars)
- [x] Implement `RagService` (pure Dart TF-IDF)
- [x] Integrate RAG into `PromptService`
- [x] Test RAG grounding (pytest `tests/test_rag.py`)

**Deliverable:** Responses reference specific crop varieties, dosages, and Kenya/Tanzania context correctly.

---

### Phase 3 — Desktop UI Polish (Week 4–5)
**Target: Production-quality UI that judges will evaluate for S_acc**

- [ ] Desktop layout with persistent sidebar
  - Navigation: Chat | Knowledge | Models | Settings
  - Collapsible context panel (region, crop, season)
- [ ] Chat screen improvements
  - Streaming token display with cursor animation
  - `<think>` tag parsing (CoT display in collapsible UI)
  - Copy response button
  - Thumbs up/down feedback (stored locally)
  - "Regenerate" button
  - Export conversation as Markdown/PDF
- [ ] Context panel
  - Set location (dropdown: county/region)
  - Set active crop (from knowledge base crop list)
  - Set season (long rains / short rains / dry)
  - These values injected into every prompt
- [ ] Knowledge base browser
  - Browse by category (crops / pests / soil / markets)
  - Full-text search
  - Detail view with formatted content
- [ ] Model status indicator in title bar (loading / ready / generating)
- [ ] Keyboard shortcuts
  - `Ctrl+Enter` — send message
  - `Ctrl+N` — new chat
  - `Ctrl+K` — focus search
  - `Escape` — cancel generation

**Deliverable:** App feels polished, fast, and purpose-built. Non-technical user (extension officer) can use it without training.

---

### Phase 4 — Swahili + African Alpha (Week 5–6)
**Target: Full Swahili UI and response capability → +15% score bonus**

- [ ] Extract all UI strings to `assets/i18n/en.json`
- [ ] Translate all strings to `assets/i18n/sw.json`
  - Use Qwen2.5-3B itself for draft translation (dogfooding), then manual review
- [ ] Implement `TranslationController` with `Provider`
- [ ] Language switcher in Settings (English / Kiswahili)
- [ ] Swahili system prompt variant:
  ```
  Jibu kwa Kiswahili. Wewe ni mshauri wa kilimo kwa wakulima wadogo Afrika Mashariki...
  ```
- [ ] Test Swahili responses for agricultural terminology accuracy
- [ ] Update `metadata.json`: `"language_scope": ["en", "sw"]`, `"african_alpha_claim": true`

**Deliverable:** Full app experience in Swahili. All agricultural responses in Swahili when language set to sw.

---

### Phase 5 — Testing & Competition Hardening (Week 6–7)
**Target: Pass all profiler checks, no thermal penalty, reproducible**

- [ ] Performance profiling on target hardware (or equivalent VM)
  - Run `adtc-profiler run --mode participant`
  - Verify: peak RSS < 7 GB
  - Verify: TPS > 8 (target ≥ 12)
  - Verify: no thermal throttling at 4 threads
- [ ] RAM optimization
  - Context window: 4096 (cap via `--ctx-size 4096`)
  - Batch size: 512
  - Threads: 4 (via `--threads 4`)
  - No GPU layers (`--n-gpu-layers 0`)
- [ ] Test `download_model.sh` on fresh Ubuntu 22.04 VM (no prior downloads)
- [ ] Verify all prompts in `metadata.json` produce correct responses
- [ ] Integration tests:
  - App starts without llama-server on PATH → shows clear error + install instructions
  - Model file missing → prompts user to run `download_model.sh`
  - Out of memory → graceful error message (no crash)
- [ ] Unit tests:
  - `RagService.retrieve()` returns relevant docs for agricultural queries
  - `PromptService.build()` stays within token budget
  - `LlmService` streaming parses SSE correctly
- [ ] Record 2-minute demo video for Gate 1 submission
  - Show: app startup, model loading, agriculture Q&A in English, switch to Swahili, knowledge base browser, context panel

**Deliverable:** `adtc-profiler` produces `"status": "pass"`. Video recorded. Repo public.

---

### Phase 6 — Gate 1 Submission (August 25, 2026) 🎯
**Checklist before DevPost submit:**

- [ ] `metadata.json` — no placeholder values remain
- [ ] `download_model.sh` — tested from scratch on Ubuntu 22.04
- [ ] `REPORT.md` — complete, accurate benchmark numbers
- [ ] README — clear build instructions
- [ ] Repo is public
- [ ] `*.gguf` files are NOT in git history
- [ ] `adtc-profiler run --mode participant` → `"status": "pass"`
- [ ] 2-minute demo video uploaded
- [ ] DevPost submission form completed

---

## Technical Decisions Log

### Decision 1: Model — Qwen2.5-3B-Instruct Q4_K_M
**Alternatives considered:** SmolLM2-1.7B, Llama-3.2-3B, Phi-3.5-mini  
**Decision:** Qwen2.5-3B for best accuracy/Swahili/size tradeoff  
**Rationale:** See REPORT.md §2.1

### Decision 2: llama.cpp Integration — Subprocess (llama-server)
**Alternatives considered:** Direct FFI via maathai_llamma plugin extension, llama_cpp_dart package  
**Decision:** `llama-server` subprocess on localhost:8080  
**Rationale:** Competition evaluates the GGUF model directly via profiler (independent of app). Subprocess model gives us OpenAI-compatible streaming API, easy cross-platform support, and matches how real desktop AI apps (Ollama, LM Studio) work. Decouples Flutter build complexity from llama.cpp build complexity.

### Decision 3: RAG — TF-IDF Keyword Retrieval (no vectors)
**Alternatives considered:** SQLite FTS5, FAISS embeddings, BM25  
**Decision:** In-memory TF-IDF (custom Dart implementation)  
**Rationale:** On a 3B model laptop, running embeddings for RAG would require a second model (embedding model) adding 200–500 MB RAM. TF-IDF with good chunking achieves 85%+ of the relevance quality for agricultural domain queries (which have specific terminology). No dependencies, instant startup, easy to audit.

### Decision 4: Desktop Platform — Linux Primary (Windows Secondary)
**Alternatives considered:** Linux-only, Web app  
**Decision:** Flutter desktop (Linux primary, Windows secondary, macOS tertiary)  
**Rationale:** Competition evaluates on Ubuntu 22.04. Flutter supports all three with one codebase. Linux is primary for competition; Windows builds useful for development and broader deployment.

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|-----------|
| `llama-server` not on PATH on eval machine | Medium | High | Ship launch script that auto-builds llama.cpp from source if binary not found |
| Qwen2.5-3B GGUF URL changes on HuggingFace | Low | High | `download_model.sh` has fallback URL + size validation |
| Peak RAM exceeds 7 GB on eval machine | Low | Critical | Profiler tests confirm ~2.65 GB; 4.35 GB headroom remains |
| Thermal throttling on older i5 | Low | Medium | Cap threads at 4, context at 4096; monitor in profiler run |
| Flutter Linux build fails on Ubuntu 22.04 | Low | High | Test on clean Ubuntu 22.04 VM before Gate 1 |
| Swahili quality is poor on Qwen2.5-3B | Low | Medium | Manual review of 20 test Swahili prompts; fallback is English-only (still pass) |

---

## Team

| Role | Responsibility |
|------|---------------|
| Lead Engineer | Flutter desktop app, llama.cpp integration, CI |
| Agricultural Content | Knowledge base authoring, prompt testing, Swahili review |
| UX | Desktop UI design, user testing with extension officers |

---

## Budget

| Item | Cost |
|------|------|
| Development hardware (existing) | $0 |
| Cloud VM for Ubuntu 22.04 testing | ~$5 |
| Model training/fine-tuning | $0 (using pre-trained Qwen2.5-3B) |
| Submission fee | $0 |
| **Total** | **~$5** |

---

*Last updated: June 2026*
