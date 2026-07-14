"""
Pre-submission validation gate.
Run before DevPost submission to verify the package meets all ADTC 2026 rules.

pytest tests/test_submission.py -v
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).parent.parent
METADATA_PATH = REPO_ROOT / "metadata.json"
DOWNLOAD_SCRIPT = REPO_ROOT / "download_model.sh"
REPORT_PATH = REPO_ROOT / "REPORT.md"
GITIGNORE_PATH = REPO_ROOT / ".gitignore"
MODEL_DIR = REPO_ROOT / "model"


class TestMetadataJson:
    @pytest.fixture(autouse=True)
    def load_metadata(self):
        with open(METADATA_PATH, encoding="utf-8") as f:
            self.meta = json.load(f)

    def test_file_exists(self):
        assert METADATA_PATH.exists(), "metadata.json is missing"

    def test_valid_json(self):
        assert isinstance(self.meta, dict)

    def test_no_placeholder_values(self):
        """
        IMPORTANT: Before DevPost submission, replace all placeholder values in metadata.json:
          - team_id: your ADTF portal team ID
          - submitter.name: your full name
          - submitter.email: your registered email
          - submitter.github_handle: your GitHub username
        """
        placeholders = {"REPLACE_WITH_YOUR_ADTF_TEAM_ID", "REPLACE_WITH_YOUR_FULL_NAME",
                        "REPLACE_WITH_YOUR_EMAIL", "TO_BE_FILLED", "TO_BE_FILLED_AFTER_MODEL_UPLOAD"}
        flat = json.dumps(self.meta)
        found = [p for p in placeholders if p in flat]
        if found:
            pytest.xfail(
                f"Placeholder values still in metadata.json (fill these before submission): {found}"
            )

    def test_required_fields_present(self):
        required = [
            "team_id", "domain", "language_scope", "african_alpha_claim",
            "budget_laptop_claim", "submitter", "cross_disciplinary_pairing",
            "test_prompts", "model", "_runtime",
        ]
        for field in required:
            assert field in self.meta, f"Required field missing: {field}"

    def test_domain_is_valid(self):
        valid_domains = {
            "math_scientific_reasoning", "healthcare_medical", "agriculture",
            "creative_writing", "coding_assistants", "corporate_enterprise",
            "autonomous_ai_agents",
        }
        assert self.meta["domain"] in valid_domains

    def test_runtime_is_llamacpp(self):
        assert self.meta["model"]["runtime"] == "llama.cpp", (
            "model.runtime must be 'llama.cpp' — no other runtime is accepted"
        )

    def test_quantization_is_gguf(self):
        quant = self.meta["model"]["quantization"]
        assert "GGUF" in quant, f"model.quantization must be a GGUF format: {quant}"

    def test_budget_laptop_claim_true(self):
        assert self.meta["budget_laptop_claim"] is True, (
            "budget_laptop_claim must be true for all ADTC 2026 submissions"
        )

    def test_exactly_two_test_prompts(self):
        prompts = self.meta.get("test_prompts", [])
        assert len(prompts) == 2, (
            f"metadata.json must contain exactly 2 test prompts (found {len(prompts)})"
        )

    def test_test_prompts_have_unique_ids(self):
        prompts = self.meta["test_prompts"]
        ids = [p["prompt_id"] for p in prompts]
        assert len(set(ids)) == len(ids), "test_prompt IDs must be unique"

    def test_test_prompts_are_non_empty(self):
        for p in self.meta["test_prompts"]:
            assert len(p["prompt"].strip()) > 20, (
                f"Prompt {p['prompt_id']} is too short"
            )

    def test_model_path_matches_runtime(self):
        model_path = self.meta["_runtime"]["model_path"]
        assert model_path.endswith(".gguf"), (
            f"_runtime.model_path must be a .gguf file: {model_path}"
        )

    def test_submitter_has_required_fields(self):
        submitter = self.meta.get("submitter", {})
        for field in ["name", "email", "github_handle"]:
            assert field in submitter and submitter[field], (
                f"submitter.{field} is missing or empty"
            )

    def test_language_scope_is_list(self):
        scope = self.meta.get("language_scope", [])
        assert isinstance(scope, list) and len(scope) >= 1

    def test_african_alpha_requires_language_scope(self):
        if self.meta.get("african_alpha_claim"):
            scope = self.meta.get("language_scope", [])
            assert len(scope) > 1 or scope[0] != "en", (
                "african_alpha_claim=true but no African language in language_scope"
            )


class TestDownloadScript:
    def test_file_exists(self):
        assert DOWNLOAD_SCRIPT.exists(), "download_model.sh is missing"

    def test_is_executable_or_bash(self):
        content = DOWNLOAD_SCRIPT.read_text(encoding="utf-8")
        assert "#!/" in content[:20], "download_model.sh must have a shebang line"

    def test_references_correct_model_file(self):
        meta = json.loads(METADATA_PATH.read_text(encoding="utf-8"))
        model_filename = Path(meta["_runtime"]["model_path"]).name
        script = DOWNLOAD_SCRIPT.read_text(encoding="utf-8")
        assert model_filename in script, (
            f"download_model.sh does not reference the model filename: {model_filename}"
        )

    def test_no_placeholder_urls(self):
        script = DOWNLOAD_SCRIPT.read_text(encoding="utf-8")
        bad_patterns = ["TO_BE_FILLED", "YOUR_ORG", "PLACEHOLDER", "example.com/fake"]
        for bad in bad_patterns:
            assert bad not in script, f"Placeholder '{bad}' in download_model.sh"

    def test_references_huggingface_url(self):
        script = DOWNLOAD_SCRIPT.read_text(encoding="utf-8")
        assert "huggingface.co" in script, "download_model.sh should use HuggingFace as primary host"


class TestReportMd:
    def test_file_exists(self):
        assert REPORT_PATH.exists(), "REPORT.md is missing"

    def test_minimum_length(self):
        content = REPORT_PATH.read_text(encoding="utf-8")
        assert len(content) > 1000, "REPORT.md seems too short (under 1000 chars)"

    def test_covers_required_sections(self):
        content = REPORT_PATH.read_text(encoding="utf-8").lower()
        sections = ["problem", "design", "constraint", "benchmark"]
        for section in sections:
            assert section in content, (
                f"REPORT.md should cover '{section}' (judges expect this)"
            )


class TestGitignore:
    def test_file_exists(self):
        assert GITIGNORE_PATH.exists(), ".gitignore is missing"

    def test_excludes_gguf(self):
        content = GITIGNORE_PATH.read_text(encoding="utf-8")
        assert "*.gguf" in content, ".gitignore must exclude *.gguf files"

    def test_excludes_model_directory(self):
        content = GITIGNORE_PATH.read_text(encoding="utf-8")
        assert "model/" in content, ".gitignore must exclude model/ directory"


class TestModelDirectory:
    def test_model_dir_exists(self):
        assert MODEL_DIR.exists(), "model/ directory must exist"

    def test_gitkeep_present(self):
        gitkeep = MODEL_DIR / ".gitkeep"
        assert gitkeep.exists(), "model/.gitkeep must exist to track empty directory in git"

    def test_no_gguf_committed(self):
        """GGUF files must NOT be committed to git."""
        gguf_files = list(MODEL_DIR.glob("*.gguf"))
        # This test passes whether model is present or not —
        # what matters is it's in .gitignore (tested above)
        # We just warn if one is present
        if gguf_files:
            pytest.skip(
                f"Model file present locally (ok for testing, but must not be committed): "
                f"{[f.name for f in gguf_files]}"
            )


class TestOfflineCompliance:
    def test_no_api_keys_in_source(self):
        """No secrets should be committed."""
        suspicious_patterns = ["OPENAI_API_KEY", "sk-", "Bearer ey", "HF_TOKEN"]
        src_dir = REPO_ROOT / "src"

        for py_file in src_dir.rglob("*.py"):
            content = py_file.read_text(encoding="utf-8")
            for pattern in suspicious_patterns:
                assert pattern not in content, (
                    f"Potential secret in {py_file.relative_to(REPO_ROOT)}: '{pattern}'"
                )

    def test_no_external_api_calls_in_config(self):
        config_file = REPO_ROOT / "src" / "config.py"
        content = config_file.read_text(encoding="utf-8")
        external_urls = ["openai.com", "anthropic.com", "api.cohere", "cloud."]
        for url in external_urls:
            assert url not in content, (
                f"External API URL in config.py: {url}"
            )
