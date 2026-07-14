# Maathai Desktop — Engineering Project Plan

> **See also:** [`PROJECT_PLAN.md`](PROJECT_PLAN.md) — the original project plan with phase checklists, technical decision log, team roles, and risk register. This document (`PLAN.md`) focuses on the competitive strategy, scoring analysis, and a phase-by-phase breakdown informed by the competition rules.

**Competition:** Africa Deep Tech Challenge 2026  
**Gate 1 Deadline:** August 25, 2026  
**Today:** June 23, 2026  
**Days available:** 63 days (with 1-week buffer, work ends August 18)

---

## Strategic Objective

Build a fully offline agricultural AI assistant that:
1. Passes all ADTC 2026 hard constraints (< 7 GB RAM, 100% offline, llama.cpp + GGUF only)
2. Maximizes the composite score: `Stotal = 0.50×Sacc + 0.30×Sperf + 0.20×Seff − Pthermal`
3. Claims the +15% African Alpha Bonus via Swahili language support
4. Leverages the existing Maathai mobile app codebase to move faster than any competitor starting from scratch

---

## Competitive Advantages Entering This Project

Before writing a single line of desktop code, Maathai Desktop already has:

| Asset | What it gives us |
|---|---|
| `assets/md/prompt.md` | A production-proven system prompt persona for African agriculture |
| `AgriculturalPromptService.dart` | Battle-tested prompt templates for 4 scenario types |
| `ModelController.dart` | Tuned sampler params (temp=0.7, topK=40, topP=0.95), dynamic token budgeting |
| `InsightService.dart` | Proven tiered fallback: local LLM → rules |
| `sw.json` (1314 keys) | Full Swahili UI translation → African Alpha Bonus on Day 1 |
| `diagnosis_templates/*.json` | Disease template data for 4 conditions |
| `kipkirui/Maathai_llama` plugin | Public GitHub evidence of deep llama.cpp integration expertise |
| `SCANNER_OFFLINE_LOCAL_ML_WRITEUP.md` | Offline ML architecture precedent for REPORT.md |

These assets compress what would be 3–4 weeks of discovery work into a 3-day porting sprint.

---

## Scoring Model — How We Win

```
Stotal = 0.50 × Sacc  +  0.30 × Sperf  +  0.20 × Seff  −  Pthermal
```

### Sacc (Accuracy, 50%) — Our Primary lever

- Use a 3–4B model with strong reasoning capability
- RAG over our curated agricultural knowledge base improves domain accuracy
- Our 2 submitted test prompts are written to showcase our RAG advantage
- System prompt from mobile app is already optimized for concise, accurate agricultural responses
- Swahili queries are handled by our language router

**Target: Top-tier accuracy on all 4 prompts (2 ours + 2 hidden)**

### Sperf (Speed, 30%)

`Sperf = min(TPS / 15, 1.0) × 100`

Scoring is normalized to a 15 TPS reference. Hitting ≥15 TPS means `Sperf = 100`.

- A 3B model on an i5 12th gen achieves 18–28 TPS → `Sperf = 100`
- A 7B model on same hardware achieves 8–12 TPS → `Sperf = 53–80`
- We use a 3B model: easier to hit 100 on Sperf

**Target: ≥15 TPS → Sperf = 100**

### Seff (Efficiency, 20%)

`Seff = (7 − peak_rss_gb) / 7 × 100`

- Our target model (Qwen 2.5 3B Q4_K_M) uses ~2.5 GB peak
- `Seff = (7 − 2.5) / 7 × 100 = 64.3`
- A 7B team using 5.5 GB: `Seff = (7 − 5.5) / 7 × 100 = 21.4`
- We score 3× better on efficiency

**Target: < 3.5 GB peak RSS → Seff > 50**

### Pthermal (Penalty, −10)

A 3B model at 15–20 TPS sustained inference keeps CPU temperature well below 85°C. The thermal risk rises with 7B models running at maximum utilization.

**Target: Zero thermal penalty**

### African Alpha Bonus (+15%)

Swahili UI and prompt routing is ported from the mobile app. This multiplies our panel score.

**Target: african_alpha_claim = true → +15%**

---

## Current State (as of June 23, 2026)

Significant work is already done. The project has:

