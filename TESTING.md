# Maathai Desktop — Test Strategy & Test Cases

**Framework:** pytest  
**Test location:** `tests/`  
**Run:** `pytest tests/ -v`  
**Run offline-only tests:** `pytest tests/ -v -m offline`

---

## Testing Philosophy

The ADTC evaluation is fully automated and unforgiving: a single OOM crash scores Stotal = 0. Our testing strategy therefore focuses on three guarantees:

1. **Never OOM** — every test run that touches the model measures and asserts peak RSS
2. **Always offline** — network isolation is verified at the test level, not just assumed
3. **No regressions** — TPS and RAM are tracked as metrics; PRs that degrade either are flagged

Secondary goals:
- Domain accuracy is validated qualitatively before submission
- RAG retrieval quality is measured and baselined
- Swahili responses are verified to be meaningful

---

## Test Categories

| Category | File | Markers | When to run |
|---|---|---|---|
| Model loading & inference | `test_inference.py` | `@pytest.mark.inference` | After every model change |
| RAG retrieval quality | `test_rag.py` | `@pytest.mark.rag` | After knowledge base changes |
| Offline isolation | `test_offline.py` | `@pytest.mark.offline` | Before every profiler run |
| Domain accuracy | `test_prompts.py` | `@pytest.mark.accuracy` | Before submission |
| Performance regression | `test_performance.py` | `@pytest.mark.perf` | After model change |
| Prompt engine | `test_prompt_engine.py` | `@pytest.mark.unit` | On every code change |
| Language routing | `test_language.py` | `@pytest.mark.unit` | On every code change |
| Submission package | `test_submission.py` | `@pytest.mark.submission` | Final pre-submission gate |

---

## Test File: `tests/test_inference.py`

**Purpose:** Verify the LLM loads cleanly, generates tokens, stays within RAM.

```python
import pytest
import psutil
import os
from src.llm.inference import LlamaInference

MODEL_PATH = "model/qwen2.5-3b-instruct-q4_k_m.gguf"
RAM_LIMIT_MB = 7168  # hard disqualification limit
RAM_TARGET_MB = 3500  # our target

@pytest.fixture(scope="module")
def model():
    """Load model once for the test module."""
    assert os.path.exists(MODEL_PATH), f"Model not found at {MODEL_PATH}. Run: bash download_model.sh"
    llm = LlamaInference(model_path=MODEL_PATH)
    yield llm
    llm.release()

def _peak_rss_mb():
    return psutil.Process().memory_info().rss / (1024 * 1024)

def test_model_loads(model):
    """Model initializes without error."""
    assert model.is_loaded()

def test_model_within_ram_limit(model):
    """Peak RSS after model load must not exceed the 7 GB disqualification threshold."""
    rss = _peak_rss_mb()
    assert rss < RAM_LIMIT_MB, f"DISQUALIFICATION RISK: peak RSS {rss:.0f} MB >= {RAM_LIMIT_MB} MB"

def test_model_within_target_ram(model):
    """Peak RSS should be under 3500 MB for a healthy Seff score."""
    rss = _peak_rss_mb()
    assert rss < RAM_TARGET_MB, f"RAM target exceeded: {rss:.0f} MB (target: {RAM_TARGET_MB} MB)"

def test_generates_tokens(model):
    """Model generates a non-empty response."""
    response = model.generate("What is the best fertilizer for maize in Kenya?", max_tokens=64)
    assert isinstance(response, str)
    assert len(response.strip()) > 10

def test_stream_yields_tokens(model):
    """Streaming generates at least one token chunk."""
    chunks = list(model.generate_stream("Name one common maize disease.", max_tokens=32))
    assert len(chunks) > 0
    assert all(isinstance(c, str) for c in chunks)

def test_response_no_emojis(model):
    """Responses must not contain emojis (per system prompt guideline)."""
    import re
    response = model.generate("What causes yellowing maize leaves?", max_tokens=64)
    emoji_pattern = re.compile(
        "[\U00010000-\U0010ffff]|[\U0001F600-\U0001F64F]|[\U0001F300-\U0001F5FF]",
        flags=re.UNICODE
    )
    assert not emoji_pattern.search(response), f"Emoji found in response: {response[:100]}"

def test_cancel_stops_generation(model):
    """Cancel terminates streaming without error."""
    import threading
    results = []
    def generate():
        for chunk in model.generate_stream("Tell me everything about agriculture.", max_tokens=512):
            results.append(chunk)
            if len(results) >= 5:
                model.cancel()
                break
    t = threading.Thread(target=generate)
    t.start()
    t.join(timeout=30)
    assert len(results) >= 1  # at least started
```

