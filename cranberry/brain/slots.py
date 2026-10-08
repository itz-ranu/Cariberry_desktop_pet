"""Torch-free helpers for pulling an app (or website) name out of a request.

These used to live in intent_classifier.py, which imports PyTorch at module level, so
even a plain "open Spotify" needed torch installed. They only use the standard library,
so they live here and the rest of Cranberry can use them without it.
"""

from __future__ import annotations

import difflib

from .. import config
from .tokenizer import basic_tokenize


def _best_fuzzy_match(text: str, candidates: dict[str, str]) -> str | None:
    """Shared core: exact match against whole words/bigrams first, then a
    stdlib-only (`difflib`, no external service) fuzzy match of the same
    words/bigrams against the candidate keys. `candidates` maps a lowercased
    name/alias to whatever value it should resolve to.

    Matching is against tokenized words, never a raw substring check of the
    full text -- "mail" is a raw substring of "gmail" and "note" of
    "notebooklm", so a naive `key in text.lower()` check resolved both of
    those to the wrong (unrelated) app before this was word-boundary-aware.
    """
    words = basic_tokenize(text)
    phrases = list(words) + [f"{a} {b}" for a, b in zip(words, words[1:])]

    for phrase in phrases:
        if phrase in candidates:
            return candidates[phrase]

    # A high cutoff here is deliberate: short, common words like "mail" are
    # a ~0.89 fuzzy-ratio away from unrelated words like "gmail", which is
    # too close to reject with a looser threshold. Genuine typos we want to
    # catch score higher still ("spotifiy"/"spotify" 0.93, "x code"/"xcode"
    # 0.91) -- known casual variants below that line (like "whatsup") are
    # handled by explicit config.APP_ALIASES entries instead, not by fuzzing
    # harder here.
    best_value, best_score = None, 0.0
    for phrase in phrases:
        match = difflib.get_close_matches(phrase, candidates.keys(), n=1, cutoff=0.90)
        if match:
            score = difflib.SequenceMatcher(None, phrase, match[0]).ratio()
            if score > best_score:
                best_value, best_score = candidates[match[0]], score
    return best_value


def extract_app_slot(text: str, known_apps: list[str]) -> str | None:
    """Matches an app name in `text`, tolerating typos and casual phrasing
    ("whatsup", "spotifiy") without needing a learned slot-filler — overkill
    for a closed vocabulary this small, the same "don't build an abstraction
    you don't need" call as using a plain classifier instead of a
    sequence-labeling model.
    """
    candidates: dict[str, str] = {app.lower(): app for app in known_apps}
    for app, aliases in config.APP_ALIASES.items():
        if app in known_apps:
            for alias in aliases:
                candidates[alias] = app
    return _best_fuzzy_match(text, candidates)


def _match_web_app(text: str) -> str | None:
    candidates: dict[str, str] = {}
    for url, names in config.WEB_APPS.items():
        for name in names:
            candidates[name] = url
    return _best_fuzzy_match(text, candidates)


def resolve_open_target(text: str) -> tuple[str, str] | None:
    """Resolves an open_app request to either (\"app\", display_name) for a
    real installed app, or (\"url\", url) for a known web app that isn't
    installed natively -- e.g. "open notebooklm" has no Dock icon to click,
    so it opens as a URL in the default browser instead. Installed apps are
    checked first, so a real app always wins over a same-named website.
    """
    from ..rpa.app_registry import installed_app_names

    native_apps = list(dict.fromkeys(config.KNOWN_APPS + installed_app_names()))
    app = extract_app_slot(text, native_apps)
    if app:
        return ("app", app)

    url = _match_web_app(text)
    if url:
        return ("url", url)

    return None
