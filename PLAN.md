# Maathai Desktop — Engineering Project Plan

> **See also:** [`PROJECT_PLAN.md`](PROJECT_PLAN.md) — the original project plan with phase checklists, technical decision log, team roles, and risk register. This document (`PLAN.md`) focuses on the competitive strategy, scoring analysis, and a phase-by-phase breakdown informed by the competition rules.

**Competition:** Africa Deep Tech Challenge 2026  
**Gate 1 Deadline:** August 25, 2026 (DevPost: Aug 24, 2026 @ 11:45pm PDT)  
**Today:** August 4, 2026  
**Days remaining:** **21 days** to Gate 1 (buffer target still August 18)

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

**Official DevPost / challenge site (current):**
`Sperf = 100 × (TPSact ÷ TPSmax)` — relative to the fastest qualified submission on audit hardware.

**adtc-profiler / local estimate (still published):**
`Sperf ≈ min(TPS / 15, 1.0) × 100` with `TPS_REFERENCE = 15.0` marked **provisional**.

Implications for us:
- Local reports can still quote the 15 TPS provisional formula for Gate 1 self-checks
- Final leaderboard speed is competitive: a slower host (our measured ~8 t/s) hurts more if peers hit 20+ t/s
- Prefer smaller/faster 3B Q4_K_M; re-benchmark on ADTC-class 4-vCPU Ubuntu before submit

**Target: maximize absolute TPS on audit hardware; aim ≥15 t/s so provisional local Sperf ≈ 100**

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

### African language / use-case bonus

- Challenge site: African language functionality → **+15% on panel score**; Budget Profile multiplier **+10%**
- DevPost rules text: African Use Case Bonus → **up to 10 extra points**
- Template field: `african_alpha_claim: true` (we claim via Swahili UI + bilingual RAG)

**Target: keep `african_alpha_claim = true` and demonstrate live Swahili Q&A in the demo video**

---

## Current State (as of August 4, 2026)

**Phase: Gate 1 submission hardening (Phase 5).** Core product is built; remaining work is audit-ready packaging.

| Component | Status | Notes |
|---|---|---|
| Core Flutter + llama-server stack | ✅ Complete | Streaming chat, model lifecycle, ChatML prompts |
| RAG (pure Dart TF-IDF) | ✅ Complete | Bilingual KB across crops/pests/livestock/soil/markets/calendars |
| Desktop UI | ✅ Mostly complete | Chat / Knowledge / Models / Settings; minor polish left |
| Swahili UI + RAG `content_sw` | ✅ Complete | Needs terminology QA pass before video |
| `metadata.json` | ✅ Complete | Team `1060310`, 2 prompts, alpha + budget claims |
| `REPORT.md` | ✅ Draft complete | Participant benchmarks filled; accuracy suite empty |
| Participant profiler run | 🔄 Partial | `submission.json` (2026-06-24): peak RSS ~3274 MB, **8.03 t/s**, `accuracy: []` |
| Tuned llama-server flags | ✅ Documented | flash-attn / batch 2048 / threads=4; re-profile after ship |
| Ubuntu 22.04 fresh-clone download | ❌ Open | Must verify `download_model.sh` on clean target OS |
| Full profiler w/ accuracy | ❌ Open | Do **not** submit `--skip-accuracy` as final report |
| Public GitHub repo | ✅ Done | `kipkirui/Maathai_Desktop` is public |
| 2-minute demo video | ❌ Open | Model live + Swahili + offline |
| DevPost submit | ❌ Open | Hard deadline Aug 25 |

**Measured local scores (provisional 15 TPS formula, participant laptop):**
`Seff ≈ 54.3` · `Sperf ≈ 53.5` · thermal OK · RAM safe under 7 GB

**Model choice locked: Qwen2.5-3B-Instruct Q4_K_M**

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

### Phase 1 — Model Verification ✅ (mostly done)
Participant laptop profiler run exists (`submission.json`, 2026-06-24). Still open: Ubuntu 22.04 / ADTC-class re-run and TPS uplift check after flash-attn / batch tuning.

### Phase 2 — Knowledge Base ✅ Complete
Bilingual corpus shipped under `assets/knowledge_base/` (crops, pests, livestock, soil, markets, calendars).

