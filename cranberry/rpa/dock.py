"""Finds a Dock icon's on-screen position via the Accessibility (AX) API.

This is the same technique automation tools like Hammerspoon use: walk the
Dock process's accessibility tree, find the AXDockItem whose title matches,
and read its position/size. Requires Accessibility permission (see mouse.py).

This is the part most likely to need a small tweak on your machine — macOS
versions have shuffled the exact AX role names before. `debug_dump_items()`
prints everything this script can see, which is the fastest way to check
what's actually there if `find_icon_center` comes back None.
"""

from __future__ import annotations

from ApplicationServices import (
    AXIsProcessTrusted,
    AXUIElementCopyAttributeValue,
    AXUIElementCreateApplication,
    AXValueGetValue,
    kAXChildrenAttribute,
    kAXPositionAttribute,
    kAXSizeAttribute,
    kAXTitleAttribute,
)
from AppKit import NSWorkspace

# Defined by ApplicationServices but not always exposed as a Python constant.
kAXValueCGPointType = 1
kAXValueCGSizeType = 2


def _dock_pid() -> int | None:
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        if app.bundleIdentifier() == "com.apple.dock":
            return app.processIdentifier()
    return None


def _attr(element, name):
    err, value = AXUIElementCopyAttributeValue(element, name, None)
    return value if err == 0 else None


def _point(value) -> tuple[float, float] | None:
    if value is None:
        return None
    ok, point = AXValueGetValue(value, kAXValueCGPointType, None)
    return (point.x, point.y) if ok else None


def _size(value) -> tuple[float, float] | None:
    if value is None:
        return None
    ok, size = AXValueGetValue(value, kAXValueCGSizeType, None)
    return (size.width, size.height) if ok else None


def _dock_items():
    pid = _dock_pid()
    if pid is None:
        return []
    dock = AXUIElementCreateApplication(pid)
    children = _attr(dock, kAXChildrenAttribute) or []
    for child in children:
        # The Dock exposes one AXList holding all the icons.
        grandchildren = _attr(child, kAXChildrenAttribute) or []
        if grandchildren:
            return grandchildren
    return []


def has_accessibility_permission() -> bool:
    return bool(AXIsProcessTrusted())


def debug_dump_items() -> None:
    if not has_accessibility_permission():
        print(
            "Accessibility permission isn't granted to this Python process, so the "
            "Dock is invisible to it (every AX call fails with -25211 / API disabled).\n"
            "Fix: System Settings -> Privacy & Security -> Accessibility -> add "
            "Terminal (or whichever app/binary is running this venv's python3), "
            "then re-run this."
        )
        return
    items = _dock_items()
    print(f"Found {len(items)} Dock item(s):")
    for item in items:
        title = _attr(item, kAXTitleAttribute)
        pos = _point(_attr(item, kAXPositionAttribute))
        size = _size(_attr(item, kAXSizeAttribute))
        print(f"  {title!r}  pos={pos}  size={size}")


def find_icon_center(app_name: str) -> tuple[float, float] | None:
    """Returns the screen-coordinate center of `app_name`'s Dock icon, or
    None if it isn't pinned to (or currently running and shown in) the Dock."""
    target = app_name.strip().lower()
    for item in _dock_items():
        title = _attr(item, kAXTitleAttribute)
        if not title or title.strip().lower() != target:
            continue
        position = _point(_attr(item, kAXPositionAttribute))
        size = _size(_attr(item, kAXSizeAttribute))
        if position is None or size is None:
            continue
        return (position[0] + size[0] / 2, position[1] + size[1] / 2)
    return None


if __name__ == "__main__":
    debug_dump_items()