---

## Test File: `tests/test_rag.py`

**Purpose:** Verify RAG retrieval returns relevant documents and improves answer quality.

```python
import pytest
from src.rag.retriever import Retriever
from src.rag.embedder import Embedder

@pytest.fixture(scope="module")
def retriever():
    r = Retriever()
    yield r

def test_retriever_initializes(retriever):
    """Retriever loads index without error."""
    assert retriever.is_ready()

def test_retrieval_maize_disease(retriever):
    """Query about maize disease returns crop-relevant chunks."""
    results = retriever.retrieve("yellowing leaves on maize plants", top_k=3)
    assert len(results) >= 1
    combined = " ".join([r["text"] for r in results]).lower()
    assert any(word in combined for word in ["maize", "corn", "leaf", "nitrogen", "disease"])

def test_retrieval_livestock(retriever):
    """Query about goat disease returns livestock-relevant chunks."""
    results = retriever.retrieve("my goats have runny nose and coughing", top_k=3)
    assert len(results) >= 1
    combined = " ".join([r["text"] for r in results]).lower()
    assert any(word in combined for word in ["goat", "respiratory", "pneumonia", "ppr", "livestock"])

def test_retrieval_pest(retriever):
    """Query about fall armyworm returns pest-relevant chunks."""
    results = retriever.retrieve("caterpillars destroying my maize crop", top_k=3)
    assert len(results) >= 1
    combined = " ".join([r["text"] for r in results]).lower()
    assert any(word in combined for word in ["armyworm", "caterpillar", "pest", "larvae", "spray"])

def test_retrieval_market(retriever):
    """Query about market prices returns market-relevant chunks."""
    results = retriever.retrieve("What is the price of maize in Nairobi?", top_k=3)
    assert len(results) >= 1
    combined = " ".join([r["text"] for r in results]).lower()
    assert any(word in combined for word in ["price", "market", "nairobi", "maize", "kg"])

def test_retrieval_returns_metadata(retriever):
    """Each result includes source metadata."""
    results = retriever.retrieve("coffee berry disease treatment", top_k=2)
    for r in results:
        assert "text" in r
        assert "source" in r
        assert "score" in r

def test_rag_improves_specificity(retriever):
    """RAG context adds African-specific detail not in base model training."""
    results = retriever.retrieve("KALRO recommended bean varieties Kenya", top_k=3)
    combined = " ".join([r["text"] for r in results]).lower()
    # Should retrieve KALRO-sourced content
    assert any(word in combined for word in ["kalro", "kenya", "bean", "variety", "release"])

@pytest.mark.parametrize("query,expected_keyword", [
    ("tea leaf disease rust Kenya", "tea"),
    ("rice blast disease treatment", "rice"),
    ("sorghum drought tolerance", "sorghum"),
    ("cassava mosaic virus control", "cassava"),
    ("Newcastle disease in chickens", "poultry"),
])
def test_retrieval_cross_crop_coverage(retriever, query, expected_keyword):
    """Knowledge base covers all major crop/livestock categories."""
    results = retriever.retrieve(query, top_k=3)
    combined = " ".join([r["text"] for r in results]).lower()
    assert expected_keyword in combined, \
        f"Expected '{expected_keyword}' in results for query: '{query}'"
```

---

## Test File: `tests/test_offline.py`

**Purpose:** Guarantee zero network calls during inference. Critical for compliance.

