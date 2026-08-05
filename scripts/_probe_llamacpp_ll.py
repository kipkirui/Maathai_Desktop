#!/usr/bin/env python3
from llama_cpp import Llama

m = Llama(
    model_path="model/qwen2.5-3b-instruct-q4_k_m.gguf",
    n_ctx=512,
    n_threads=4,
    logits_all=True,
    verbose=False,
)
context = "Question: What is 2+2?\nAnswer:"
continuation = " 4"
prompt = context + continuation
out = m(
    prompt,
    max_tokens=0,
    echo=True,
    logprobs=5,
    temperature=0.0,
)
choice = out["choices"][0]
lp = choice.get("logprobs")
print("keys", choice.keys())
print("logprobs type/keys", type(lp), list(lp.keys()) if isinstance(lp, dict) else None)
if isinstance(lp, dict):
    for k, v in lp.items():
        if isinstance(v, list):
            print(k, "len", len(v), "sample", v[:3])
        else:
            print(k, v)
print("text len", len(choice.get("text") or ""))
