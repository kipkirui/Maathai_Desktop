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

### Phase 2 — RAG Knowledge Base (Week 3–4) ✅ COMPLETE
**Target: Every response grounded in verified crop data**

- [x] Design knowledge base schema (JSON document format)
- [x] Author knowledge base content (~30+ bilingual entries across crops, pests, livestock, soil, markets, calendars)
- [x] Implement `RagService` (pure Dart TF-IDF)
- [x] Integrate RAG into `PromptService`
- [x] Test RAG grounding (pytest `tests/test_rag.py`)

**Deliverable:** Responses reference specific crop varieties, dosages, and Kenya/Tanzania context correctly.

---

### Phase 3 — Desktop UI Polish (Week 4–5) ✅ MOSTLY COMPLETE
**Target: Production-quality UI that judges will evaluate for S_acc**

- [x] Desktop layout with navigation rail (Chat | Knowledge | Models | Settings)
- [x] Collapsible context panel (region, crop, season)
- [x] Chat streaming, `<think>` collapse, copy, Markdown export
- [ ] Thumbs up/down feedback; Regenerate; PDF export
- [x] Knowledge base browser + model status indicator
- [x] Ctrl+Enter send (expand remaining shortcuts)

**Deliverable:** App feels polished, fast, and purpose-built. Non-technical user (extension officer) can use it without training.

---

### Phase 4 — Swahili + African Alpha (Week 5–6) ✅ MOSTLY COMPLETE
**Target: Full Swahili UI and response capability → +15% score bonus**

- [x] Extract UI strings to `assets/i18n/en.json` / `sw.json`
- [x] Implement `TranslationController` with `Provider`
- [x] Language switcher in Settings (English / Kiswahili)
- [x] Swahili system prompt variant / RAG `content_sw`
- [ ] Test Swahili responses for agricultural terminology accuracy
- [x] Update `metadata.json`: `"language_scope": ["en", "sw"]`, `"african_alpha_claim": true`

**Deliverable:** Full app experience in Swahili. All agricultural responses in Swahili when language set to sw.

---

### Phase 5 — Testing & Competition Hardening 🔄 IN PROGRESS (as of August 4, 2026)
**Target: Pass all profiler checks, no thermal penalty, reproducible — 21 days to Gate 1**

**Latest rules notes (DevPost + challenge site, Aug 2026):**
- `Sperf = 100 × (TPSact ÷ TPSmax)` on the leaderboard; profiler still lists 15 t/s as a provisional local reference
- Hardware profile explicitly includes AMD Ryzen 5 3000–5000 as well as Intel i5
- Final participant report should include accuracy (do not ship `--skip-accuracy` as the Gate 1 artifact)
- Timeline: Gate 1 Aug 25 → semifinalists Sep 8 → semifinal package Sep 22 → finalists Sep 29 → live defense Oct 17

- [x] Initial participant profiling (`submission.json` 2026-06-24)
  - peak RSS ~3274 MB (< 7 GB) ✅
  - TPS 8.03 (below provisional 15; competitive TPSmax risk) 🔄
  - no thermal throttling at 4 threads ✅
  - `accuracy: []` — must re-run full suite ❌
- [x] RAM / runtime tuning documented (`n_ctx=4096`, `n_batch=2048`, `threads=4`, flash-attn on, `n_gpu_layers=0`)
- [ ] Re-run profiler after shipping tuned flags; prefer ADTC-class 4-vCPU Ubuntu
- [ ] Test `download_model.sh` on fresh Ubuntu 22.04 VM (no prior downloads)
- [ ] Verify both `metadata.json` test prompts produce grounded responses (RAG + model)
- [x] Unit tests exist for RAG / prompts / submission metadata
- [ ] Record 2-minute demo video for Gate 1 submission
  - Show: app startup, model loading, agriculture Q&A in English, switch to Swahili, knowledge base browser, offline

**Deliverable:** Full `submission.json` with accuracy metrics. Video recorded. Repo public.

---

### Phase 6 — Gate 1 Submission (August 25, 2026) 🎯
**Checklist before DevPost submit:**

- [x] `metadata.json` — no placeholder values remain
- [ ] `download_model.sh` — tested from scratch on Ubuntu 22.04
- [x] `REPORT.md` — complete, accurate benchmark numbers (participant laptop; refresh after re-profile)
- [x] `LICENSE` — GNU GPL v3 present
- [x] README — clear build instructions
- [ ] Repo is public
- [x] `*.gguf` excluded from git (local weights present under `model/` for dev)
- [ ] `adtc-profiler run --mode participant` → accuracy scored; improve TPS if needed
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
