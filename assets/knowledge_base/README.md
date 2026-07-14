# Maathai Desktop — Knowledge Base (RAG Corpus)

Offline agricultural documents bundled as Flutter assets. Loaded at app startup by `RagService` (`lib/services/rag_service.dart`) and injected into LLM prompts by `PromptService`.

**Competition constraints:** publicly licensed content only, 100% offline, no paywalled scraping. All documents ship inside the app — no runtime download.

---

## Directory layout

```
assets/knowledge_base/
├── crops/       Varieties, agronomy, nutrient deficiency (maize.json, tea.json, …)
├── pests/       Insects, diseases, management (pests_diseases.json)
├── livestock/   Goats, cattle, poultry (livestock.json)
├── soil/        pH, fertility, erosion (soil_management.json)
├── markets/     Ex-farm prices, selling tips (market_prices.json)
└── calendars/   Long/short rains planting windows (planting_calendars.json)
```

Each subfolder must be listed under `flutter: assets:` in `pubspec.yaml`.

---

## File format

Each `*.json` file is a **JSON array** of document objects:

```json
[
  {
    "id": "crop_maize_nutrient_deficiency",
    "title": "Maize Nutrient Deficiency — Diagnosis Guide",
    "category": "crops",
    "tags": ["maize", "yellow leaves", "nitrogen", "Nakuru", "deficiency"],
    "content": "## Heading\n\nEnglish body. Use Markdown. Put key terms early.",
    "content_sw": "## Kichwa\n\nKiswahili body. Required for African Alpha / Swahili mode."
  }
]
```

### Field reference

| Field | Required | Used by RAG |
|-------|----------|-------------|
| `id` | Recommended | Stable identifier; fallback is asset path |
| `title` | Yes | Indexed; shown in `[category: title]` prefix |
| `content` | Yes | Indexed (English); injected when language is `en` |
| `content_sw` | Strongly recommended | Injected when farm language is `sw` |
| `tags` | Recommended | Indexed (helps queries like “Arusha tomato price”) |
| `category` | Optional | Folder name is used if omitted |

### Authoring guidelines

1. **One topic per object** — e.g. separate entries for “maize overview” vs “N deficiency”.
2. **Front-load facts** — passages are trimmed to **800 characters** before prompt injection.
3. **Use searchable terms** in `title`, `tags`, and opening lines: crop names, regions (Nakuru, Arusha), inputs (CAN, DAP), pests (FAW, MLN).
4. **Be specific** — dosages, varieties (H614D, Anna F1), prices (KES/kg, TZS/kg), weeks after planting.
5. **Bilingual** — always add `content_sw` for competition Swahili claim.
6. **Sources** — paraphrase public extension guidance (KALRO, FAO, ICIPE); do not paste copyrighted text.

---

## How retrieval works

- **Algorithm:** TF-IDF + cosine similarity (pure Dart, no embeddings).
- **At startup:** all `*.json` under the six folders are parsed into memory.
- **On each chat message:** top **3** passages (score ≥ 0.05) are retrieved and appended to the prompt.
- **Language:** `content_sw` is used when context panel / settings language is `sw`.
- **Tests:** Python mirror in `src/rag/tfidf_retriever.py` reads the same files for `pytest tests/test_rag.py`.

Prompt injection shape:

```
Relevant agricultural knowledge:
---
[crops: Maize Nutrient Deficiency — Diagnosis Guide]
## Maize Nutrient Deficiency...
---
```

In the app, users see the same text via **View sources** on assistant replies.

---

## Adding or editing documents

1. Edit or create a `.json` file in the appropriate category folder.
2. Validate JSON (array of objects, required fields present).
3. Hot restart the app (`R` in `flutter run`).
4. Verify:
   - **Knowledge** tab lists/browse works
   - Chat query returns expected **View sources**
   - `pytest tests/test_rag.py -v -m rag`

---

## Competition coverage map

| Evaluation topic | Primary files |
|------------------|---------------|
| tp_001 — maize yellowing / Nakuru | `crops/maize.json`, `pests/pests_diseases.json` |
| tp_002 — tomato / Arusha commercial | `crops/maize.json` (tomato entry), `markets/market_prices.json`, `calendars/planting_calendars.json` |
| Hidden — fall armyworm | `pests/pests_diseases.json` |
| Hidden — goat lethargy / milk drop | `livestock/livestock.json` |
| Hidden — livestock / poultry | `livestock/livestock.json` |

Target: **14+ crop topics**, full pest/livestock/soil/market/calendar coverage (see `PROJECT_PLAN.md` Phase 2).

---

## Current inventory

| File | Topics |
|------|--------|
| `crops/maize.json` | Maize overview, N deficiency, tomato guide |
| `crops/cereals.json` | Sorghum, millet, wheat, rice |
| `crops/beans_cassava.json` | Beans, cassava |
| `crops/tea.json`, `coffee.json`, `other_crops.json` | Tea, coffee, banana, etc. |
| `pests/pests_diseases.json` | FAW, MLN, tomato diseases, stem borer |
| `livestock/livestock.json` | PPR, parasites, Newcastle, mastitis |
| `soil/soil_management.json` | pH, organic matter, lime |
| `markets/market_prices.json` | East Africa commodity prices |
| `calendars/planting_calendars.json` | Bimodal rains calendar |

Run `RagService.documentCount` at startup (logged as `RagService ready (N docs)` in `maathai.log`).