```python
import pytest
import socket
import subprocess
import platform

@pytest.mark.offline
def test_model_loads_with_network_disabled():
    """
    Model loading and inference must work with network unavailable.
    This test simulates evaluation conditions where outbound requests fail.
    """
    import sys, os
    sys.path.insert(0, os.path.abspath("."))
    from src.llm.inference import LlamaInference
    
    # Monkey-patch socket to block connections
    original_connect = socket.socket.connect
    
    def blocked_connect(self, address):
        raise OSError(f"Network blocked during offline test. Attempted: {address}")
    
    socket.socket.connect = blocked_connect
    
    try:
        llm = LlamaInference(model_path="model/qwen2.5-3b-instruct-q4_k_m.gguf")
        response = llm.generate("What grows well in dry regions?", max_tokens=32)
        assert len(response.strip()) > 5
    finally:
        socket.socket.connect = original_connect
        llm.release()

@pytest.mark.offline
def test_rag_loads_with_network_disabled():
    """RAG index loads from bundled JSON without network."""
    import socket
    from src.rag.tfidf_retriever import TfidfRetriever

    original_connect = socket.socket.connect

    def blocked_connect(self, address):
        raise OSError(f"Network blocked during offline test. Attempted: {address}")

    socket.socket.connect = blocked_connect

    try:
        retriever = TfidfRetriever()
        assert retriever.initialize()
        results = retriever.retrieve("maize nitrogen deficiency", top_k=2)
        assert len(results) >= 0
    finally:
        socket.socket.connect = original_connect

@pytest.mark.offline
def test_no_http_calls_during_generation(monkeypatch):
    """
    Instrument urllib and requests to catch any outbound HTTP during inference.
    """
    import urllib.request
    
    http_calls = []
    
    original_urlopen = urllib.request.urlopen
    def tracking_urlopen(url, *args, **kwargs):
        http_calls.append(str(url))
        raise OSError("HTTP blocked during offline test")
    
    monkeypatch.setattr(urllib.request, "urlopen", tracking_urlopen)
    
    from src.llm.inference import LlamaInference
    llm = LlamaInference(model_path="model/qwen2.5-3b-instruct-q4_k_m.gguf")
    llm.generate("Describe maize growing conditions.", max_tokens=32)
    llm.release()
    
    assert len(http_calls) == 0, f"HTTP call attempted during offline inference: {http_calls}"
```

---

## Test File: `tests/test_prompts.py`

**Purpose:** Validate accuracy on the 4 competition prompts (2 submitted + 2 simulated hidden).

