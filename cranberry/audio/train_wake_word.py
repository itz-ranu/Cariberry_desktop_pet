"""Trains the wake-word CNN on the clips from `collect_samples.py`.

Run: python -m cranberry.audio.train_wake_word

Entirely local: no data leaves your machine, and the model starts from
random weights every time you run this (no pretrained checkpoint is loaded).
"""

from __future__ import annotations

import random
from pathlib import Path

import numpy as np
import torch
from scipy.io import wavfile
from torch import nn
from torch.utils.data import DataLoader, Dataset

from .. import config
from .features import clip_to_features
from .wake_word_model import WakeWordCNN


class ClipDataset(Dataset):
    def __init__(self, positive_dir: Path, negative_dir: Path):
        self.items: list[tuple[Path, int]] = []
        self.items += [(p, 1) for p in sorted(positive_dir.glob("*.wav"))]
        self.items += [(p, 0) for p in sorted(negative_dir.glob("*.wav"))]
        random.Random(0).shuffle(self.items)

    def __len__(self) -> int:
        return len(self.items)

    def __getitem__(self, idx: int):
        path, label = self.items[idx]
        sr, clip = wavfile.read(path)
        clip = clip.astype(np.float32)
        if clip.max() > 1.0:  # int16 wav
            clip = clip / 32768.0
        features = clip_to_features(clip)
        return torch.from_numpy(features).float(), label


def train(epochs: int = 30, batch_size: int = 8, lr: float = 1e-3) -> None:
    positive_dir = config.DATA_DIR / "wake" / "positive"
    negative_dir = config.DATA_DIR / "wake" / "negative"
    n_pos = len(list(positive_dir.glob("*.wav")))
    n_neg = len(list(negative_dir.glob("*.wav")))
    if n_pos < 10 or n_neg < 10:
        raise SystemExit(
            f"Not enough samples yet (found {n_pos} positive, {n_neg} negative). "
            "Run `python -m cranberry.audio.collect_samples` first."
        )

    dataset = ClipDataset(positive_dir, negative_dir)
    n_val = max(2, len(dataset) // 6)
    train_set, val_set = torch.utils.data.random_split(
        dataset, [len(dataset) - n_val, n_val], generator=torch.Generator().manual_seed(0)
    )
    train_loader = DataLoader(train_set, batch_size=batch_size, shuffle=True)
    val_loader = DataLoader(val_set, batch_size=batch_size)

    model = WakeWordCNN()
    optimizer = torch.optim.Adam(model.parameters(), lr=lr)
    loss_fn = nn.CrossEntropyLoss()

    best_val_acc = 0.0
    config.WEIGHTS_DIR.mkdir(exist_ok=True)
    out_path = config.WEIGHTS_DIR / "wake_word.pt"

    for epoch in range(1, epochs + 1):
        model.train()
        total_loss = 0.0
        for features, labels in train_loader:
            optimizer.zero_grad()
            logits = model(features)
            loss = loss_fn(logits, labels)
            loss.backward()
            optimizer.step()
            total_loss += loss.item() * len(labels)

        model.eval()
        correct = 0
        with torch.no_grad():
            for features, labels in val_loader:
                preds = model(features).argmax(dim=-1)
                correct += (preds == labels).sum().item()
        val_acc = correct / len(val_set) if len(val_set) else 0.0

        print(f"epoch {epoch:2d}  train_loss={total_loss / len(train_set):.4f}  val_acc={val_acc:.2%}")

        if val_acc >= best_val_acc:
            best_val_acc = val_acc
            torch.save(model.state_dict(), out_path)

    print(f"\nBest val accuracy: {best_val_acc:.2%}")
    print(f"Saved weights to {out_path}")
    if best_val_acc < 0.85:
        print(
            "That's a bit low for a live wake word — record more samples "
            "(especially more negatives covering normal speech/typing/music) "
            "and rerun training."
        )


if __name__ == "__main__":
    train()
