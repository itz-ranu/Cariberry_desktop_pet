"""TinyGPT: a small decoder-only transformer, written from scratch.

No pretrained weights are loaded anywhere in this file or anywhere in this
service — every parameter starts randomly initialized and is only ever
shaped by training on cranberry/brain/dataset_gen.py's synthetic corpus (see
train.py). It's intentionally small (a few hundred thousand parameters):
big enough to learn Cranberry's narrow vocabulary and tone, not a
general-knowledge model.
"""

from __future__ import annotations

import math

import torch
import torch.nn.functional as F
from torch import nn


class CausalSelfAttention(nn.Module):
    def __init__(self, d_model: int, n_heads: int, max_len: int, dropout: float = 0.1):
        super().__init__()
        assert d_model % n_heads == 0
        self.n_heads = n_heads
        self.head_dim = d_model // n_heads

        self.qkv = nn.Linear(d_model, 3 * d_model)
        self.out_proj = nn.Linear(d_model, d_model)
        self.dropout = nn.Dropout(dropout)

        causal_mask = torch.tril(torch.ones(max_len, max_len)).bool()
        self.register_buffer("causal_mask", causal_mask, persistent=False)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        batch, seq_len, d_model = x.shape
        qkv = self.qkv(x).view(batch, seq_len, 3, self.n_heads, self.head_dim)
        q, k, v = qkv.permute(2, 0, 3, 1, 4)  # each: (batch, n_heads, seq_len, head_dim)

        scores = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        mask = self.causal_mask[:seq_len, :seq_len]
        scores = scores.masked_fill(~mask, float("-inf"))
        attn = F.softmax(scores, dim=-1)
        attn = self.dropout(attn)

        out = attn @ v  # (batch, n_heads, seq_len, head_dim)
        out = out.transpose(1, 2).reshape(batch, seq_len, d_model)
        return self.out_proj(out)


class MLP(nn.Module):
    def __init__(self, d_model: int, dropout: float = 0.1):
        super().__init__()
        self.net = nn.Sequential(
            nn.Linear(d_model, 4 * d_model),
            nn.GELU(),
            nn.Linear(4 * d_model, d_model),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        return self.net(x)


class Block(nn.Module):
    def __init__(self, d_model: int, n_heads: int, max_len: int, dropout: float = 0.1):
        super().__init__()
        self.ln1 = nn.LayerNorm(d_model)
        self.attn = CausalSelfAttention(d_model, n_heads, max_len, dropout)
        self.ln2 = nn.LayerNorm(d_model)
        self.mlp = MLP(d_model, dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = x + self.attn(self.ln1(x))
        x = x + self.mlp(self.ln2(x))
        return x


class TinyGPT(nn.Module):
    def __init__(
        self,
        vocab_size: int,
        d_model: int = 128,
        n_heads: int = 4,
        n_layers: int = 4,
        max_len: int = 64,
        dropout: float = 0.1,
    ):
        super().__init__()
        self.max_len = max_len
        self.token_embedding = nn.Embedding(vocab_size, d_model)
        self.position_embedding = nn.Embedding(max_len, d_model)
        self.blocks = nn.ModuleList([Block(d_model, n_heads, max_len, dropout) for _ in range(n_layers)])
        self.ln_final = nn.LayerNorm(d_model)
        self.head = nn.Linear(d_model, vocab_size, bias=False)
        self.head.weight = self.token_embedding.weight  # weight tying

    def forward(self, tokens: torch.Tensor) -> torch.Tensor:
        batch, seq_len = tokens.shape
        positions = torch.arange(seq_len, device=tokens.device).unsqueeze(0)
        x = self.token_embedding(tokens) + self.position_embedding(positions)
        for block in self.blocks:
            x = block(x)
        x = self.ln_final(x)
        return self.head(x)

    @torch.no_grad()
    def generate(
        self,
        prompt_ids: list[int],
        eos_id: int,
        max_new_tokens: int = 24,
        temperature: float = 0.8,
        top_k: int = 20,
        repetition_penalty: float = 1.5,
        no_repeat_last_n: int = 2,
    ) -> list[int]:
        """Samples a continuation. `repetition_penalty` down-weights tokens
        already generated (divides their logit), and `no_repeat_last_n` bans
        outright repeating whatever token appeared in the last N steps — a
        small model trained on a small corpus left unchecked tends to fall
        into "closing closing closing closing" loops, and this is a much
        cheaper fix than making the model bigger or the dataset huge."""
        self.eval()
        ids = list(prompt_ids)
        generated: list[int] = []
        for _ in range(max_new_tokens):
            window = ids[-self.max_len:]
            logits = self.forward(torch.tensor([window]))[0, -1]
            for token_id in set(generated):
                logits[token_id] /= repetition_penalty
            for token_id in generated[-no_repeat_last_n:]:
                logits[token_id] = float("-inf")
            logits = logits / max(temperature, 1e-5)
            if top_k:
                top_values, top_indices = torch.topk(logits, min(top_k, logits.size(-1)))
                probs = torch.zeros_like(logits).scatter_(0, top_indices, F.softmax(top_values, dim=-1))
            else:
                probs = F.softmax(logits, dim=-1)
            next_id = int(torch.multinomial(probs, num_samples=1).item())
            ids.append(next_id)
            generated.append(next_id)
            if next_id == eos_id:
                break
        return ids[len(prompt_ids):]
