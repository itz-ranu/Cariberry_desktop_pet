"""Real system-wide cursor movement and clicking, via CGEvent (Quartz).

Requires Accessibility permission for whatever process runs Python (System
Settings -> Privacy & Security -> Accessibility -> add Terminal / iTerm /
your venv's python3). Without it, CGEventPost silently does nothing.
"""

from __future__ import annotations

import math
import time

from Quartz import (
    CGEventCreate,
    CGEventCreateMouseEvent,
    CGEventGetLocation,
    CGEventPost,
    CGPointMake,
    kCGEventLeftMouseDown,
    kCGEventLeftMouseUp,
    kCGEventMouseMoved,
    kCGHIDEventTap,
    kCGMouseButtonLeft,
)


def current_position() -> tuple[float, float]:
    point = CGEventGetLocation(CGEventCreate(None))
    return point.x, point.y


def _move_to(x: float, y: float) -> None:
    event = CGEventCreateMouseEvent(None, kCGEventMouseMoved, CGPointMake(x, y), kCGMouseButtonLeft)
    CGEventPost(kCGHIDEventTap, event)


def _ease_in_out(t: float) -> float:
    return 0.5 - 0.5 * math.cos(math.pi * t)


def glide_to(x: float, y: float, duration: float = 0.5, on_step=None) -> None:
    """Moves the real cursor from wherever it is to (x, y) over `duration`
    seconds, easing in/out so it reads as a deliberate gesture rather than a
    teleport. `on_step(x, y)` is called on every intermediate point, so a
    cosmetic overlay (see cursor_overlay.py) can follow the same path."""
    start_x, start_y = current_position()
    steps = max(1, int(duration / 0.016))  # ~60fps
    for i in range(1, steps + 1):
        t = _ease_in_out(i / steps)
        x_i = start_x + (x - start_x) * t
        y_i = start_y + (y - start_y) * t
        _move_to(x_i, y_i)
        if on_step:
            on_step(x_i, y_i)
        time.sleep(duration / steps)


def click(x: float, y: float) -> None:
    down = CGEventCreateMouseEvent(None, kCGEventLeftMouseDown, CGPointMake(x, y), kCGMouseButtonLeft)
    up = CGEventCreateMouseEvent(None, kCGEventLeftMouseUp, CGPointMake(x, y), kCGMouseButtonLeft)
    CGEventPost(kCGHIDEventTap, down)
    time.sleep(0.06)
    CGEventPost(kCGHIDEventTap, up)
