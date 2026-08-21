"""lm_eval model backed by llama-cpp-python (legacy echo logprobs)."""
from __future__ import annotations

import os
import sys
from pathlib import Path
from typing import Any

from lm_eval.api.instance import Instance
from lm_eval.api.model import LM
from lm_eval.api.registry import register_model
from tqdm import tqdm


def _ensure_ggml_backends() -> None:
    """llama-cpp-python needs site-packages/lib on LD_LIBRARY_PATH or load fails."""
    for lib_dir in Path(sys.prefix).glob("lib/python*/site-packages/lib"):
        if not (lib_dir / "libggml-cpu.so.0").exists() and not (lib_dir / "libggml-cpu.so").exists():
            continue
        os.environ["GGML_BACKEND_DIR"] = str(lib_dir)
        existing = os.environ.get("LD_LIBRARY_PATH", "")
        prefix = str(lib_dir)
        if prefix not in existing.split(os.pathsep):
            os.environ["LD_LIBRARY_PATH"] = (
                prefix if not existing else f"{prefix}{os.pathsep}{existing}"
            )
        return


_ensure_ggml_backends()


def _get_result(logprobs: dict, context_length: int):
    is_greedy = True
    offsets = logprobs["text_offset"]
    tokens = logprobs["tokens"]
    tokens_logprobs = logprobs["token_logprobs"]

    idx = 0
    while idx < len(offsets) and offsets[idx] < context_length:
        idx += 1
    if idx >= len(tokens_logprobs):
        return 0.0, False

    # Sum continuation token logprobs (exclude trailing None / generated pad)
    vals = []
    for lp in tokens_logprobs[idx:]:
        if lp is None:
            continue
        vals.append(float(lp))
    continuation_logprobs = sum(vals)

    for i in range(idx, len(tokens)):
        token = tokens[i]
        top_tokens = logprobs["top_logprobs"][i]
        if not top_tokens:
            continue
        top_token = max(top_tokens.keys(), key=lambda x: top_tokens[x])
        if top_token != token:
            is_greedy = False
            break
    return continuation_logprobs, is_greedy


@register_model("maathai_llama_cpp")
class MaathaiLlamaCpp(LM):
    def __init__(
        self,
        model_path: str | None = None,
        pretrained: str | None = None,
        n_ctx: int = 512,
        n_threads: int = 4,
        n_gpu_layers: int = 0,
        **kwargs: Any,
    ) -> None:
        super().__init__()
        _ensure_ggml_backends()
        from llama_cpp import Llama

        # lm_eval may pass pretrained= / model_path=; strip accidental nesting
        path = model_path or pretrained or kwargs.get("pretrained") or ""
        for _ in range(4):
            if path.startswith("pretrained="):
                path = path.split("=", 1)[1]
            elif path.startswith("model_path="):
                path = path.split("=", 1)[1]
            else:
                break
        # If lm_eval stuffed the whole argstring into pretrained, keep only the path
        if "," in path and ("n_ctx=" in path or path.count("=") >= 1):
            # e.g. "/tmp/foo.gguf,n_ctx=512,..." or "model_path=/tmp/foo,n_ctx=..."
            first = path.split(",", 1)[0]
            if first.startswith("model_path="):
                first = first.split("=", 1)[1]
            path = first
        print(f"[maathai_llama_cpp] loading {path} n_ctx={n_ctx} threads={n_threads}", flush=True)
        self.model = Llama(
            model_path=path,
            n_ctx=int(n_ctx),
            n_threads=int(n_threads),
            n_gpu_layers=int(n_gpu_layers),
            logits_all=True,
            verbose=False,
        )
        self._max_length = int(n_ctx)

    @property
    def eot_token_id(self):
        return self.model.token_eos()

    @property
    def max_length(self) -> int:
        return self._max_length

    @property
    def max_gen_toks(self) -> int:
        return 256

    @property
    def batch_size(self) -> int:
        return 1

    @property
    def device(self) -> str:
        return "cpu"

    def tok_encode(self, string: str, **kwargs):
        return self.model.tokenize(string.encode("utf-8"), add_bos=False)

    def tok_decode(self, tokens, **kwargs) -> str:
        return self.model.detokenize(list(tokens)).decode("utf-8", errors="replace")

    def loglikelihood(self, requests, disable_tqdm: bool = False):
        res = []
        for context, continuation in tqdm(
            [req.args for req in requests], disable=disable_tqdm
        ):
            prompt = context + continuation
            out = self.model(
                prompt,
                max_tokens=0,
                echo=True,
                logprobs=5,
                temperature=0.0,
            )
            choice = out["choices"][0]
            logprobs = choice.get("logprobs")
            if not logprobs or "token_logprobs" not in logprobs:
                res.append((0.0, False))
                continue
            logprob, is_greedy = _get_result(logprobs, len(context))
            res.append((logprob, is_greedy))
        return res

    def generate_until(self, requests, disable_tqdm: bool = False):
        res = []
        for req in tqdm(requests, disable=disable_tqdm):
            context, gen_kwargs = req.args
            until = gen_kwargs.get("until") or []
            max_gen = int(gen_kwargs.get("max_gen_toks", self.max_gen_toks))
            out = self.model(
                context,
                max_tokens=max_gen,
                temperature=0.0,
                stop=until or None,
            )
            res.append(out["choices"][0]["text"])
        return res

    def loglikelihood_rolling(self, requests, disable_tqdm: bool = False):
        raise NotImplementedError
