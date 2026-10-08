"""Thin wrapper over `sounddevice` that yields fixed-length mono float32 frames."""

from __future__ import annotations

import queue
from typing import Iterator

import numpy as np
import sounddevice as sd

from .. import config


class MicStream:
    """Opens the default input device and yields `frame_seconds`-long chunks.

    Frames are produced continuously (each call to `frames()` is a fresh,
    non-overlapping read); code that needs a sliding window keeps its own
    ring buffer on top of this — see `listen.py`.
    """

    def __init__(self, frame_seconds: float, sample_rate: int = config.SAMPLE_RATE):
        self.sample_rate = sample_rate
        self.frame_size = int(frame_seconds * sample_rate)
        self._queue: "queue.Queue[np.ndarray]" = queue.Queue()

    def _callback(self, indata, frames, time_info, status) -> None:  # noqa: ANN001 - sounddevice signature
        self._queue.put(indata[:, 0].copy())

    def frames(self) -> Iterator[np.ndarray]:
        with sd.InputStream(
            samplerate=self.sample_rate,
            channels=1,
            dtype="float32",
            blocksize=self.frame_size,
            callback=self._callback,
        ):
            while True:
                yield self._queue.get()


def record_seconds(seconds: float, sample_rate: int = config.SAMPLE_RATE) -> np.ndarray:
    """Blocks and records a single clip. Used by the sample-collection script."""
    clip = sd.rec(int(seconds * sample_rate), samplerate=sample_rate, channels=1, dtype="float32")
    sd.wait()
    return clip[:, 0]