### Phase 3 — Desktop Application UI ✅ Mostly complete
Flutter desktop nav + streaming chat + knowledge browser + models/settings. Optional polish: feedback buttons, regenerate, PDF export.

### Phase 4 — Fine-Tuning ⏭️ Deferred
Not blocking Gate 1. RAG + prompt quality is the accuracy lever for now; revisit only if accuracy suite is weak.

### Phase 5 — Submission Package 🔄 IN PROGRESS (August 4 – August 18)
**Goal: Audit-ready Gate 1 package — finish ≥1 week before deadline**

**Runbook:** [`GATE1.md`](GATE1.md) · `bash scripts/gate1_verify.sh` (full) / `--smoke` (iterate)

| Day | Task | Status |
|---|---|---|
| Aug 4–6 | Confirm HF GGUF URL + `download_model.sh` idempotency | 🔄 Model local; fresh Ubuntu via `gate1_verify.sh` |
| Aug 6–8 | Re-run `adtc-profiler` **with accuracy** (`gate1_verify.sh` or `run_adtc_profiler.sh --full`) | ❌ |
| Aug 8–10 | Update `REPORT.md` with final numbers + rule-aligned Sperf note | 🔄 Draft exists |
| Aug 10–12 | Swahili terminology QA + record ≤2 min demo video ([shot list](GATE1.md)) | ❌ |
| Aug 12–15 | Public repo + full checklist (`download` → profiler → review) | ❌ |
| Aug 15–18 | Buffer / fix flag verdicts | ❌ |
| **Aug 25** | **Submit on DevPost (hard deadline)** | ❌ |

**Official Gate timeline (DevPost rules, Aug 2026):**
| Date | Stage |
|---|---|
| Aug 25 | Gate 1 deadline — prototype + REPORT + video |
| Sep 8 | Up to 20 semifinalists announced; Gate 2 audit begins |
| Sep 22 | Semifinalist submission deadline |
| Sep 29 | Up to 10 finalists announced |
| Oct 17 | Live defense & awards |

---

## Submission Checklist

Before submitting on DevPost, every item must be checked:

### Repository
- [ ] Repository is **public** on GitHub
- [ ] `*.gguf` and `model/` are in `.gitignore` — no large files committed
- [ ] `data/chroma_db/` is in `.gitignore` — built at first run, not committed
- [ ] `.venv/`, `__pycache__/`, `*.pyc` excluded

### `metadata.json`
- [x] `team_id` — `1060310`
- [x] `domain: "agriculture"` — correct
- [x] `language_scope: ["en", "sw"]` — English + Swahili
- [x] `african_alpha_claim: true` — Swahili support is live
- [x] `budget_laptop_claim: true` — required for all
- [x] `submitter` fields — real name, email, GitHub handle
- [x] `cross_disciplinary_pairing.load_bearing: true` — RAG is load-bearing
- [x] `test_prompts` — exactly 2 prompts, agriculture domain, no placeholders
- [x] `model.runtime: "llama.cpp"` — required
- [x] `model.quantization` — `"GGUF Q4_K_M"`
- [x] `_runtime.model_path` — `model/qwen2.5-3b-instruct-q4_k_m.gguf`

### `download_model.sh`
- [x] Runs without credentials (public URL)
- [x] Downloads to `model/` directory
- [ ] Idempotent verified on clean Ubuntu 22.04
- [x] Downloaded file path matches `_runtime.model_path`

### `REPORT.md`
- [x] Problem section — African context, target user
- [x] Design decisions section — model choice, quantization rationale, RAG architecture
- [x] Constraints section — hardware target, offline requirement
- [x] Benchmarks table — participant TPS, RAM, latency (re-run before submit)

### `adtc-profiler` pass
- [ ] `bash download_model.sh` completes without error on fresh Ubuntu
- [ ] Final `adtc-profiler run --mode participant --output submission.json` **without** `--skip-accuracy`
- [x] Existing `submission.json` shows `"measured_on": "participant_laptop"` (stale; re-run)
- [x] `peak_rss_mb` < 7168 (hard limit) — ~3274 MB measured
- [ ] `tokens_per_second_generation` competitive vs field (provisional local target ≥15)

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
| TPS weak vs field TPSmax (relative Sperf) | Medium | High | Stay on 3B Q4_K_M; flash-attn/batch tune; re-bench on ADTC 4-vCPU Ubuntu |
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
