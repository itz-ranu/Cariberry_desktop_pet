"""Discovers every app actually installed on this Mac, so "open any app"
means any app, not just the dozen names in config.KNOWN_APPS.

config.KNOWN_APPS still exists and still matters: it's what the intent
classifier trains on to learn the *shape* of an "open X" request. This
module is the separate, much longer list used only at inference time to
resolve X to a real, installed app -- there's no need to retrain on every
app on your disk just to look its name up.
"""

from __future__ import annotations

import time
from pathlib import Path

_SEARCH_DIRS = [
    Path("/Applications"),
    Path("/System/Applications"),
    Path("/System/Applications/Utilities"),
    Path.home() / "Applications",
]

_cache: list[str] = []
_cache_time: float = 0.0
_CACHE_SECONDS = 300  # apps don't get installed mid-conversation; a few
                       # minutes keeps repeated lookups cheap without ever
                       # needing a restart to see a newly installed app.


def installed_app_names() -> list[str]:
    global _cache, _cache_time
    now = time.monotonic()
    if _cache and now - _cache_time < _CACHE_SECONDS:
        return _cache

    names: set[str] = set()
    for directory in _SEARCH_DIRS:
        if not directory.is_dir():
            continue
        for entry in directory.glob("*.app"):
            names.add(entry.stem)

    _cache = sorted(names)
    _cache_time = now
    return _cache
