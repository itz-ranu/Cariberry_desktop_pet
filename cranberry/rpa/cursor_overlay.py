"""A floating, click-through 'paw' cursor that visually follows the real
mouse movement performed by mouse.py.

macOS doesn't let a background script swap the actual system cursor image
without much riskier private APIs, so instead we do what's genuinely
supportable: the real OS cursor does the real moving/clicking (so clicks
always land on the right pixel), and this small always-on-top transparent
window paints a paw over it so the *gesture* reads as Cranberry's paw doing
the work.

This is the most visually finicky piece of the whole project because pyobjc
GUI code outside a full `NSApplication.run()` loop needs to be nudged to
actually flush to the window server — `_pump()` below does that. If the paw
doesn't appear, the click still happens correctly; this layer is cosmetic.
"""

from __future__ import annotations

from AppKit import (
    NSApplication,
    NSBackingStoreBuffered,
    NSColor,
    NSFloatingWindowLevel,
    NSFont,
    NSScreen,
    NSTextAlignmentCenter,
    NSTextField,
    NSWindow,
    NSWindowStyleMaskBorderless,
)
from Foundation import NSDate, NSMakeRect, NSRunLoop


class PawCursorOverlay:
    def __init__(self, size: float = 34.0):
        NSApplication.sharedApplication()
        self.size = size
        self.screen_height = NSScreen.mainScreen().frame().size.height

        self.window = NSWindow.alloc().initWithContentRect_styleMask_backing_defer_(
            NSMakeRect(0, 0, size, size),
            NSWindowStyleMaskBorderless,
            NSBackingStoreBuffered,
            False,
        )
        self.window.setOpaque_(False)
        self.window.setBackgroundColor_(NSColor.clearColor())
        self.window.setLevel_(NSFloatingWindowLevel + 1)
        self.window.setIgnoresMouseEvents_(True)
        self.window.setHasShadow_(True)

        label = NSTextField.alloc().initWithFrame_(NSMakeRect(0, 0, size, size))
        label.setStringValue_("\U0001F43E")  # 🐾
        label.setFont_(NSFont.systemFontOfSize_(size * 0.75))
        label.setBezeled_(False)
        label.setDrawsBackground_(False)
        label.setEditable_(False)
        label.setSelectable_(False)
        label.setAlignment_(NSTextAlignmentCenter)
        self.window.contentView().addSubview_(label)

    def _pump(self) -> None:
        NSRunLoop.currentRunLoop().runUntilDate_(NSDate.dateWithTimeIntervalSinceNow_(0.0))

    def show(self) -> None:
        self.window.orderFrontRegardless()
        self._pump()

    def hide(self) -> None:
        self.window.orderOut_(None)
        self._pump()

    def move_to(self, quartz_x: float, quartz_y: float) -> None:
        """`quartz_x/y` are CGEvent-style top-left-origin screen coordinates,
        same as mouse.py hands to `on_step` during `glide_to`."""
        appkit_x = quartz_x - self.size / 2
        appkit_y = self.screen_height - quartz_y - self.size / 2
        self.window.setFrameOrigin_((appkit_x, appkit_y))
        self._pump()
