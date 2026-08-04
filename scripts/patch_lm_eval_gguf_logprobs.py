#!/usr/bin/env python3
"""Patch lm_eval.models.gguf to accept llama.cpp's modern OpenAI logprobs shape."""
from __future__ import annotations

import sys
from pathlib import Path

MARKER = "MAATHAI_LOGPROBS_COMPAT"

HELPER = '''
def _maathai_normalize_logprobs(logprobs):
    """Normalize llama.cpp OpenAI logprobs into the legacy shape lm_eval expects."""
    if not logprobs or "token_logprobs" in logprobs:
        return logprobs
    content = logprobs.get("content")
    if not content:
        return logprobs
    tokens = []
    token_logprobs = []
    text_offset = []
    top_logprobs = []
    pos = 0
    for item in content:
        tok = item.get("token") or ""
        tokens.append(tok)
        token_logprobs.append(item.get("logprob"))
        text_offset.append(pos)
        pos += len(tok)
        tops = {}
        for t in item.get("top_logprobs") or []:
            if "token" in t and "logprob" in t:
                tops[t["token"]] = t["logprob"]
        top_logprobs.append(tops)
    return {
        "tokens": tokens,
        "token_logprobs": token_logprobs,
        "text_offset": text_offset,
        "top_logprobs": top_logprobs,
    }
'''

LOGLIKELIHOOD_BLOCK = '''    def loglikelihood(self, requests, disable_tqdm: bool = False):
        if not requests:
            return []
        res = []
        for context, continuation in tqdm(
            [req.args for req in requests], disable=disable_tqdm
        ):
            response = self.gguf_completion(context=context, continuation=continuation)
            if response and "choices" in response and response["choices"]:
                choice = response["choices"][0]
                logprobs = _maathai_normalize_logprobs(choice.get("logprobs"))
                if (
                    logprobs
                    and "token_logprobs" in logprobs
                    and logprobs["token_logprobs"]
                ):
                    logprob, is_greedy = get_result(logprobs, len(context))
                    res.append((logprob, is_greedy))
                else:
                    logger.warning(
                        "Invalid logprobs data after normalize. keys=%s",
                        list(logprobs.keys()) if isinstance(logprobs, dict) else type(logprobs),
                    )
            else:
                logger.error(
                    f"Invalid response for loglikelihood. Response: {response}"
                )
                assert False
        return res
'''


def main() -> int:
    try:
        import lm_eval.models.gguf as gguf
    except ImportError as exc:
        print(f"FAIL: cannot import lm_eval.models.gguf: {exc}")
        return 1

    path = Path(gguf.__file__)
    text = path.read_text(encoding="utf-8")

    # Always rewrite loglikelihood to the correct order (normalize then check)
    import re

    text2, n = re.subn(
        r"    def loglikelihood\(self, requests, disable_tqdm: bool = False\):.*?"
        r"        return res\n",
        LOGLIKELIHOOD_BLOCK + "\n",
        text,
        count=1,
        flags=re.S,
    )
    if n != 1:
        print("FAIL: could not rewrite loglikelihood()")
        return 1
    text = text2

    if MARKER not in text:
        if "def get_result(logprobs, context_length):" not in text:
            print("FAIL: get_result missing")
            return 1
        text = text.replace(
            "def get_result(logprobs, context_length):",
            f"# {MARKER}\n{HELPER}\ndef get_result(logprobs, context_length):",
            1,
        )
    elif "_maathai_normalize_logprobs" not in text:
        text = text.replace(
            "def get_result(logprobs, context_length):",
            f"{HELPER}\ndef get_result(logprobs, context_length):",
            1,
        )

    path.write_text(text, encoding="utf-8")
    # clear pycache
    for pyc in path.parent.glob("__pycache__/gguf*.pyc"):
        pyc.unlink(missing_ok=True)
    print(f"✓ patched {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
