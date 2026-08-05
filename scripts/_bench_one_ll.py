#!/usr/bin/env python3
"""Time one llama-cpp-python echo-logprobs call on /tmp GGUF."""
import time
from llama_cpp import Llama

path = "/tmp/maathai-model/qwen2.5-3b-instruct-q4_k_m.gguf"
t0 = time.time()
m = Llama(model_path=path, n_ctx=512, n_threads=4, logits_all=True, verbose=False)
print(f"load_s={time.time()-t0:.1f}")

ctx = "Question: What is 2+2?\nAnswer:"
cont = " 4"
t1 = time.time()
out = m(ctx + cont, max_tokens=0, echo=True, logprobs=5, temperature=0.0)
lp = out["choices"][0]["logprobs"]
print(f"ll_s={time.time()-t1:.1f} tokens={len(lp['tokens'])}")
