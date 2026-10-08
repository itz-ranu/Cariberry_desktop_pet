"""Turns raw audio into the log-mel spectrogram the wake-word CNN reads.

This is plain signal processing (via librosa), not a pretrained model — the
same kind of utility as calling numpy.fft. No weights, nothing learned here.
"""

from __future__ import annotations

import numpy as np
import librosa

from .. import config

N_MELS = 40
N_FFT = 400          # 25ms at 16kHz
HOP_LENGTH = 160      # 10ms at 16kHz


def log_mel_spectrogram(clip: np.ndarray, sample_rate: int = config.SAMPLE_RATE) -> np.ndarray:
    """Returns a (N_MELS, T) log-mel spectrogram, roughly zero-centered."""
    if clip.dtype != np.float32:
        clip = clip.astype(np.float32)
    mel = librosa.feature.melspectrogram(
        y=clip,
        sr=sample_rate,
        n_fft=N_FFT,
        hop_length=HOP_LENGTH,
        n_mels=N_MELS,
        power=2.0,
    )
    log_mel = librosa.power_to_db(mel, ref=np.max)
    # Normalize to roughly [-1, 1] so the CNN doesn't have to learn the scale.
    return (log_mel + 40.0) / 40.0


def fixed_width(spectrogram: np.ndarray, width: int) -> np.ndarray:
    """Pads or center-crops a spectrogram's time axis to exactly `width` frames."""
    n_mels, t = spectrogram.shape
    if t == width:
        return spectrogram
    if t > width:
        start = (t - width) // 2
        return spectrogram[:, start:start + width]
    pad_total = width - t
    left = pad_total // 2
    right = pad_total - left
    return np.pad(spectrogram, ((0, 0), (left, right)), mode="constant", constant_values=-1.0)


def clip_to_features(clip: np.ndarray, clip_seconds: float = config.WAKE_CLIP_SECONDS) -> np.ndarray:
    """Full pipeline: raw audio -> fixed-size log-mel spectrogram for the CNN."""
    target_width = 1 + int(clip_seconds * config.SAMPLE_RATE) // HOP_LENGTH
    spec = log_mel_spectrogram(clip)
    return fixed_width(spec, target_width)
