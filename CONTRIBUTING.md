# Contributing to Maathai Desktop

This guide covers the development environment setup, project workflow, and coding conventions for the Maathai Desktop project.

---

## Development Environment Setup

### System Requirements

| Requirement | Minimum | Notes |
|---|---|---|
| OS | Ubuntu 22.04 LTS | Competition target; also works on Windows 10+, macOS 13+ |
| Python | 3.11 | Strictly 3.11 or newer (llama-cpp-python requires ≥3.8) |
| RAM | 8 GB | Match competition target hardware |
| Storage | 10 GB free | Model weights + ChromaDB index + venv |
| llama.cpp | Latest | `llama-bench` and `llama-server` must be on PATH |

### Step 1: Install llama.cpp

The ADTC evaluation uses `llama-bench` from llama.cpp. Install it on your system.

**Ubuntu 22.04:**
```bash
# Install build dependencies
sudo apt-get update
sudo apt-get install -y build-essential cmake git libopenblas-dev pkg-config

# Clone and build llama.cpp
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_BLAS=ON -DGGML_BLAS_VENDOR=OpenBLAS
cmake --build build --config Release -j$(nproc)

# Add to PATH (add to ~/.bashrc for persistence)
export PATH="$PATH:$(pwd)/build/bin"

# Verify
llama-bench --version
```

**Windows (PowerShell, for development only):**
```powershell
# Option A: Use pre-built binaries from GitHub releases
# https://github.com/ggerganov/llama.cpp/releases
# Download llama-<version>-bin-win-cpu-x64.zip, extract, add to PATH

# Option B: Build with CMake + Visual Studio
winget install cmake
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build
cmake --build build --config Release
# Add build\bin\Release to PATH
```

### Step 2: Set up Python environment

```bash
# Clone this repository
git clone https://github.com/YOUR_GITHUB/maathai-desktop.git
cd maathai-desktop

# Create virtual environment
python3.11 -m venv .venv

# Activate (Ubuntu/macOS)
source .venv/bin/activate

# Activate (Windows PowerShell)
.\.venv\Scripts\Activate.ps1

# Install dependencies
pip install --upgrade pip
pip install -r requirements.txt
```

### Step 3: Install the ADTC profiler

```bash
pip install "git+https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler.git"

# Verify
adtc-profiler --help
```

### Step 4: Download the model

```bash
# Run the download script (see PLAN.md for when the URL will be filled in)
bash download_model.sh

# Verify the model file exists
ls -lh model/*.gguf
```

### Step 5: Build the RAG index (first time only)

```bash
python src/rag/build_index.py
```

This reads all documents from `src/rag/knowledge_base/`, embeds them with `all-MiniLM-L6-v2`, and stores the index in `data/chroma_db/`. Takes ~2 minutes on first run.

### Step 6: Launch the application

```bash
python src/app.py
```

---

## Project Structure

```
maathai-desktop/
├── src/
│   ├── app.py               # Entry point — run this
│   ├── config.py            # Paths, model config, language settings
│   ├── llm/
│   │   ├── inference.py     # LlamaInference class (llama-cpp-python wrapper)
│   │   ├── prompt_engine.py # PromptEngine (ported from AgriculturalPromptService.dart)
│   │   ├── language_router.py
│   │   ├── insight_engine.py
│   │   └── llm_parser.py
│   ├── rag/
│   │   ├── build_index.py   # Run once to build ChromaDB index
│   │   ├── embedder.py
│   │   ├── retriever.py
│   │   └── knowledge_base/  # Curate documents here
│   └── ui/
│       ├── main_window.py
│       ├── chat_view.py
│       ├── knowledge_view.py
│       ├── benchmark_view.py
│       └── i18n/
└── tests/
```

---

## Development Workflow

### Making changes to the inference layer

1. Edit `src/llm/inference.py` or `src/llm/prompt_engine.py`
2. Run unit tests (fast, no model needed):
   ```bash
   pytest tests/test_prompt_engine.py tests/test_language.py -v -m "unit"
   ```
3. Run inference tests (requires model):
   ```bash
   pytest tests/test_inference.py -v
   ```

### Making changes to the knowledge base

1. Add or edit documents in `src/rag/knowledge_base/`
2. Rebuild the index:
   ```bash
   python src/rag/build_index.py
   ```
