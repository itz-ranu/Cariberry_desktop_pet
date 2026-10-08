"""High-level "do the thing" actions Cranberry can take.

Opening an app is the literal "paw moves and clicks the icon" gesture: find
the Dock icon via Accessibility, glide the real cursor there with the paw
overlay riding along, and click it for real.

Closing is handled differently and deliberately: a single left-click on a
running app's Dock icon just refocuses it, it doesn't quit anything — the
real "click to quit" gesture is right-click -> Quit from the context menu,
which means locating a transient AXMenu and its "Quit <App>" item. That's
meaningfully more fragile automation surface for comparatively little
payoff, so v1 quits the same way clicking Quit ultimately does at the OS
level (NSRunningApplication.terminate()) without the extra click chain.
"""

from __future__ import annotations

import subprocess
import time

from AppKit import NSWorkspace

from . import dock, keyboard, mouse
from .cursor_overlay import PawCursorOverlay


def open_app(app_name: str, overlay: PawCursorOverlay | None = None) -> bool:
    """Returns True if this actually clicked the app's real Dock icon,
    False if it fell back to a plain launch (app isn't pinned to the Dock,
    or this process doesn't have Accessibility permission yet)."""
    if not dock.has_accessibility_permission():
        print(
            "Cranberry: no Accessibility permission yet, so I can't see the Dock "
            "or move the real cursor -- launching normally instead. Grant it in "
            "System Settings -> Privacy & Security -> Accessibility to get the "
            "real paw-click gesture. (python -m cranberry.rpa.dock for details.)"
        )
        subprocess.run(["open", "-a", app_name], check=False)
        return False

    icon_center = dock.find_icon_center(app_name)
    if icon_center is None:
        subprocess.run(["open", "-a", app_name], check=False)
        return False

    x, y = icon_center
    on_step = None
    if overlay is not None:
        overlay.move_to(*mouse.current_position())
        overlay.show()
        on_step = overlay.move_to

    mouse.glide_to(x, y, duration=0.55, on_step=on_step)
    mouse.click(x, y)

    if overlay is not None:
        time.sleep(0.2)
        overlay.hide()
    return True


def close_app(app_name: str) -> bool:
    target = app_name.strip().lower()
    for app in NSWorkspace.sharedWorkspace().runningApplications():
        name = app.localizedName()
        if name and name.strip().lower() == target:
            return bool(app.terminate())
    return False


def close_frontmost_window() -> bool:
    """"Close this window" with no app named -- Cmd+W on whatever's in
    front. Same Accessibility permission requirement as open_app's click."""
    if not dock.has_accessibility_permission():
        print(
            "Cranberry: no Accessibility permission yet, so I can't send the "
            "Cmd+W keystroke to close a window. Grant it in System Settings -> "
            "Privacy & Security -> Accessibility."
        )
        return False
    keyboard.close_frontmost_window()
    return True


def open_url(url: str) -> None:
    """For web apps with no native Dock icon (NotebookLM, Gmail, ...): opens
    the URL in the default browser directly. There's no icon to click here,
    so this skips the cursor/paw gesture that open_app does for real apps."""
    subprocess.run(["open", url], check=False)


def start_music(query: str = "") -> str:
    """Starts music. Plays a playlist URI if one is configured (`playlist_uri` in
    cranberry.json), otherwise resumes Spotify or Apple Music, whichever is installed.
    Returns a short description of what it did, for the chat."""
    from . import app_registry

    uri = ""
    try:
        import json
        from pathlib import Path

        path = Path.home() / "Library" / "Application Support" / "DesktopPup" / "cranberry.json"
        if path.is_file():
            uri = json.loads(path.read_text()).get("playlist_uri", "")
    except (OSError, ValueError):
        pass

    installed = {name.lower() for name in app_registry.installed_app_names()}
    if "spotify" in installed:
        script = (f'tell application "Spotify" to play track "{uri}"' if uri
                  else 'tell application "Spotify" to activate\ndelay 1\ntell application "Spotify" to play')
        subprocess.run(["osascript", "-e", script], check=False)
        return "spotify" if not uri else "your study playlist"
    if "music" in installed:
        subprocess.run(["osascript", "-e", 'tell application "Music" to play'], check=False)
        return "Apple Music"
    return ""