| Component | Status | Notes |
|---|---|---|
| `llm_service.dart` | ✅ Complete | llama-server subprocess + SSE streaming |
| `rag_service.dart` | ✅ Complete | Pure Dart TF-IDF, bilingual, < 5ms |
| `prompt_service.dart` | ✅ Complete | ChatML format, Qwen2.5-compatible, token budget |
| `app_config.dart` | ✅ Complete | Model: Qwen2.5-3B Q4_K_M configured |
| `model_controller.dart` | ✅ Complete | Full lifecycle + sampler settings |
| `chat_controller.dart` | ✅ Complete | RAG + streaming integrated |
| Knowledge base (crops) | ✅ Maize, beans, cassava, coffee, tomato | Bilingual entries |
| Knowledge base (pests) | ✅ FAW, MLN, late blight, stalk borer | 4 detailed bilingual entries |
| Knowledge base (livestock) | ✅ Goats, poultry, cattle | PPR, parasites, Newcastle, mastitis |
| Knowledge base (soil/markets/calendars) | ✅ Populated | Single comprehensive doc each |
| Dart tests | ✅ prompt + rag tests | Run: `flutter test` |
| Python tests | ✅ Full pytest suite | Run: `pytest tests/ -v` |
| `metadata.json` | 🔄 Needs team ID | Model info filled in |
| UI screens | ✅ Implemented | Polish items remain (Phase 3) |

**Model choice is already made: Qwen2.5-3B-Instruct Q4_K_M**

---

## Phase Plan

### Phase 0 — Foundation Complete ✅ (June 23)
**Already done: Core services, knowledge base, model configuration**

**Already done.** The phase 0 foundation is complete. The model is already chosen (Qwen2.5-3B-Instruct Q4_K_M). Core services (`llm_service.dart`, `rag_service.dart`, `prompt_service.dart`) are implemented and unit-tested.

**Immediate first action (TODAY):**
```bash
# 1. Install llama.cpp (Ubuntu)
sudo apt-get install -y build-essential cmake git libopenblas-dev
git clone https://github.com/ggml-org/llama.cpp && cd llama.cpp
cmake -B build -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build build --config Release -j$(nproc)
sudo cp build/bin/llama-server /usr/local/bin/
sudo cp build/bin/llama-bench  /usr/local/bin/

# 2. Download model
bash download_model.sh

# 3. Run profiler baseline
pip install "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"
adtc-profiler run --submission . --mode participant --output baseline.json --skip-accuracy
cat baseline.json
```

**Milestone: First baseline profiler run recorded in `baseline.json`**

---

### Phase 1 — Model Verification ✅ (July 1 – July 7)
**Goal: Confirm Qwen2.5-3B hits TPS and RAM targets on Ubuntu target environment**

Since the model is already selected, this phase is about verification, not selection:

- [ ] Run `download_model.sh` on Ubuntu 22.04 VM (simulate evaluation environment)
- [ ] Run `adtc-profiler run --mode participant --skip-accuracy`
- [ ] Verify `tokens_per_second_generation >= 15` and `peak_rss_mb < 7168`
- [ ] Run the 2 test prompts manually through `llama-server` on Ubuntu — check answer quality
- [ ] If TPS < 15 on Ubuntu: evaluate Qwen2.5-1.5B Q4_K_M as fallback (faster, less accurate)

**Milestone: Profiler baseline on Ubuntu VM confirmed with valid `submission.json`**

---

### Phase 2 — Knowledge Base Completion (July 7 – July 21, 14 days)
**Goal: Offline RAG corpus curated, indexed, retrieval verified**

The knowledge base format is already established (JSON with `content` + `content_sw`). Existing content:
- ✅ Crops: Maize overview, Maize nutrient deficiency, Tomato
- ✅ Pests: Fall Armyworm, MLN, Late Blight, Maize Stalk Borer

Remaining content to add (all in `assets/knowledge_base/`):

