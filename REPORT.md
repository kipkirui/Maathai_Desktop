# Technical Report — Maathai Desktop

**Team ID:** 1060310  
**Domain:** agriculture  
**Model:** Qwen2.5-3B-Instruct-Q4_K_M  
**Quantization:** GGUF Q4_K_M

---

## Problem

### Who is the target user?

Maathai Desktop is built for **smallholder farmers and agricultural extension officers** across Sub-Saharan Africa, with a primary focus on East Africa (Kenya, Uganda, Tanzania). The typical user:

- Manages 0.5–5 acres of mixed crops (maize, beans, cassava, vegetables) or small livestock (goats, cattle, poultry)
- Has access to a secondhand laptop (bought for KES 15,000–30,000) but unreliable internet
- May speak Kiswahili as a first or second language
- Cannot afford API-fee AI services (GPT-4 API costs more per month than their weekly income)

### What problem does it solve?

African smallholder farmers face three compounding information failures:

1. **Access:** The nearest agricultural extension officer covers 500–1000 farmers. Questions go unanswered for weeks.
2. **Cost:** Cloud AI requires API fees + reliable internet + electricity — all scarce.
3. **Relevance:** Generic AI advice ("apply NPK 20-20-20") ignores local variety names, seasonal calendars, market realities, and language.

Maathai Desktop addresses all three by running a tuned agricultural AI advisor entirely on the device the user already owns, with zero ongoing cost after setup.

### Why local/offline inference?

- **No API fees** — inference is free after model download
- **Works during load-shedding and data rationing** — inference requires no active connection
- **Privacy** — farm data (crop records, scan results) never leave the device
- **Latency** — no round-trip to a cloud server once the model is loaded

### Prior work — Maathai mobile app