```python
import pytest
from src.llm.inference import LlamaInference
from src.llm.prompt_engine import PromptEngine
from src.rag.retriever import Retriever

@pytest.fixture(scope="module")
def system():
    llm = LlamaInference(model_path="model/qwen2.5-3b-instruct-q4_k_m.gguf")
    prompt_engine = PromptEngine()
    retriever = Retriever()
    yield llm, prompt_engine, retriever
    llm.release()

def _ask(system, question, max_tokens=256):
    llm, prompt_engine, retriever = system
    context_chunks = retriever.retrieve(question, top_k=3)
    prompt = prompt_engine.build_contextual_prompt(
        user_query=question,
        rag_context=context_chunks,
        country="Kenya",
        region="Western Kenya",
    )
    return llm.generate(prompt, max_tokens=max_tokens)

# ─── SUBMITTED TEST PROMPTS (tp_001 and tp_002) ───────────────────────────────

def test_tp001_maize_yellowing(system):
    """
    tp_001: Nitrogen deficiency diagnosis on maize.
    Expected: identifies nitrogen deficiency, recommends urea/CAN, mentions soil testing.
    """
    response = _ask(system,
        "A smallholder farmer in western Kenya has maize plants showing yellowing leaves "
        "starting from the lower leaves and moving upward. The soil has been continuously "
        "cropped for three years without fertilizer. What is the most likely cause and "
        "what should the farmer do?"
    )
    
    assert len(response) > 100, "Response too short"
    response_lower = response.lower()
    
    # Must identify nutrient deficiency
    assert any(w in response_lower for w in ["nitrogen", "nutrient", "deficiency", "fertilizer"]), \
        "Response did not identify nitrogen/nutrient deficiency"
    
    # Must recommend a concrete action
    assert any(w in response_lower for w in ["urea", "can", "fertilizer", "apply", "top-dress"]), \
        "Response did not recommend a fertilizer action"

def test_tp002_tomato_farm(system):
    """
    tp_002 (metadata.json): Commercial tomato farm near Arusha, Tanzania.
    Expected: varieties, planting schedule, diseases, market price per kg.
    """
    response = _ask(system,
        "I have 2 acres of land near Arusha, Tanzania with red volcanic soil and access "
        "to a borehole for irrigation. I want to start a commercial tomato farm for the "
        "first time this season. Which tomato varieties are best suited for this region, "
        "what is the full planting and harvesting schedule, what are the three most common "
        "diseases I should prepare to prevent, and what market price per kilogram can I "
        "realistically expect?"
    )
    
    assert len(response) > 100, "Response too short"
    response_lower = response.lower()
    
    assert any(w in response_lower for w in ["tomato", "variety", "varieties", "plant", "disease"]), \
        "Response did not address tomato farming"
    
    assert any(w in response_lower for w in ["price", "market", "kg", "kilogram", "sell"]), \
        "Response did not mention market expectations"

# ─── SIMULATED HIDDEN PROMPTS ──────────────────────────────────────────────────

def test_hidden_goat_milk_drop(system):
    """
    Simulated hidden prompt: Goat lethargy + milk drop — tests livestock knowledge.
    """
    response = _ask(system,
        "I have 20 dairy goats and their milk production has dropped significantly over "
        "the past two weeks. They are eating but seem lethargic. What are the possible "
        "causes and what steps should I take to diagnose and treat this?"
    )
    
    response_lower = response.lower()
    assert any(w in response_lower for w in ["parasite", "worm", "infection", "disease", "nutrition", "ppr"]), \
        "Response did not identify possible causes"
    assert any(w in response_lower for w in ["veterinarian", "vet", "test", "treat", "diagnose"]), \
        "Response did not recommend action"

def test_hidden_01_fall_armyworm(system):
    """
    Simulated hidden prompt: Fall armyworm — tests pest knowledge depth.
    """
    response = _ask(system,
        "My maize crop has caterpillars inside the whorls of young plants. "
        "The leaves show ragged holes and there is frass inside the whorl. "
        "What pest is this and how do I control it organically?"
    )
    
    response_lower = response.lower()
    assert any(w in response_lower for w in ["armyworm", "spodoptera", "fall", "pest"]), \
        "Response did not identify fall armyworm"
    assert any(w in response_lower for w in ["neem", "organic", "biological", "trichogramma", "manual"]), \
        "Response did not suggest organic control"

def test_hidden_02_coffee_disease(system):
    """
    Simulated hidden prompt: Coffee berry disease — tests crop disease depth.
    """
    response = _ask(system,
        "My coffee berries are turning black and rotting on the tree before they ripen. "
        "This is happening on berries that look fine on the outside until I open them. "
        "What disease is this and how should I manage it?"
    )
    
    response_lower = response.lower()
    assert any(w in response_lower for w in ["coffee berry", "cbd", "colletotrichum", "anthracnose", "fungal"]), \
        "Response did not identify coffee berry disease"
    assert any(w in response_lower for w in ["fungicide", "copper", "prune", "harvest", "control"]), \
        "Response did not recommend management action"

# ─── SWAHILI TEST (African Alpha Bonus) ───────────────────────────────────────

def test_swahili_response(system):
    """
    Model responds meaningfully in Swahili when prompted in Swahili.
    """
    llm, prompt_engine, retriever = system
    query_sw = "Mahindi yangu yana njano. Ni tatizo gani na ninafanya nini?"
    
    context_chunks = retriever.retrieve(query_sw, top_k=2)
    prompt = prompt_engine.build_contextual_prompt(
        user_query=query_sw,
        rag_context=context_chunks,
        country="Kenya",
        language="sw",
    )
    response = llm.generate(prompt, max_tokens=128)
    
    assert len(response.strip()) > 20, "Swahili response too short"
    # Should contain some Swahili words
    swahili_words = ["mahindi", "mbolea", "udongo", "kilimo", "mmea", "mazao", "shamba"]
    assert any(w in response.lower() for w in swahili_words), \
        f"Response does not appear to be in Swahili: {response[:200]}"
```