| File | Status | Content source |
|---|---|---|
| `crops/beans_cassava.json` (expand) | 🔄 Stub exists | Add cassava mosaic, bean rust, bean root rot |
| `crops/coffee.json` | ❌ To add | Coffee Berry Disease, Coffee Leaf Rust, KALRO recommendations |
| `crops/livestock.json` | ❌ To add | Cattle mastitis, goat PPR, poultry Newcastle, dairy cow milk drop |
| `soil/soil_management.json` (expand) | 🔄 Stub exists | Soil pH, organic matter, erosion control, lime application |
| `markets/market_prices.json` (expand) | 🔄 Stub exists | Nairobi, Kampala, Dar es Salaam reference prices for major crops |
| `calendars/planting_calendars.json` (expand) | 🔄 Stub exists | East Africa long/short rains, West Africa, Southern Africa seasons |

All additions must include `content_sw` (Swahili translation) for the African Alpha Bonus.

Also port from mobile app:
- `Tomato___Late_blight.json` diagnosis template → add to `pests/pests_diseases.json`
- `Corn_(maize)___Common_rust_.json` → add to `pests/pests_diseases.json`

**Milestone: Knowledge base covers all 4 hidden prompt topic areas, RAG retrieval quality test passes**

---

### Phase 3 — Desktop Application UI (July 21 – August 4, 14 days)
**Goal: Working, visually clean PyQt6 desktop application**

The Flutter skeleton exists with stub implementations for all screens. The services are already working. This phase completes the UI.

#### Week 1 (July 21–28): Core screens

The following Dart stub files need implementation:
- `lib/screens/home_screen.dart` — dashboard with quick actions and offline model status
- `lib/screens/chat_screen.dart` — main agriculture Q&A with streaming token display
  - Reuse `chat_bubble.dart`, `typing_indicator.dart` widgets (already exist as stubs)
  - Language toggle (EN / SW) — uses `TranslationController`
  - Connects to `LlmService.generateStream()` and `RagService.retrieve()`
- `lib/screens/models_screen.dart` — model download/status (points to `download_model.sh`)

Reuse from mobile app (direct Dart ports):
- `chat_controller.dart` (exists as stub) — port from mobile `ChatController`
- `translation_controller.dart` (exists as stub) — port from mobile `TranslationController`
- `theme_controller.dart` (exists as stub) — port from mobile app

#### Week 2 (July 28 – August 4): Supporting screens + polish

- `lib/screens/knowledge_screen.dart` — browse knowledge base by category
- Benchmark overlay — live RAM, TPS, CPU temp (shown in settings or debug panel)
- Offline indicator in status bar (always visible)
- Swahili UI strings from `assets/i18n/sw.json` (ported from mobile app)
- App icon using Maathai branding

**Milestone: Full walkthrough of the application on dev machine recorded**

---

### Phase 4 — Fine-Tuning (Optional, July 14 – August 4, parallel)
**Goal: Boost Sacc — highest-weight scoring component (50%)**

Fine-tuning is parallel to Phase 3. If bandwidth allows, it can significantly improve accuracy on the 4 evaluation prompts.

#### Dataset creation

Minimum 200 instruction-response pairs in agriculture domain:
- Crop diagnosis (symptoms → cause → treatment)
- Livestock health (symptom → disease → action)
- Planting calendar queries (location → crop → timing)
- Market questions (crop → price reference → storage advice)
- Swahili pairs (same content in Kiswahili)

Sources: KALRO extension guides, FAO training materials, CABI data sheets, mobile app `insight_service.dart` data patterns

#### Fine-tuning process

```bash
# QLoRA fine-tuning on Colab T4 or local GPU
# Using Unsloth or TRL
python fine_tune.py \
  --base_model Qwen/Qwen2.5-3B-Instruct \
  --dataset data/agriculture_qa.jsonl \
  --output_dir checkpoints/maathai-agri-lora \
  --lora_r 16 --epochs 3 --batch_size 4
```

#### Post-training

1. Merge LoRA weights into base model
2. Quantize to GGUF Q4_K_M using `llama.cpp/convert_hf_to_gguf.py` + `llama-quantize`
3. Verify merged model still passes RAM constraint
4. Re-run profiler — confirm TPS does not degrade > 10%

**Milestone (if achieved): Fine-tuned `.gguf` with measurably better accuracy on agriculture prompts**

---

### Phase 5 — Submission Package (August 4 – August 18, 14 days)
**Goal: Complete, valid, polished submission — 1 week before deadline**

