"""A small from-scratch keyword-spotting CNN for "Hey Cranberry".

Architecture: this is the same family of model as classic small-footprint
keyword spotters (a handful of conv blocks over a log-mel spectrogram,
global-pooled into a binary classifier) — original code, trained from
scratch on samples you record yourself in `collect_samples.py`. There is no
pretrained checkpoint anywhere in this repo; the weights only exist once you
train them.
"""

from __future__ import annotations

import torch
from torch import nn


class WakeWordCNN(nn.Module):
    def __init__(self, n_mels: int = 40):
        super().__init__()
        self.features = nn.Sequential(
            nn.Conv2d(1, 16, kernel_size=3, padding=1),
            nn.BatchNorm2d(16),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),

            nn.Conv2d(16, 32, kernel_size=3, padding=1),
            nn.BatchNorm2d(32),
            nn.ReLU(inplace=True),
            nn.MaxPool2d(2),

            nn.Conv2d(32, 64, kernel_size=3, padding=1),
            nn.BatchNorm2d(64),
            nn.ReLU(inplace=True),
            nn.AdaptiveAvgPool2d(1),
        )
        self.classifier = nn.Linear(64, 2)  # [not_wake_word, wake_word]

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (batch, n_mels, time) -> (batch, 1, n_mels, time)
        x = x.unsqueeze(1)
        x = self.features(x)
        x = x.flatten(1)
        return self.classifier(x)

    @torch.no_grad()
    def wake_probability(self, x: torch.Tensor) -> float:
        """x: (n_mels, time) single example. Returns P(wake word)."""
        self.eval()
        logits = self.forward(x.unsqueeze(0))
        return torch.softmax(logits, dim=-1)[0, 1].item()
