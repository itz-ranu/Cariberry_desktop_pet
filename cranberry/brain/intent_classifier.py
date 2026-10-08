"""A small, from-scratch intent classifier.

Command parsing ("open WhatsApp" -> actually click WhatsApp's icon) has to
be reliable, since a wrong read triggers a real mouse click. A few-hundred-
parameter mean-pooled embedding classifier trained on thousands of templated
examples is far more dependable for this than trusting a tiny generative
model to free-form its way to the right action — so intent detection and
persona chit-chat are deliberately split into two small models here.
"""

from __future__ import annotations

import torch
from torch import nn

from .. import config
from .tokenizer import Tokenizer, basic_tokenize
from .dataset_gen import INTENTS


class IntentClassifier(nn.Module):
    def __init__(self, vocab_size: int, d_model: int = 64, n_intents: int = len(INTENTS)):
        super().__init__()
        self.embedding = nn.Embedding(vocab_size, d_model, padding_idx=0)
        self.classifier = nn.Sequential(
            nn.Linear(d_model, d_model),
            nn.ReLU(inplace=True),
            nn.Dropout(0.1),
            nn.Linear(d_model, n_intents),
        )

    def forward(self, tokens: torch.Tensor, pad_id: int) -> torch.Tensor:
        mask = (tokens != pad_id).float().unsqueeze(-1)  # (batch, seq, 1)
        embedded = self.embedding(tokens) * mask
        pooled = embedded.sum(dim=1) / mask.sum(dim=1).clamp(min=1)
        return self.classifier(pooled)

    @torch.no_grad()
    def predict(self, text: str, tokenizer: Tokenizer) -> str:
        self.eval()
        ids = tokenizer.encode(text, add_special=False) or [tokenizer.token_to_id["<unk>"]]
        tokens = torch.tensor([ids])
        logits = self.forward(tokens, tokenizer.pad_id)
        return INTENTS[int(logits.argmax(dim=-1).item())]


# Re-exported so existing imports keep working: they now live in slots.py (no torch needed).
from .slots import (  # noqa: E402,F401
    _best_fuzzy_match,
    _match_web_app,
    extract_app_slot,
    resolve_open_target,
)