3. Run RAG tests:
   ```bash
   pytest tests/test_rag.py -v
   ```

### Running the full test suite

```bash
# Fast tests only (no model)
pytest tests/ -v -m "unit" --tb=short

# Full suite (requires model downloaded)
pytest tests/ -v --tb=short

# Skip performance tests (faster CI)
pytest tests/ -v --ignore=tests/test_performance.py
```

### Running the ADTC profiler locally

Always run the profiler before committing changes that affect inference:

```bash
adtc-profiler run \
  --submission . \
  --mode participant \
  --output submission.json \
  --skip-accuracy

# Check key metrics
python -c "
import json
with open('submission.json') as f: s = json.load(f)
print('Peak RAM:', s['memory']['peak_rss_mb'], 'MB')
print('TPS:', round(s['throughput']['tokens_per_second_generation'], 1))
print('Seff:', round((7168 - s['memory']['peak_rss_mb']) / 7168 * 100, 1))
print('Sperf:', round(min(s['throughput']['tokens_per_second_generation'] / 15, 1) * 100, 1))
"
```

---

## Porting from the Mobile App

A significant part of Maathai Desktop is ported from `D:\Github\v2\Maathai_app-main\example`. When porting:

### Mapping (Dart → Python)

| Dart pattern | Python equivalent |
|---|---|
| `ChangeNotifier` | `dataclasses` + observer pattern or Qt signals |
| `async/await` | `asyncio` or synchronous (PyQt6 uses QThread for background tasks) |
| `Stream<String>` | Python `Generator[str]` or `Queue` |
| `rootBundle.loadString()` | `Path("...").read_text()` |
| `jsonEncode/jsonDecode` | `json.dumps` / `json.loads` |
| `Logger.info/error` | Python `logging` module |

### Key porting decisions

- `AgriculturalPromptService.dart` → `src/llm/prompt_engine.py`
  - Cache uses `functools.lru_cache` or a plain `dict` (32 entries max, same as mobile)
  - Location uses static config from `config.py` (no GPS on desktop)
  - `{{location}}` placeholder resolved from user settings, defaulting to "East Africa"

- `ModelController.dart` → `src/llm/inference.py`
  - All sampler params are the same: temp=0.7, topK=40, topP=0.95
  - Dynamic max tokens: `context_length − int(len(prompt) / 4) − 100`

- `InsightService.dart` → `src/llm/insight_engine.py`
  - Tiered fallback: local LLM → rules (no cloud tier — evaluation must be offline)
  - Same rule-based fallback logic for when no model is loaded

---

## Code Style

- **Python version target:** 3.11
- **Formatter:** `black` (line length 100)
- **Linter:** `ruff`
- **Type hints:** required on all public functions
- **Docstrings:** Google style, only on non-obvious functions
- **No emojis in code** (consistency with system prompt guideline)

```bash
# Format
black src/ tests/ --line-length 100

# Lint
ruff check src/ tests/
```

---

## Branching Convention

| Branch | Purpose |
|---|---|
| `main` | Always submission-ready; must pass profiler |
| `phase/0-porting` | Phase 0 work (mobile app porting) |
| `phase/1-model-selection` | Phase 1 (model benchmarking) |
| `phase/2-knowledge-base` | Phase 2 (RAG corpus curation) |
| `phase/3-ui` | Phase 3 (PyQt6 application) |
| `phase/4-finetune` | Phase 4 (optional fine-tuning) |
| `fix/...` | Bug fixes to merge into current phase |

---

## Before Opening a Pull Request

- [ ] `pytest tests/ -v -m "unit"` passes
- [ ] `pytest tests/test_inference.py` passes (if LLM code changed)
- [ ] `adtc-profiler run --mode participant --skip-accuracy` produces valid JSON
- [ ] Peak RAM still < 3500 MB (target) or at minimum < 7168 MB (hard limit)
- [ ] No placeholder values introduced into `metadata.json`
- [ ] No `.gguf` files staged
- [ ] `black` and `ruff` clean

---

## Contacts

- Competition: challenge@africadeeptech.org
- Template issues: [adtc-2026-submission-template](https://github.com/Africa-Deep-Tech-Foundation/adtc-2026-submission-template/issues)
- Profiler issues: [adtc-profiler](https://github.com/Africa-Deep-Tech-Foundation/adtc-profiler/issues)