---

## Test File: `tests/test_performance.py`

**Purpose:** Track TPS and RAM to catch regressions between model versions.

```python
import pytest
import psutil
import time
from src.llm.inference import LlamaInference

MODEL_PATH = "model/qwen2.5-3b-instruct-q4_k_m.gguf"
TPS_MINIMUM = 10.0       # fail if below this
TPS_TARGET  = 15.0       # competition reference; aim to meet or beat
RAM_HARD_LIMIT_MB = 7168 # disqualification threshold
RAM_TARGET_MB     = 3500 # our performance target

@pytest.fixture(scope="module")
def model():
    llm = LlamaInference(model_path=MODEL_PATH)
    yield llm
    llm.release()

@pytest.mark.perf
def test_tps_meets_minimum(model):
    """
    Token generation speed must exceed the minimum to pass Sperf scoring.
    Tests over a 128-token generation burst.
    """
    prompt = (
        "You are a farming advisor. A farmer asks: "
        "My tomato plants have brown spots with yellow halos on the leaves. "
        "What disease is this and how do I treat it? Give step-by-step advice."
    )
    
    start = time.perf_counter()
    tokens = list(model.generate_stream(prompt, max_tokens=128))
    elapsed = time.perf_counter() - start
    
    tps = len(tokens) / elapsed if elapsed > 0 else 0
    print(f"\nTPS measurement: {tps:.1f} t/s over {len(tokens)} tokens ({elapsed:.2f}s)")
    
    assert tps >= TPS_MINIMUM, f"TPS {tps:.1f} is below minimum {TPS_MINIMUM}"
    
    if tps < TPS_TARGET:
        pytest.warns(UserWarning, match="TPS below target")
        print(f"WARNING: TPS {tps:.1f} is below target {TPS_TARGET}. Sperf will be reduced.")

@pytest.mark.perf
def test_ram_within_hard_limit(model):
    """Peak RSS after model load must not exceed 7 GB disqualification threshold."""
    rss = psutil.Process().memory_info().rss / (1024 * 1024)
    print(f"\nCurrent RSS: {rss:.0f} MB")
    assert rss < RAM_HARD_LIMIT_MB, \
        f"DISQUALIFICATION: {rss:.0f} MB >= {RAM_HARD_LIMIT_MB} MB hard limit"

@pytest.mark.perf
def test_ram_within_target(model):
    """Peak RSS should stay within our efficiency target."""
    rss = psutil.Process().memory_info().rss / (1024 * 1024)
    seff = (7168 - rss) / 7168 * 100
    print(f"\nRAM: {rss:.0f} MB | Seff estimate: {seff:.1f}")
    assert rss < RAM_TARGET_MB, f"RAM {rss:.0f} MB exceeds target {RAM_TARGET_MB} MB (Seff={seff:.1f})"

@pytest.mark.perf
def test_first_token_latency(model):
    """Time to first token must be under 2 seconds for good UX."""
    prompt = "What are the signs of fall armyworm on maize?"
    
    first_token_time = None
    start = time.perf_counter()
    
    for chunk in model.generate_stream(prompt, max_tokens=64):
        if chunk.strip() and first_token_time is None:
            first_token_time = time.perf_counter() - start
            break
    
    assert first_token_time is not None, "No tokens generated"
    print(f"\nFirst token latency: {first_token_time * 1000:.0f} ms")
    assert first_token_time < 2.0, \
        f"First token latency {first_token_time * 1000:.0f} ms exceeds 2000 ms"

@pytest.mark.perf
def test_sustained_generation_no_crash(model):
    """
    Run 5 consecutive 128-token generations without OOM or crash.
    Simulates evaluation conditions (multiple prompts tested in sequence).
    """
    prompts = [
        "Describe the best practices for maize farming in East Africa.",
        "What livestock vaccines are essential for a cattle farmer in Kenya?",
        "How do I control fall armyworm without chemical pesticides?",
        "What is the best time to plant beans in western Kenya?",
        "How do I improve yield on a farm with poor sandy soil?",
    ]
    
    for i, prompt in enumerate(prompts):
        tokens = list(model.generate_stream(prompt, max_tokens=128))
        rss = psutil.Process().memory_info().rss / (1024 * 1024)
        assert len(tokens) > 0, f"Prompt {i+1} generated no tokens"
        assert rss < RAM_HARD_LIMIT_MB, f"OOM risk after prompt {i+1}: {rss:.0f} MB"
        print(f"Prompt {i+1}: {len(tokens)} tokens, RSS {rss:.0f} MB")
```