This submission builds on **Maathai** (`usemaathai.com`), a production Android app already used by farmers in Kenya, which integrates the same llama.cpp inference engine through our open-source plugin [`kipkirui/Maathai_llama`](https://github.com/kipkirui/Maathai_llama). Maathai Desktop ports the battle-tested agriculture prompts, Swahili UI, and offline inference architecture to the laptop platform required by ADTC 2026.

---

## Design Decisions

### Base model selection

We selected **Qwen2.5-3B-Instruct** (3 billion parameters, GGUF Q4_K_M quantization, ~1.86 GB).

Candidates evaluated:

| Model | Params | GGUF Q4_K_M | Est. RAM | Est. TPS (i5 12th gen) | Verdict |
|---|---|---|---|---|---|
| **Qwen2.5-3B-Instruct** | 3B | ~1.86 GB | ~2.5–3.3 GB | 8–28 t/s (machine-dependent) | ✅ Selected |
| Phi-3.5 Mini Instruct | 3.8B | ~2.4 GB | ~3.1 GB | 18–24 t/s | Good, larger |
| Llama 3.2 3B Instruct | 3B | ~2.0 GB | ~2.6 GB | 20–26 t/s | Similar, less instruction-tuned |

Decision rationale:
- Qwen2.5-3B-Instruct delivers consistently strong instruction-following quality at 3B scale
- ChatML format (`<|im_start|>` / `<|im_end|>`) is natively supported — our prompt builder targets this format
- Peak RAM stays well under the 7 GB hard ceiling (~3.3 GB measured) → strong `Seff`
- Qwen2.5 training data has meaningful Swahili representation, improving Swahili response quality
- Throughput depends on host CPU; on our participant laptop (i7-1185G7, Ubuntu 22.04) we measure ~8 t/s generation. On ADTC-class i5 hardware with OpenBLAS-tuned `llama.cpp`, we expect higher TPS; the 3B Q4_K_M choice remains the best accuracy/RAM/speed tradeoff versus 7B alternatives

We deliberately avoided 7B models. A 7B model at Q4_K_M uses ~5.5 GB RAM, giving `Seff ≈ 21` vs our measured `Seff ≈ 54` — a large efficiency gap. A slower 7B also risks thermal penalties on 4-vCPU integrated-GPU laptops. The RAG layer closes much of the domain accuracy gap without the RAM cost of a larger base model.

### Quantization format

GGUF Q4_K_M was selected for the following reasons, consistent with our mobile app's model selection philosophy:
- Q4_K_M balances quantization quality against memory footprint better than Q2_K (too aggressive) or Q8_0 (too large)
- Q8_0 would require 2× more RAM and half the speed — direct Seff and Sperf penalties
- Q2_K shows measurable quality degradation on multi-step agricultural reasoning
- Q4_K_M is the standard quantization level used in our production Maathai mobile app

### Inference runtime

`llama.cpp` via `llama-server` (HTTP/SSE on localhost) is the only permitted runtime. Key configuration for the ADTC standard laptop:

```
n_ctx      = 4096     # sufficient for RAG context + prompt
n_threads  = 4        # matches ADTC 4 vCPU profile; avoids thermal pressure from over-threading
n_gpu_layers = 0      # integrated GPU only; CPU inference
temperature = 0.7     # balanced creativity/determinism for advisory tasks
top_k       = 40      # from Maathai mobile app production config
top_p       = 0.95
repeat_penalty = 1.1  # reduces repetitive advice patterns
max_tokens  = 512     # dynamic: context_length − prompt_tokens − 100
```

These parameters are ported from `ModelController.dart` in the Maathai mobile app, where they were tuned over thousands of production inference sessions.

### RAG over offline agricultural knowledge corpus

Maathai Desktop implements Retrieval-Augmented Generation in **pure Dart** (`lib/services/rag_service.dart`) with zero external dependencies. This is the primary cross-disciplinary integration and is load-bearing.

**Without RAG:** The 3B model answers from training data alone — generic, not Africa-specific.  
**With RAG:** Retrieved bilingual passages from our knowledge base are injected into context. Answers become specific to African agricultural conditions.

Implementation:
- **Algorithm:** TF-IDF with cosine similarity, English stemmer, IDF weighting
- **Speed:** < 5ms retrieval over all documents (in-memory, pure Dart)
- **Language:** Bilingual — returns Swahili content when language = "sw"
- **Knowledge base:** Bundled as Flutter assets (JSON), covering crops, pests, soil, markets, calendars, livestock (~30 documents)
- **No external dependencies:** No Python, no server process, no embedding model to download

Key knowledge base entries (all bilingual):
- Maize production guide: varieties by altitude, fertilizer rates, weed management
- Maize nutrient deficiency diagnosis: N/P/K/Zn symptoms and treatments with CAN/DAP rates
- Fall Armyworm management: identification, scouting thresholds, Bt and chemical control
- Maize Lethal Necrosis: differential diagnosis vs nitrogen deficiency, notifiable disease guidance
- Tomato commercial guide: East African hybrids, nursery-to-harvest schedule, irrigation
- Tomato diseases: late blight, bacterial wilt, TYLCV prevention
- Soil management: East African soil types including red volcanic (Arusha/Kilimanjaro)
- Markets: maize, beans, tomato price bands for Kenya/Tanzania/Uganda
- Planting calendars: long rains (Masika) and short rains (Vuli) by zone

The RAG is **load-bearing**: on tp_001 (maize yellowing/nitrogen deficiency), retrieval surfaces the exact passage "Apply CAN at 50 kg/ha immediately" from the knowledge base — specificity that a 3B model would not reliably produce from training data alone.

### Swahili language support

The desktop UI is bilingual English ↔ Kiswahili via `assets/i18n/{en,sw}.json` and `TranslationController`. When the user switches language (or a Swahili query is detected), the system prompt adds `"Jibu kwa Kiswahili"` and RAG returns `content_sw` passages. Knowledge-base documents are authored with both `content` and `content_sw`.

This qualifies for the African Alpha Bonus (+15% on panel score).

### Application architecture

**Flutter desktop** (Linux primary, also Windows/macOS) with `llama-server` subprocess for inference:

- **`LlmService`** — launches `llama-server` as a child process, communicates via localhost SSE streaming. This uses the exact same llama.cpp binary that the ADTC profiler evaluates.
- **`RagService`** — pure Dart TF-IDF retrieval over bundled knowledge base assets. < 5ms latency, zero external dependencies.
- **`PromptService`** — assembles ChatML prompts within the 4096-token context budget (25% system / 30% RAG / 35% history / remaining user).
- **`ModelController`** — manages model lifecycle, sampler params (ported from Maathai mobile app).

Flutter was chosen over Python+PyQt6 because the team has deep Flutter expertise (production Maathai Android app) and large amounts of existing Dart code are directly reusable. Flutter Linux desktop adds ~50 MB overhead — negligible compared to the model's footprint.

---

## Constraints

### Hardware target
- 8 GB DDR4 RAM, 4 vCPU (Intel i5 or AMD Ryzen 5)
- Intel UHD / Iris Xe integrated GPU (no CUDA, no ROCm)
- Ubuntu 22.04 LTS
- 256 GB SSD

### Key hardware constraint implications
- No GPU acceleration: pure CPU inference via llama.cpp
- 7 GB RAM hard ceiling: any model exceeding this results in immediate disqualification
- 4 CPU threads: `n_threads=4` is optimal — using more can cause thermal throttling without proportional speed gains
- No internet: 100% offline during evaluation window; `download_model.sh` runs before profiling begins

### Data constraints
- Knowledge base must consist of publicly licensed agricultural documents
- No proprietary data, no scraping of paywalled content
- All documents are offline-bundled; no API calls to agricultural data services

---

## Benchmarks

*Self-reported development benchmarks from `adtc-profiler` participant mode. Official scores are measured by the ADTC profiler on the standard evaluation machine.*

| Metric | Value | Notes |
|---|---|---|
| **Development machine** | Ubuntu 22.04.5 LTS, 11th Gen Intel Core i7-1185G7 @ 3.00 GHz, 11.7 GB RAM, no discrete GPU | Participant laptop run |
| **Model** | `qwen2.5-3b-instruct-q4_k_m.gguf` | Qwen2.5-3B-Instruct Q4_K_M |
| **Peak RAM** | 3273.84 MB | Measured by adtc-profiler (`memory.peak_rss_mb`) |
| **Steady-state RAM** | 3149.29 MB | `memory.steady_state_rss_mb` |
| **Time to first token** | 18416.73 ms | Cold start on 512-token prompt (includes model/context warm path) |
| **Generation speed** | 8.03 t/s | Measured over 128-token burst |
| **Thermal throttling** | None observed | `cpu_thermal.throttled: false`; CPU p99 ≈ 52% |
| **Profiler mode** | participant | Accuracy suite not yet scored in this file (`accuracy: []`) |

**Estimated competition scores (from participant laptop numbers):**
```
Seff  = (7168 − 3273.84) / 7168 × 100  = 54.3
Sperf = min(8.03 / 15, 1.0) × 100      = 53.5
```

**Notes for Gate 1 judges:** Peak RSS is safely under the 7168 MB hard limit. Throughput on this host is below the 15 t/s `Sperf=100` reference; we will re-run on ADTC-equivalent 4-vCPU hardware and continue OpenBLAS / thread / batch tuning before final Gate scoring. No thermal throttle was observed at `n_threads=4`.
