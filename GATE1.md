# Gate 1 Close-Out — Maathai Desktop

**Deadline:** August 25, 2026 (DevPost: Aug 24, 2026 @ 11:45pm PDT)  
**Team:** 1060310 · Agriculture · Qwen2.5-3B-Instruct Q4_K_M

Gate 1 is packaging: public repo + `REPORT.md` + working prototype evidence + ≤2 min video. Finish technical verify first, then film.

---

## 1. Automated verify (Ubuntu 22.04 / WSL)

From repo root:

```bash
# Full Gate 1 artifact (accuracy ON — use for final submission.json)
bash scripts/gate1_verify.sh

# Same, but cap the process tree at 8 GiB like the ADTC laptop (native Linux)
bash scripts/gate1_verify.sh --mem-8g

# Fast iterate while fixing toolchain
bash scripts/gate1_verify.sh --smoke
bash scripts/gate1_verify.sh --smoke --mem-8g

# Human remaining tasks only
bash scripts/gate1_verify.sh --checklist
```

**Do we need more tests?** No more llama-bench / RAM smoke loops. Peak RSS already PASSes with ~4 GB of headroom. Throughput and heat on the 15W U laptop will not improve by re-measuring.

**Do we need one more profiler run?** Yes — one **full** (`no --smoke`) run whose `submission.json` has a non-empty `accuracy` array. Prefer `--mem-8g` so that artifact matches the 8 GB evaluation laptop. If ARC-Easy limit=50 is already running on this host, **let it finish**; then run `--smoke --mem-8g` only if you still want an 8 GB RAM proof. Do not kill a live accuracy job to restart under 8 GB.

**WSL 8 GB cap:** `systemd-run` cannot limit WSL2 host RAM. Put this in `%UserProfile%\.wslconfig`, then `wsl --shutdown` and reopen:

```ini
[wsl2]
memory=8GB
processors=4
```

After a full run:

1. Confirm `submission.json` → `accuracy` is **not** `[]`
2. Confirm `memory.peak_rss_mb` &lt; 7168
3. Copy TPS / RAM / TTFT into `REPORT.md` § Benchmarks
4. Keep `submission.json` locally (gitignored) for DevPost / judges

**Accuracy note:** stock `lm_eval --model gguf` + current `llama-server` cannot do ARC loglikelihood (OpenAI logprobs are completion-only).  
`gate1_verify.sh` (full mode) patches `adtc-profiler` to call `scripts/run_maathai_accuracy.py`, which scores via **llama-cpp-python** echo logprobs.

**Timing (WSL, model on `/home/...` not `/mnt/d`):**
- Smoke verify (`--smoke`): ~5–10 min (TPS/RAM only)
- Accuracy limit=2: ~30–40 min (validated 2026-08-05, score 1.0)
- Full accuracy limit=50 (default Gate 1): **~6–10 hours** — start overnight
- Never run accuracy against a GGUF on `/mnt/d` (orders of magnitude slower)

---

## 2. Manual checklist

| # | Task | Owner cue |
|---|---|---|
| 1 | Repo **public** on GitHub | ✅ `kipkirui/Maathai_Desktop` is already public |
| 2 | `git ls-files '*.gguf'` empty | Never commit weights |
| 3 | Fresh-clone `bash download_model.sh` on Ubuntu | Same machine judges use profile |
| 4 | Full profiler JSON with accuracy | `gate1_verify.sh` (no `--smoke`) |
| 5 | Offline proof (airplane mode) | One EN + one SW chat |
| 6 | Demo video ≤ 2:00 uploaded | Shot list below |
| 7 | DevPost form + Git commit hash URL | Submit early; edit until deadline |

---

## 3. Demo video shot list (≤ 2:00)

Target total **~1:50**. Record 1080p; voiceover or on-screen captions OK.

| Time | Shot | What to show / say |
|---|---|---|
| 0:00–0:15 | Title | “Maathai Desktop — offline agriculture AI for 8 GB laptops. ADTC 2026, Team 1060310.” |
| 0:15–0:30 | Boot + offline | App open; status shows model loaded; mention **no internet** (airplane mode icon or unplugged). |
| 0:30–1:00 | English Q&A (`tp_001`) | Paste maize yellowing / Nakuru prompt. Stream answer. Call out **specific treatment** (e.g. CAN rate) from RAG. |
| 1:00–1:25 | Swahili | Switch language → ask one short crop question in Kiswahili → show Swahili reply (African Alpha claim). |
| 1:25–1:40 | Knowledge + Models | Quick Knowledge browser + Models screen (GGUF / llama.cpp). |
| 1:40–1:55 | Close | “100% offline · llama.cpp · East Africa RAG · Swahili. Repo: github.com/kipkirui/Maathai_Desktop” |

**Prompts to keep on clipboard**

EN (`tp_001` shortened if needed for time):

> My maize leaves are turning yellow with brown spots from the lower leaves up. Farm in Nakuru, Kenya, 3 weeks dry, plants 8 weeks old. What is wrong and what treatment do you recommend?

SW (short):

> Majani ya mahindi yangu yanaanza kuwa manjano. Ni upungufu gani wa virutubisho na nitumie mbolea gani?

**Do not** spend video time on architecture slides — judges want the model running.

---

## 4. After video

- Upload (YouTube unlisted or Drive) and paste URL into DevPost  
- Attach/link public GitHub repo  
- Keep working tree clean at the commit hash you submit  

---

## 5. What not to do before Aug 18

- Fine-tune experiments that block packaging  
- UI polish (thumbs / PDF / regenerate)  
- Expanding the knowledge base further  

Those help later gates; they do not unlock Gate 1.
