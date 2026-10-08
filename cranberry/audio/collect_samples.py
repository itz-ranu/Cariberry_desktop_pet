"""Records training clips for the wake-word model.

Run: python -m cranberry.audio.collect_samples

Because the wake-word detector is trained from scratch, it only exists once
you feed it your own voice. This script records:
  - N clips of you actually saying "Hey Cranberry" (positive)
  - N clips of you saying other things / silence / background noise (negative)

More samples (and more voices, if more than one person will use it) means a
more reliable detector. 40-60 of each is a reasonable starting point;
you can rerun this script at any time to add more before retraining.
"""

from __future__ import annotations

import sys
from pathlib import Path

from scipy.io import wavfile

from .. import config
from .mic import record_seconds

FILLER_PROMPTS = [
    "what's the weather like today",
    "open safari please",
    "(just stay quiet for a second)",
    "hey siri, what time is it",
    "can you close this tab",
    "good morning",
    "(hum, cough, or shuffle papers)",
    "hey cranberry... wait no, ignore me",
    "let's get some coffee",
    "(keyboard typing / background noise)",
]


def _next_index(directory: Path) -> int:
    existing = list(directory.glob("*.wav"))
    return len(existing)


def _record_batch(directory: Path, count: int, seconds: float, prompt_fn) -> None:
    directory.mkdir(parents=True, exist_ok=True)
    start = _next_index(directory)
    for i in range(count):
        idx = start + i
        prompt = prompt_fn(i)
        input(f"  [{i + 1}/{count}] Say: \"{prompt}\"  -- press Enter, then speak")
        print("    recording...", end=" ", flush=True)
        clip = record_seconds(seconds)
        path = directory / f"{idx:04d}.wav"
        wavfile.write(path, config.SAMPLE_RATE, clip)
        print(f"saved {path.name}")


def main() -> None:
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 40

    print("=== Cranberry wake-word sample collection ===\n")
    print(f"Step 1: say \"{config.WAKE_WORD}\" naturally, {count} times.")
    print("Vary your distance from the mic, tone, and pace a little each time.\n")
    _record_batch(
        config.DATA_DIR / "wake" / "positive",
        count,
        config.WAKE_CLIP_SECONDS,
        prompt_fn=lambda i: config.WAKE_WORD,
    )

    print(f"\nStep 2: say {count} *other* things, so the model learns what's NOT the wake word.\n")
    _record_batch(
        config.DATA_DIR / "wake" / "negative",
        count,
        config.WAKE_CLIP_SECONDS,
        prompt_fn=lambda i: FILLER_PROMPTS[i % len(FILLER_PROMPTS)],
    )

    print("\nDone. Next: python -m cranberry.audio.train_wake_word")


if __name__ == "__main__":
    main()
