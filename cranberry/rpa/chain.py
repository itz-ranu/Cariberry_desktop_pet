"""Turns a spoken or typed request into a short list of desktop steps.

"Cranberry, open Notion and start my study playlist" becomes
    [open Notion, play music "study"]
so several things can happen from one sentence. Standard library only.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# split on "and", "then", "and then", or a comma
_SPLIT = re.compile(r"\s*(?:,\s*(?:and\s+|then\s+)?|\s+and\s+then\s+|\s+then\s+|\s+and\s+|\s+&\s+)\s*", re.I)

_OPEN = re.compile(r"^(?:please\s+|can you\s+|could you\s+)?(?:open|launch|pull up|start up|go to)\s+(?:my\s+|the\s+)?(.+)$", re.I)
_CLOSE = re.compile(r"^(?:please\s+)?(?:close|quit|shut down|exit)\s+(?:my\s+|the\s+)?(.+)$", re.I)
_MUSIC = re.compile(r"\b(?:play|start|put on|queue|turn on)\b.*\b(?:playlist|music|songs?|lo-?fi|tunes|vibes)\b", re.I)
_FOCUS_WORDS = re.compile(r"\b(?:focus|pomodoro|study session)\b", re.I)
_START_WORDS = re.compile(r"\b(?:start|begin|set up|do)\b", re.I)
_MINUTES = re.compile(r"(\d{1,3})\s*-?\s*min", re.I)

# words that are about the music, not the thing to open
_FILLER = {"my", "the", "a", "some", "please", "playlist", "music", "songs", "song"}


@dataclass
class Step:
    kind: str          # "open" | "close" | "music" | "focus"
    arg: str = ""      # app name, music query, or minutes


def music_query(text: str) -> str:
    words = [w for w in re.findall(r"[\w'-]+", text.lower()) if w not in _FILLER and w not in
             {"play", "start", "put", "on", "queue", "turn"}]
    return " ".join(words).strip() or "study"


def parse(text: str) -> list:
    """Returns the steps, or [] if this isn't a multi-step / music / focus command (so the
    normal intent classifier or chat brain should handle it)."""
    steps: list = []
    for part in _SPLIT.split(text.strip()):
        p = part.strip(" .!?")
        if not p:
            continue
        p = re.sub(r"^(?:hey\s+)?cranberry[,:]?\s*", "", p, flags=re.I)
        if _MUSIC.search(p):
            steps.append(Step("music", music_query(p)))
        elif m := _OPEN.match(p):
            steps.append(Step("open", m.group(1).strip()))
        elif m := _CLOSE.match(p):
            steps.append(Step("close", m.group(1).strip()))
        elif _START_WORDS.search(p) and _FOCUS_WORDS.search(p):
            minutes = _MINUTES.search(p)
            steps.append(Step("focus", minutes.group(1) if minutes else "25"))
        elif steps and steps[-1].kind in ("open", "close") and len(p.split()) <= 3 and p.replace(" ", "").isalnum():
            steps.append(Step(steps[-1].kind, p))          # "open Safari, then Spotify"
    musical = any(s.kind == "music" for s in steps)
    return steps if (len(steps) >= 2 or musical or any(s.kind == "focus" for s in steps)) else []
