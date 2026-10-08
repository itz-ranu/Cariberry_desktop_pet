"""Synthetic keyboard events via CGEvent -- same permission story as
mouse.py (needs Accessibility for whatever runs this venv's python3)."""

from __future__ import annotations

from Quartz import (
    CGEventCreateKeyboardEvent,
    CGEventPost,
    CGEventSetFlags,
    kCGEventFlagMaskCommand,
    kCGHIDEventTap,
)

_KEYCODE_W = 13  # 'w' on the standard ANSI US layout


def close_frontmost_window() -> None:
    """Sends Cmd+W to whatever app is frontmost -- the same shortcut a
    person would press, so it closes a single window/tab without quitting
    the app, matching how "close this window" reads to a person."""
    down = CGEventCreateKeyboardEvent(None, _KEYCODE_W, True)
    CGEventSetFlags(down, kCGEventFlagMaskCommand)
    up = CGEventCreateKeyboardEvent(None, _KEYCODE_W, False)
    CGEventSetFlags(up, kCGEventFlagMaskCommand)
    CGEventPost(kCGHIDEventTap, down)
    CGEventPost(kCGHIDEventTap, up)
