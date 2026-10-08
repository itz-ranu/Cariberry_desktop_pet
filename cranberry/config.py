"""Shared constants for the Cranberry voice-assistant service.

Cranberry is a separate local process from Cariberry.app (the Swift pet).
They only ever talk over a loopback TCP socket — see bridge.py.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
WEIGHTS_DIR = ROOT / "weights"

# --- Bridge (must match CranberryBridge.swift) -----------------------------
BRIDGE_HOST = "127.0.0.1"
BRIDGE_PORT = 8765

# --- Audio -------------------------------------------------------------
SAMPLE_RATE = 16_000
WAKE_WORD = "hey cranberry"

# Rolling window the wake-word model scores, and the hop between scores.
WAKE_CLIP_SECONDS = 1.2
WAKE_HOP_SECONDS = 0.25

# How many consecutive positive frames are required before we trust a
# detection. Cuts down on one-off false triggers from a noisy mic.
WAKE_CONSECUTIVE_HITS = 2
WAKE_COOLDOWN_SECONDS = 2.5

# How long we record the command that follows the wake word.
COMMAND_MAX_SECONDS = 6.0

# --- Apps Cranberry knows how to open ---------------------------------
# The display name must match what's under the app's Dock icon (or, for
# apps that aren't pinned to the Dock, its .app name in /Applications).
KNOWN_APPS = [
    "WhatsApp",
    "Safari",
    "Mail",
    "Messages",
    "Notes",
    "Calendar",
    "Music",
    "Spotify",
    "Terminal",
    "Finder",
    "Slack",
    "Xcode",
]

# Common mishearings/typos/casual spellings, so "open whatsup" still resolves
# to WhatsApp instead of needing an exact name match. Anything not listed
# here still gets a fuzzy match (see brain/intent_classifier.py) — this is
# just for the very common cases worth spelling out explicitly.
APP_ALIASES = {
    # Deliberately NOT aliasing "whats up" / "what's up" here: those are also
    # the extremely common small-talk greeting, and aliasing them pulled the
    # classifier's own "up" association toward open_app, breaking that
    # greeting (see _SMALL_TALK_TEMPLATES, which now trains on it directly
    # instead). "whatsup" as one word is unambiguous enough to keep.
    "WhatsApp": ["whatsapp", "whats app", "whatsup", "watsapp", "whatsaap"],
    "Safari": ["safari"],
    "Spotify": ["spotify", "spotifiy"],
    "Terminal": ["terminal", "term"],
    "Finder": ["finder"],
    "Notes": ["notes", "note"],
    "Calendar": ["calendar", "cal"],
    "Messages": ["messages", "imessage", "message"],
    "Mail": ["mail", "email"],
    "Music": ["music", "itunes"],
    "Slack": ["slack"],
    "Xcode": ["xcode", "x code"],
}

# Things people ask to "open" that aren't installed native apps at all --
# websites. "open notebooklm" only makes sense as opening a URL in the
# default browser; there's no Dock icon to click for it. Native apps are
# always checked first (see rpa/app_registry.py), so a real "NotebookLM.app"
# on your Mac would still win if one ever existed.
WEB_APPS = {
    "https://notebooklm.google.com": ["notebooklm", "notebook lm"],
    "https://mail.google.com": ["gmail", "google mail"],
    "https://docs.google.com": ["google docs", "gdocs"],
    "https://sheets.google.com": ["google sheets", "gsheets"],
    "https://drive.google.com": ["google drive", "gdrive"],
    "https://youtube.com": ["youtube"],
    "https://calendar.google.com": ["google calendar", "gcal"],
    "https://chat.openai.com": ["chatgpt"],
    "https://github.com": ["github"],
}

# Display names for the reply text ("opening NotebookLM 🐾"), separate from
# the lowercase aliases above that are just for matching what the user typed.
WEB_APP_NAMES = {
    "https://notebooklm.google.com": "NotebookLM",
    "https://mail.google.com": "Gmail",
    "https://docs.google.com": "Google Docs",
    "https://sheets.google.com": "Google Sheets",
    "https://drive.google.com": "Google Drive",
    "https://youtube.com": "YouTube",
    "https://calendar.google.com": "Google Calendar",
    "https://chat.openai.com": "ChatGPT",
    "https://github.com": "GitHub",
}