| Day | Task |
|---|---|
| Aug 4–6 | Upload final `.gguf` to HuggingFace (public repo) |
| Aug 6–7 | Write `download_model.sh` — test idempotency, test from fresh clone |
| Aug 7–10 | Write `REPORT.md` — problem, design decisions, constraints, benchmarks |
| Aug 10–11 | Final `metadata.json` — no placeholder values, 2 test prompts, african_alpha_claim true |
| Aug 11–13 | Record 2-minute demo video — show model running, Swahili query, benchmark panel |
| Aug 13–15 | Full submission checklist run: `bash download_model.sh` → `adtc-profiler run` → review JSON |
| Aug 15–18 | Buffer — fix any issues from checklist run |
| **Aug 25** | **Submit on DevPost (hard deadline)** |

---

## Submission Checklist

Before submitting on DevPost, every item must be checked:

### Repository
- [ ] Repository is **public** on GitHub
- [ ] `*.gguf` and `model/` are in `.gitignore` — no large files committed
- [ ] `data/chroma_db/` is in `.gitignore` — built at first run, not committed
- [ ] `.venv/`, `__pycache__/`, `*.pyc` excluded

### `metadata.json`
- [ ] `team_id` — matches ADTF portal registration
- [ ] `domain: "agriculture"` — correct
- [ ] `language_scope: ["en", "sw"]` — English + Swahili
- [ ] `african_alpha_claim: true` — Swahili support is live
- [ ] `budget_laptop_claim: true` — required for all
- [ ] `submitter` fields — real name, email, GitHub handle
- [ ] `cross_disciplinary_pairing.load_bearing: true` — RAG is load-bearing
- [ ] `test_prompts` — exactly 2 prompts, agriculture domain, no placeholders
- [ ] `model.runtime: "llama.cpp"` — required
- [ ] `model.quantization` — matches the GGUF file (e.g. `"GGUF Q4_K_M"`)
- [ ] `_runtime.model_path` — exact relative path to the `.gguf` file

### `download_model.sh`
- [ ] Runs without credentials (public URL)
- [ ] Downloads to `model/` directory
- [ ] Idempotent (safe to run twice)
- [ ] Downloaded file path matches `_runtime.model_path`

### `REPORT.md`
- [ ] Problem section — African context, target user
- [ ] Design decisions section — model choice, quantization rationale, RAG architecture
- [ ] Constraints section — hardware target, offline requirement
- [ ] Benchmarks table — self-reported TPS, RAM, latency

### `adtc-profiler` pass
- [ ] `bash download_model.sh` completes without error
- [ ] `adtc-profiler run --mode participant --output submission.json --skip-accuracy` exits 0
- [ ] `submission.json` shows `"measured_on": "participant_laptop"`
- [ ] `peak_rss_mb` < 7168 (hard limit)
- [ ] `tokens_per_second_generation` > 15 (target)

### Video
- [ ] 2 minutes or under
- [ ] Shows model running (chat response in real-time)
- [ ] Shows Swahili query and response
- [ ] Shows benchmark panel (RAM usage visible)
- [ ] Shows offline mode (network disabled or disconnected)

---

## Risk Register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Model exceeds 7 GB RAM → disqualification | Low (with 3B model) | Critical | Test RAM with profiler in Week 1; never use 7B model |
| TPS below 15 on target hardware | Low–Medium | High | Use 3B model; test on Ubuntu; optimize n_threads=4 |
| Thermal throttling on 90-minute generation load | Low | Medium | 3B model runs cooler; benchmark panel warns if temp > 75°C |
| Fine-tuned model degrades TPS | Medium | Medium | Benchmark before and after; fine-tuning is optional |
| HuggingFace download fails during evaluation | Low | Critical | Test `download_model.sh` from fresh clone on Ubuntu |
| ChromaDB index build fails on Ubuntu | Low | High | Test full pipeline on Ubuntu VM before submission |
| Swahili responses hallucinate (bad quality) | Medium | Medium | Use `use_english_prompting=True` as fallback; test 10 Swahili queries |

---

## Definition of Done

The project is complete when:
1. `adtc-profiler run --mode participant` produces a valid `submission.json` with `peak_rss_mb < 7168` and `tokens_per_second_generation >= 15`
2. All items in the submission checklist above are checked
3. The 2-minute demo video is recorded and uploaded
4. The DevPost submission is live with the correct Git commit hash URL
