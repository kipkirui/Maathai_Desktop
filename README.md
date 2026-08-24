# Maathai Desktop

> *"It's the little things citizens do. That's what will make the difference. My little thing is planting trees."*  
> — Wangari Maathai, Nobel Peace Prize laureate

**Offline AI agriculture advisor for the laptop Africa already has.**  
ADTC 2026 submission — Africa Deep Tech Challenge, Agriculture track.

[![ADTC 2026](https://img.shields.io/badge/ADTC-2026-green)](https://africadeeptech.org/challenge-2026/)
[![Domain](https://img.shields.io/badge/domain-agriculture-brightgreen)](https://africadeeptech.org/challenge-2026/)
[![Runtime](https://img.shields.io/badge/runtime-llama.cpp-orange)](https://github.com/ggml-org/llama.cpp)
[![Language](https://img.shields.io/badge/language-English%20%2B%20Swahili-blue)](https://en.wikipedia.org/wiki/Swahili_language)
[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

---

## What It Is

Maathai Desktop is a **100% offline** on-device AI agricultural assistant that runs on an 8 GB RAM laptop with no internet, no subscription, and no GPU — targeting the hardware millions of African farmers, extension officers, and agri-students already own.

It delivers:
- **Crop advisory** — planting calendars, fertilizer, soil prep, irrigation
- **Pest & disease diagnosis** — symptom-based identification and treatment
- **Livestock health** — disease recognition, vaccination, feeding guidance
- **Market reference** — offline price snapshots, crop grading, storage
- **Swahili support** — full English ↔ Kiswahili switching for East Africa

All inference runs locally via `llama.cpp`. Zero API fees. Zero internet after install.

---

## Prior Work — Maathai Mobile App

This project extends **Maathai** ([usemaathai.com](https://usemaathai.com)) — a production Android agriculture AI app already serving farmers in Kenya. The desktop version ports the battle-tested agriculture prompts, Swahili UI, and offline inference architecture from the mobile app to the laptop.

The mobile app's llama.cpp integration is open-source at [`kipkirui/Maathai_llama`](https://github.com/kipkirui/Maathai_llama), demonstrating deep prior expertise in on-device LLM inference.

---

## ADTC 2026 Submission Details

| Field | Value |
|---|---|
| Competition | [Africa Deep Tech Challenge 2026](https://africadeeptech.org/challenge-2026/) |
| Track | Agriculture |
| Runtime | `llama.cpp` (GGUF weights only) |
| Target hardware | 8 GB RAM, Intel i5 10th–12th gen **or** AMD Ryzen 5, integrated GPU, Ubuntu 22.04 |
| Languages | English (`en`) + Swahili (`sw`) |
| African Alpha claim | Yes (Swahili; +15% panel / DevPost African Use Case bonus) |
| Budget laptop claim | Yes |
| Gate 1 deadline | **August 25, 2026** (DevPost: Aug 24 @ 11:45pm PDT) |
| Status (Aug 4) | Core app + RAG done; Gate 1 packaging / full profiler / video remaining |

---

## Quick Start

### Prerequisites

```bash
# Ubuntu 22.04 — build llama.cpp
sudo apt-get update
sudo apt-get install -y build-essential cmake git libopenblas-dev
git clone https://github.com/ggml-org/llama.cpp
cd llama.cpp
cmake -B build -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build build --config Release -j$(nproc)
sudo cp build/bin/llama-server /usr/local/bin/
sudo cp build/bin/llama-bench  /usr/local/bin/
cd ..

# Flutter (for the desktop UI — Linux desktop target)
sudo snap install flutter --classic
# Verify
flutter doctor
```

### Download the model

```bash
# Downloads ~2 GB GGUF model weights to model/
bash download_model.sh
```

The agricultural knowledge base is bundled in `assets/knowledge_base/` as bilingual JSON. The Flutter app builds a TF-IDF index in memory at startup — no separate index build step is required.

### Run the desktop application

```bash
flutter pub get
flutter run -d linux
```

### Gate 1 verify + ADTC profiler

Full close-out checklist and video shot list: [`GATE1.md`](GATE1.md).

```bash
# Ubuntu 22.04 / WSL — preferred (download + metadata + profiler + gates)
bash scripts/gate1_verify.sh           # FULL — accuracy ON (final artifact)
bash scripts/gate1_verify.sh --mem-8g  # same, cgroup-capped at 8 GiB (ADTC laptop)
bash scripts/gate1_verify.sh --smoke   # fast iterate

# Or call the profiler wrapper directly
bash scripts/run_adtc_profiler.sh --full
```

Manual install (if needed):

```bash
python3.11 -m pip install "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"
adtc-profiler run --submission . --mode participant --output submission.json
```

Provisional local score peek (15 t/s reference; official Sperf uses field TPSmax):

```bash
python -c "
import json
with open('submission.json') as f: s = json.load(f)
print('Peak RAM:', s['memory']['peak_rss_mb'], 'MB')
print('TPS:', round(s['throughput']['tokens_per_second_generation'], 1))
print('Seff:', round((7168 - s['memory']['peak_rss_mb']) / 7168 * 100, 1))
print('Sperf (prov 15):', round(min(s['throughput']['tokens_per_second_generation'] / 15, 1) * 100, 1))
print('Accuracy entries:', len(s.get('accuracy') or []))
"
```

---

## Architecture

### Technology Stack

| Layer | Technology | Why |
|---|---|---|
| **UI** | Flutter (Dart) — Linux desktop | Reuses mobile app codebase; production-quality UI |
| **LLM inference** | `llama-server` subprocess → localhost HTTP | 100% offline; only ADTC-compliant runtime |
| **RAG retrieval** | Pure Dart TF-IDF (`lib/services/rag_service.dart`) | No second model; sub-5ms; zero extra RAM |
| **Knowledge corpus** | Bilingual JSON in `assets/knowledge_base/` | Bundled offline; English + Swahili (`content_sw`) |
| **Model format** | GGUF Q4_K_M | Required by ADTC; best RAM/quality tradeoff |

### System Diagram

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
│                             │ localhost:8080                   │
│  ┌──────────────────────────▼────────────────────────────────┐ │
│  │         llama-server subprocess (offline)                  │ │
│  │         model/qwen2.5-3b-instruct-q4_k_m.gguf             │ │
│  └───────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

The `src/` Python layer provides pytest helpers and optional profiler utilities. It is not required at app runtime.

### Reuse from Mobile App (Maathai Android)

| Mobile component | Desktop equivalent | Reuse type |
|---|---|---|
| `assets/md/prompt.md` | `src/rag/knowledge_base/system_prompt.md` | Verbatim copy |
| `AgriculturalPromptService.dart` | `lib/services/prompt_service.dart` | Direct Dart port |
| `ModelController.dart` | `lib/state/model_controller.dart` | Direct Dart port |
| `InsightService.dart` (tiered fallback) | `lib/services/insight_service.dart` | Direct Dart port |
| `assets/i18n/sw.json` (1314 Swahili keys) | `assets/i18n/sw.json` | Verbatim copy |
| `assets/diagnosis_templates/` | `assets/knowledge_base/pests_diseases/` | Verbatim copy |

---

## Project Structure

```
Maathai_Desktop/
├── metadata.json              ← ADTC 2026 submission metadata + 2 test prompts
├── download_model.sh          ← Downloads GGUF model to model/
├── REPORT.md                  ← Technical writeup for competition judges
├── PLAN.md                    ← Engineering project plan and timeline
├── TESTING.md                 ← Test strategy and test cases
├── ARCHITECTURE.md            ← System design document
├── CONTRIBUTING.md            ← Dev setup and workflow guide
├── requirements.txt           ← Python deps (RAG layer + profiler)
├── .gitignore                 ← Excludes *.gguf, model/, chroma_db/
│
├── model/
│   └── .gitkeep               ← Model downloaded here (NEVER committed)
│
├── src/                       ← Python utilities (RAG, profiler helpers)
│   ├── app.py                 ← CLI entry point
│   ├── config.py              ← Paths and configuration
│   ├── llm/                   ← LLM wrappers (Python, for testing/profiler)
│   │   ├── inference.py
│   │   └── prompt_engine.py   ← Python port of AgriculturalPromptService.dart
│   └── rag/
│       ├── tfidf_retriever.py ← TF-IDF retriever (pytest; mirrors Dart RagService)
│       └── knowledge_base/    ← Agricultural text corpus
│           ├── system_prompt.md
│           ├── crops/
│           ├── livestock/
│           ├── pests_diseases/
│           ├── market_data/
│           └── climate/
│
├── lib/                       ← Flutter application (primary UI)
│   ├── main.dart
│   ├── services/
│   │   ├── llm_service.dart   ← llama-server subprocess + HTTP
│   │   ├── prompt_service.dart← Ported from AgriculturalPromptService.dart
│   │   └── rag_service.dart   ← Pure Dart TF-IDF over bundled JSON
│   └── state/
│       └── model_controller.dart ← Ported from mobile app
│
├── assets/
│   ├── knowledge_base/        ← Agricultural corpus (also used by Flutter)
│   └── i18n/
│       ├── en.json            ← Desktop UI strings (EN)
│       └── sw.json            ← Desktop UI strings (Kiswahili)
│
└── tests/                     ← pytest test suite
    ├── conftest.py
    ├── test_inference.py
    ├── test_rag.py
    ├── test_offline.py
    ├── test_prompts.py
    ├── test_performance.py
    ├── test_prompt_engine.py
    └── test_submission.py
```

---

## Scoring Strategy

```
Stotal = 0.50 × Sacc  +  0.30 × Sperf  +  0.20 × Seff  −  Pthermal
```

| Component | Our target | How we achieve it |
|---|---|---|
| Sacc (50%) | High | Battle-tested prompts + RAG over African agricultural data |
| Sperf (30%) | Competitive vs field max | Official: `100×(TPSact/TPSmax)`; local provisional ref still 15 t/s |
| Seff (20%) | ~54+ (measured ~3.3 GB peak) | 3B Q4_K_M stays well under 7 GB |
| Pthermal | 0 (no penalty) | 3B model; no throttle in participant run |
| Alpha Bonus | Claimed | Full Swahili UI + bilingual RAG |

**This laptop (2026-08-21 profiler / 2026-08-24 packaging):** 3.59 t/s · peak RSS 3177 MB · throttled 100 °C · accuracy job restarted  
**WSL smoke (2026-08-04):** 5.64 t/s · peak RSS 3274 MB · thermal OK · `accuracy: []`  
**Accuracy probe (2026-08-05):** ARC-Easy limit=2 → score 1.0; native limit=50 restarted 2026-08-24 after a dead 38/200 run.

---

## Deadlines

| Gate | Date | Status |
|---|---|---|
| Gate 1 | **August 25, 2026** | Due **today** (DevPost Aug 24, 23:45 PDT); packaging checks pass, accuracy JSON filling |
| Semifinalists | September 8, 2026 | Up to 20 teams; Gate 2 audit begins |
| Semifinalist package | September 22, 2026 | Gate 2 submission |
| Finalists | September 29, 2026 | Up to 10 teams |
| Gate 3 / Live defense | October 17, 2026 | Pitch + awards |

---

## Competition Checklist

See [`GATE1.md`](GATE1.md) for the full close-out + video shot list. Run `bash scripts/gate1_verify.sh --checklist`.

- [x] Repository is public on GitHub
- [x] `metadata.json` — no placeholder values
- [x] `download_model.sh` — present, HuggingFace URL, no placeholders (fresh-clone still worth a once-over)
- [x] Model is GGUF format, hosted publicly on HuggingFace
- [x] `model/*.gguf` excluded from git (`model/.gitkeep` tracked)
- [x] `REPORT.md` — complete technical writeup (participant benchmarks filled)
- [x] `LICENSE` — GNU GPL v3
- [x] Submission pytest gate (`tests/test_submission.py`) — 30 passed, 1 skipped
- [ ] `submission.json` accuracy non-empty — native ARC-Easy n=50 running (2026-08-24)
- [x] Peak RAM < 7168 MB (hard limit) — native ~3177 MB / WSL ~3274 MB
- [ ] Zero network calls during inference (verify offline)
- [ ] 2-minute demo video recorded (shot list in GATE1.md)
- [ ] Submitted on DevPost before August 25

---

## Related Projects

- [`kipkirui/Maathai_llama`](https://github.com/kipkirui/Maathai_llama) — Open-source Flutter plugin wrapping llama.cpp (Android)
- [Maathai App](https://usemaathai.com) — Production mobile agriculture AI app

---

## License

GNU GPL v3 — see [LICENSE](LICENSE)

*Built in Nairobi, Kenya. For African farmers, by people who know the soil.*
