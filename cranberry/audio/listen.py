"""Real-time "Hey Cranberry" detection loop.

Maintains a rolling ~1.2s audio window, rescored every `WAKE_HOP_SECONDS`,
using the CNN trained by `train_wake_word.py`. Requires
`config.WEIGHTS_DIR / "wake_word.pt"` to exist.
"""

from __future__ import annotations

import time
from pathlib import Path
from typing import Callable

import numpy as np
import torch

from .. import config
from .features import clip_to_features
from .mic import MicStream
from .wake_word_model import WakeWordCNN


class WakeWordListener:
    def __init__(self, weights_path: Path = config.WEIGHTS_DIR / "wake_word.pt", threshold: float = 0.85):
        if not weights_path.exists():
            raise FileNotFoundError(
                f"No trained wake-word model at {weights_path}. "
                "Run collect_samples.py then train_wake_word.py first."
            )
        self.model = WakeWordCNN()
        self.model.load_state_dict(torch.load(weights_path, map_location="cpu"))
        self.model.eval()
        self.threshold = threshold

        self._window_size = int(config.WAKE_CLIP_SECONDS * config.SAMPLE_RATE)
        self._buffer = np.zeros(self._window_size, dtype=np.float32)

    def listen_forever(self, on_wake: Callable[[], None]) -> None:
        mic = MicStream(frame_seconds=config.WAKE_HOP_SECONDS)
        consecutive_hits = 0
        last_trigger = 0.0

        print(f'Listening for "{config.WAKE_WORD}"... (Ctrl+C to stop)')
        for hop in mic.frames():
            self._buffer = np.roll(self._buffer, -len(hop))
            self._buffer[-len(hop):] = hop

            features = torch.from_numpy(clip_to_features(self._buffer)).float()
            probability = self.model.wake_probability(features)

            if probability >= self.threshold:
                consecutive_hits += 1
            else:
                consecutive_hits = 0

            now = time.monotonic()
            if (
                consecutive_hits >= config.WAKE_CONSECUTIVE_HITS
                and now - last_trigger > config.WAKE_COOLDOWN_SECONDS
            ):
                last_trigger = now
                consecutive_hits = 0
                on_wake()
