# Technical Report — Maathai Desktop

**Team ID:** maathai-desktop  
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

`llama.cpp` via `llama-server` (HTTP/SSE on localhost) is the only permitted runtime. Key configuration for the ADTC standard laptop (tuned with `scripts/benchmark_tune_wsl.sh` + `scripts/benchmark_extra_flags_wsl.sh`):

```
n_ctx           = 4096     # RAG context + prompt budget
n_threads       = 4        # ADTC 4 vCPU; >4 oversubscribes and lowers TPS
n_threads_batch = 4        # match prompt processing to gen threads
n_batch         = 2048     # best gen TPS in batch sweep (vs 512/1024)
n_ubatch        = 512      # llama.cpp default physical micro-batch
n_gpu_layers    = 0        # CPU-only (integrated GPU)
flash_attn      = on       # ~15% gen TPS gain vs flash-attn off on Qwen2.5-3B
mlock           = on       # keep weights resident; peak RSS still ~3.3 GB
prio            = 0        # omit --prio; unprivileged Linux cannot setpriority(1)
cache_type_k/v  = f16      # fastest KV; q8_0 is a RAM tradeoff if needed
OMP/OpenBLAS    = 4        # env caps so BLAS cannot oversubscribe CPUs
temperature     = 0.7
top_k           = 40
top_p           = 0.95
repeat_penalty  = 1.1
max_tokens      = 256      # shorter replies on 15W U-class CPUs; settings slider still allows more
```

These parameters are ported from `ModelController.dart` in the Maathai mobile app (sampler) and refined for desktop via llama-bench sweeps on the competition GGUF.

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

### Hardware target (ADTC Standard Laptop — current rules)
- 8 GB DDR4 RAM, 4 vCPU
- CPU: Intel Core i5 10th–12th gen **or** AMD Ryzen 5 3000–5000 (x86-64)
- Integrated graphics only (Intel UHD / Iris Xe or AMD Radeon integrated; no discrete GPU / CUDA / ROCm)
- Ubuntu 22.04 LTS
- 256 GB SSD
- Market range: ~$400–$500 new / ~$150–$250 refurbished

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

| Metric | This laptop (2026-08-21) | Earlier WSL smoke (2026-08-04) | Notes |
|---|---|---|---|
| **Development machine** | Ubuntu 24.04.4 / i7-10610U / 15.4 GB / no dGPU | Ubuntu 22.04.5 / i7-1185G7 / 11.7 GB / WSL | 15W U vs 28W Tiger Lake |
| **Model** | `qwen2.5-3b-instruct-q4_k_m.gguf` | same | Qwen2.5-3B-Instruct Q4_K_M |
| **Peak RAM** | **3176.89 MB** | 3273.79 MB | Hard limit 7168 MB — PASS |
| **Steady-state RAM** | 2824.66 MB | 3140.45 MB | |
| **Time to first token** | 48792.58 ms | 21200.96 ms | Cold 512-token prompt |
| **Generation speed** | **3.59 t/s** | 5.64 t/s | Official `llama-bench -ngl 0`; neither hits provisional 15 t/s |
| **Thermal throttling** | **true** (package 100 °C) | false (CPU p99 ≈ 52%) | −10 Pthermal risk on this 15W U host |
| **Accuracy** | native n=50 **restarted 2026-08-24** (prior job died at 38/200) | WSL docs cite 0.34 n=50 (JSON not on this host) | Do not attach empty `accuracy` |

**Smoke / participant verdict (this laptop, 2026-08-21):**
| Gate | Result |
|---|---|
| Peak RSS &lt; 7168 MB | **PASS** (~3177 MB → Seff ≈ 55.7) |
| No thermal throttle | **WARN** — package 100 °C, `throttled: true` |
| TPS ≥ 15 (provisional Sperf=100) | **WARN** — 3.59 t/s on this host |
| Accuracy suite filled | **Pending** — `submission.json` still `[]` until the 2026-08-24 native ARC-Easy n=50 job finishes |

**Estimated competition scores (this laptop, throughput/RAM only):**
```
Seff  = (7168 − 3176.89) / 7168 × 100  = 55.7

# Local / profiler provisional estimate (TPS_REFERENCE = 15.0):
Sperf ≈ min(3.59 / 15, 1.0) × 100     = 23.9

# Official DevPost leaderboard formula (relative to field max):
Sperf = 100 × (TPSact ÷ TPSmax)         # TPSmax = fastest audit submission
```

**Accuracy (separate from smoke):**
- Path: `scripts/run_maathai_accuracy.py` (llama-cpp-python; stock `lm_eval --model gguf` incompatible with current llama-server logprobs)
- Validated 2026-08-05: ARC-Easy **limit=2 → score 1.0** (~33 min, model on Linux home FS)
- 2026-08-21: first native `gate1_verify.sh` wrote empty `accuracy` because llama-cpp-python could not find `libggml-cpu` (fixed in `scripts/maathai_lm_eval_model.py` + `scripts/gate1_verify.sh`)
- Native limit=50 started 2026-08-21 died at **38/200** (~4 h, no score). Restarted **2026-08-24 17:13 EAT**; merge the printed JSON row into `submission.json` when it finishes (~15–20 h).
- Do not copy undocumented WSL 0.34 into this machine's `submission.json`.

**Rules alignment (as of August 2026):**
- Composite: `Stotal = 0.50×Sacc + 0.30×Sperf + 0.20×Seff − Pthermal` (unchanged)
- `Seff` still uses the 7 GB peak-RSS budget (unchanged)
- `Sperf` on DevPost is relative to **TPSmax across submissions**; `adtc-profiler` still documents the 15 t/s provisional reference for local estimates
- African language / use-case bonus claimed via Swahili (`african_alpha_claim: true`)
- Gate 1 due **August 25, 2026**

**Tuning follow-up (WSL llama-bench on same GGUF, `-p 512 -n 128`):**
- Best app/server defaults: `-t 4 -b 2048 --flash-attn on --mlock` (see § Inference runtime)
- Flash-attn on ≈ **9.4 t/s** vs ≈ **8.1 t/s** with flash-attn off (~15% gain on this host)
- Batch 2048 beats 512/1024; threads >4 lower TPS (oversubscription on 4 logical CPUs)
- Official Gate `Sperf` still comes from `adtc-profiler` / `llama-bench` defaults — re-run on ADTC-class 4-vCPU Ubuntu for a fairer TPS number

**Status as of August 24, 2026 (17:00 EAT):** Packaging checks pass (submission pytest 30 passed / 1 skipped). Peak RSS **PASS** (3177 MB). TPS **3.59 t/s** and thermal **WARN** (100 °C). `submission.json` RAM/TPS/thermal are from the 2026-08-21 participant profiler; **accuracy is still empty** until today's native ARC-Easy n=50 job finishes. DevPost due **today 23:45 PDT**. Human remaining: airplane-mode EN+SW, ≤2 min video, DevPost form (repo is public).