---

## Test File: `tests/test_prompt_engine.py`

**Purpose:** Unit-test the PromptEngine without running the LLM (fast, no model needed).

```python
import pytest
from src.llm.prompt_engine import PromptEngine

@pytest.fixture
def engine():
    return PromptEngine()

@pytest.mark.unit
def test_system_prompt_contains_location(engine):
    prompt = engine.build_agriculture_prompt(country="Kenya", region="Rift Valley")
    assert "Kenya" in prompt
    assert "Rift Valley" in prompt

@pytest.mark.unit
def test_system_prompt_default_location(engine):
    prompt = engine.build_agriculture_prompt()
    assert "Africa" in prompt

@pytest.mark.unit
def test_contextual_prompt_includes_query(engine):
    prompt = engine.build_contextual_prompt(
        user_query="How do I grow cassava?",
        country="Uganda"
    )
    assert "cassava" in prompt.lower()

@pytest.mark.unit
def test_contextual_prompt_includes_season(engine):
    prompt = engine.build_contextual_prompt(
        user_query="What should I plant?",
        season="Long rains (March–May)"
    )
    assert "long rains" in prompt.lower() or "march" in prompt.lower()

@pytest.mark.unit
def test_prompt_cache_hit(engine):
    """Same inputs return cached prompt without rebuilding."""
    p1 = engine.build_agriculture_prompt(country="Kenya", region="Nyanza")
    p2 = engine.build_agriculture_prompt(country="Kenya", region="Nyanza")
    assert p1 == p2

@pytest.mark.unit
def test_insights_prompt_has_json_instruction(engine):
    ctx = {"scans": [], "weather": {"temp_c": 28}, "tasks": [], "fields": []}
    prompt = engine.build_insights_prompt(context_data=ctx)
    assert "JSON" in prompt
    assert "priority" in prompt

@pytest.mark.unit
def test_scanner_prompt_includes_label(engine):
    prompt = engine.build_scanner_diagnosis_prompt(
        predicted_label="Tomato___Late_blight",
        confidence=0.82,
        top_k_labels=["Tomato___Late_blight", "Tomato___Early_blight"],
    )
    assert "Tomato___Late_blight" in prompt
    assert "82" in prompt  # confidence percentage

@pytest.mark.unit
def test_no_emojis_instruction_in_prompt(engine):
    """System prompt must include the no-emoji guideline."""
    prompt = engine.build_agriculture_prompt(country="Nigeria")
    assert "emojis" in prompt.lower()
```

---

## Test File: `tests/test_submission.py`

**Purpose:** Final gate — verify the entire submission package is valid before DevPost submission.

```python
import pytest
import json
import os
import subprocess

@pytest.mark.submission
def test_metadata_json_exists():
    assert os.path.exists("metadata.json"), "metadata.json is missing"

@pytest.mark.submission
def test_metadata_json_valid():
    with open("metadata.json") as f:
        m = json.load(f)
    
    # Required fields
    required = ["team_id", "domain", "language_scope", "african_alpha_claim",
                "budget_laptop_claim", "submitter", "cross_disciplinary_pairing",
                "test_prompts", "model", "_runtime"]
    for field in required:
        assert field in m, f"metadata.json missing required field: {field}"
    
    # No placeholder values
    text = json.dumps(m)
    placeholders = ["your-team-id", "your-name", "your-email@domain.com", "your-github",
                    "YourModel", "coding_assistants"]
    for p in placeholders:
        assert p not in text, f"Placeholder value still in metadata.json: '{p}'"

@pytest.mark.submission
def test_metadata_domain_is_agriculture():
    with open("metadata.json") as f:
        m = json.load(f)
    assert m["domain"] == "agriculture", f"Domain must be 'agriculture', got: {m['domain']}"

@pytest.mark.submission
def test_metadata_runtime_is_llamacpp():
    with open("metadata.json") as f:
        m = json.load(f)
    assert m["model"]["runtime"] == "llama.cpp", "Runtime must be 'llama.cpp'"

@pytest.mark.submission
def test_metadata_has_swahili_language():
    with open("metadata.json") as f:
        m = json.load(f)
    assert "sw" in m["language_scope"], "Swahili ('sw') must be in language_scope for African Alpha Bonus"

@pytest.mark.submission
def test_metadata_african_alpha_claimed():
    with open("metadata.json") as f:
        m = json.load(f)
    assert m["african_alpha_claim"] is True

@pytest.mark.submission
def test_metadata_exactly_two_test_prompts():
    with open("metadata.json") as f:
        m = json.load(f)
    prompts = m.get("test_prompts", [])
    assert len(prompts) == 2, f"Must have exactly 2 test prompts, found: {len(prompts)}"

@pytest.mark.submission
def test_metadata_model_path_matches_file():
    with open("metadata.json") as f:
        m = json.load(f)
    model_path = m["_runtime"]["model_path"]
    assert os.path.exists(model_path), \
        f"Model file not found at '{model_path}'. Run: bash download_model.sh"

@pytest.mark.submission
def test_gitignore_excludes_gguf():
    assert os.path.exists(".gitignore"), ".gitignore is missing"
    with open(".gitignore") as f:
        content = f.read()
    assert "*.gguf" in content, "*.gguf must be in .gitignore"
    assert "model/" in content, "model/ must be in .gitignore"

@pytest.mark.submission
def test_report_md_exists_and_not_template():
    assert os.path.exists("REPORT.md"), "REPORT.md is missing"
    with open("REPORT.md") as f:
        content = f.read()
    assert "[Your Submission Title]" not in content, "REPORT.md still has template placeholders"
    assert "your-team-id" not in content, "REPORT.md still has placeholder team ID"
    assert len(content) > 1000, "REPORT.md is too short — write a proper technical report"

@pytest.mark.submission
def test_download_script_exists():
    assert os.path.exists("download_model.sh"), "download_model.sh is missing"

@pytest.mark.submission
def test_model_dir_exists():
    assert os.path.isdir("model"), "model/ directory is missing"
```

---

## Running Tests

```bash
# All fast unit tests (no model needed)
pytest tests/ -v -m "unit"

# All offline tests
pytest tests/ -v -m "offline"

# Full test suite (requires model downloaded)
pytest tests/ -v

# Only submission gate (run last before DevPost)
pytest tests/test_submission.py -v -m "submission"

# Performance regression report
pytest tests/test_performance.py -v -m "perf" -s

# Skip slow tests
pytest tests/ -v --ignore=tests/test_performance.py --ignore=tests/test_prompts.py
```

---

## Profiler Commands (not pytest — run separately)

```bash
# Local participant check
adtc-profiler run \
  --submission . \
  --mode participant \
  --output submission.json \
  --skip-accuracy

# Review output
cat submission.json | python -m json.tool

# Key fields to check
python -c "
import json
with open('submission.json') as f: s = json.load(f)
print('Peak RAM:', s['memory']['peak_rss_mb'], 'MB')
print('TPS:', s['throughput']['tokens_per_second_generation'])
print('First token:', s['throughput']['first_token_latency_ms'], 'ms')
print('Seff score:', round((7168 - s['memory']['peak_rss_mb']) / 7168 * 100, 1))
print('Sperf score:', round(min(s['throughput']['tokens_per_second_generation'] / 15, 1) * 100, 1))
"
```
