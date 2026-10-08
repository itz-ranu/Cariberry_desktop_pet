"""Cranberry: run with `python -m cranberry.main` from the repo root.

The "brain" behind the floating chat drawer in Cariberry.app, plus the voice assistant:
  - the chat: messages typed in Cariberry's native chat drawer arrive over the bridge, and
    replies stream back into it word by word (bridge.py)
  - the chat brain: Ollama / OpenAI / Gemini if you've connected one, otherwise the
    built-in brain, which works with no internet and no PyTorch (brain/llm.py, brain/infer.py)
  - desktop tasks: "open Notion and start my study playlist" (rpa/chain.py, rpa/actions.py)
  - the wake-word listener, if you've trained one (audio/listen.py)

There is no window of its own any more: the old Tkinter chat is gone, and everything you see
is native SwiftUI inside Cariberry.
"""

from __future__ import annotations

import re
import threading
import uuid
from typing import Optional

from . import config
from .bridge import CariberryBridge
from .brain.infer import Brain
from .brain.llm import LLMError, LLMRouter
from .rpa import chain

MOOD_BY_INTENT = {
    "open_app": "proud",
    "close_app": "proud",
    "greeting": "excited",
    "thanks": "love",
    "how_are_you": "happy",
    "small_talk": "curious",
}

# How the pet shows each of her emotions as she speaks (names match Emotion in Theme.swift).
_FALLBACK_MOOD = "happy"


class Cranberry:
    def __init__(self) -> None:
        self.bridge = CariberryBridge()
        self.brain = Brain()
        self.llm = LLMRouter()
        self.persona: dict = {}
        self._busy = threading.Lock()   # one conversation turn at a time

        if not self.brain.is_trained:
            print(
                "Note: the local brain isn't trained (that's fine). Commands use keyword matching "
                "and small talk uses canned replies; connect a chat brain in Cariberry's Settings "
                "for real answers."
            )

    # -- messages from Cariberry -------------------------------------------

    def _on_config(self, message: dict) -> None:
        self.llm.configure(message)
        if isinstance(message.get("persona"), dict):
            self.persona = message["persona"]
        provider = self.llm.settings.provider
        print(f"Cranberry: chat brain is {provider}" + (f" ({self.llm.model})" if provider != "local" else ""))

    def _on_chat(self, message: dict) -> None:
        text = (message.get("text") or "").strip()
        if not text:
            return
        if isinstance(message.get("persona"), dict):
            self.persona = message["persona"]
        request_id = message.get("id") or str(uuid.uuid4())
        threading.Thread(target=self.handle_text, args=(text, request_id), daemon=True).start()

    # -- one turn of conversation ----------------------------------------------

    def handle_text(self, text: str, request_id: Optional[str] = None) -> None:
        """Shared by typed chat and voice: do any desktop task first, otherwise answer."""
        voice = request_id is None
        request_id = request_id or str(uuid.uuid4())
        with self._busy:
            steps = chain.parse(text)
            if steps:
                reply = self._run_steps(steps)
                self._finish(request_id, reply, "proud", voice)
                return

            result = self.brain.respond(text)
            if result.intent in ("open_app", "close_app"):
                self._act_on_intent(result)
                self._finish(request_id, result.reply, MOOD_BY_INTENT.get(result.intent), voice)
                return

            self._chat(request_id, text, result.reply, result.intent, voice)

    def _chat(self, request_id: str, text: str, local_reply: str, intent: str, voice: bool) -> None:
        """Answer with the chosen LLM, streamed. If it's unavailable, answer with the local brain."""
        if self.llm.is_remote_or_llm():
            streamed = []
            try:
                for chunk in self.llm.stream(text, self.persona):
                    streamed.append(chunk)
                    self.bridge.chat_chunk(request_id, chunk, done=False)
                full = "".join(streamed).strip()
                self.bridge.chat_chunk(request_id, "", done=True, mood=MOOD_BY_INTENT.get(intent, _FALLBACK_MOOD))
                if voice or full:
                    self.bridge.say(full[:140] or local_reply, mood=MOOD_BY_INTENT.get(intent, _FALLBACK_MOOD), seconds=4.0)
                if full:
                    return
            except LLMError as exc:
                provider = self.llm.settings.provider
                print(f"Cranberry: {provider} couldn't answer ({exc}); answering locally.")
                self.bridge.task_status(f"couldn't reach {provider}, answering on this Mac")
                if streamed:       # part of a reply already went out: finish it, don't repeat
                    self.bridge.chat_chunk(request_id, "", done=True)
                    return
        self._finish(request_id, local_reply, MOOD_BY_INTENT.get(intent, _FALLBACK_MOOD), voice)

    def _finish(self, request_id: str, reply: str, mood: Optional[str], voice: bool) -> None:
        self.bridge.chat_reply(request_id, reply, mood=mood)
        self.bridge.say(reply[:140], mood=mood, seconds=4.0)

    # -- desktop tasks ---------------------------------------------------------

    def _act_on_intent(self, result) -> None:
        if result.intent == "open_app" and result.target_kind == "app" and result.app:
            self._status(f"🐾 opening {result.app}...")
            self._open_app(result.app)
        elif result.intent == "open_app" and result.target_kind == "url" and result.app:
            self._status("🐾 opening in your browser...")
            self._open_url(result.app)
        elif result.intent == "close_app" and result.target_kind == "app" and result.app:
            self._status(f"🐾 closing {result.app}...")
            self._close_app(result.app)
        elif result.intent == "close_app" and result.target_kind == "window":
            self._status("🐾 closing that window...")
            self._close_window()
        self._status("")

    def _run_steps(self, steps: list) -> str:
        """Runs a chain like [open Notion, play music]. Returns what to say afterwards."""
        done: list = []
        for step in steps:
            if step.kind == "open":
                self._status(f"🐾 opening {step.arg}...")
                self._open_app(step.arg)
                done.append(f"opened {step.arg}")
            elif step.kind == "close":
                self._status(f"🐾 closing {step.arg}...")
                self._close_app(step.arg)
                done.append(f"closed {step.arg}")
            elif step.kind == "music":
                self._status("🐾 finding your music...")
                from .rpa import actions
                what = actions.start_music(step.arg)
                done.append(f"started {what}" if what else "couldn't find a music app")
            elif step.kind == "focus":
                self.bridge.command("focus", minutes=int(step.arg))
                done.append(f"started a {step.arg} minute focus")
        self._status("")
        return "done! " + ", then ".join(done) + " 🐾" if done else "hmm, I couldn't do that one 🥺"

    def _status(self, text: str) -> None:
        self.bridge.task_status(text)

    def _open_app(self, app_name: str) -> None:
        from .rpa import actions

        overlay = None
        try:
            from .rpa.cursor_overlay import PawCursorOverlay
            overlay = PawCursorOverlay()
        except Exception as exc:  # pyobjc/AppKit issues shouldn't break the action
            print(f"Cranberry: couldn't create the paw overlay ({exc}); clicking without it.")
        actions.open_app(app_name, overlay=overlay)

    def _open_url(self, url: str) -> None:
        from .rpa import actions
        actions.open_url(url)

    def _close_app(self, app_name: str) -> None:
        from .rpa import actions
        actions.close_app(app_name)

    def _close_window(self) -> None:
        from .rpa import actions
        actions.close_frontmost_window()

    # -- voice loop -----------------------------------------------------------

    def _run_wake_word_loop(self) -> None:
        try:
            from .audio.listen import WakeWordListener
            listener = WakeWordListener()
        except (FileNotFoundError, ImportError) as exc:
            print(f"Cranberry: voice activation is off ({exc}); the chat drawer still works.")
            return

        def on_wake() -> None:
            self.bridge.say("yes? \U0001F43E\U0001F442", mood="curious", seconds=2.0)
            text = self.bridge.transcribe(max_seconds=config.COMMAND_MAX_SECONDS)
            if not text:
                self.bridge.say("hmm, didn't catch that \U0001F97A", seconds=2.5)
                return
            self.bridge.heard(text)
            self.handle_text(text)

        listener.listen_forever(on_wake)

    # -- entry point ------------------------------------------------------

    def run(self) -> None:
        self.bridge.on("config", self._on_config)
        self.bridge.on("chat", self._on_chat)
        self.bridge.on_connect(lambda: print("Connected to Cariberry."))
        print("Connecting to Cariberry (it keeps retrying if it isn't up yet)...")
        self.bridge.start()
        threading.Thread(target=self._run_wake_word_loop, daemon=True).start()
        self._serve_forever()

    def _serve_forever(self) -> None:
        """Stays alive and serves the bridge. With PyObjC available the main thread runs a real
        Cocoa event loop (as a Dock-less accessory app): the paw cursor overlay is an AppKit
        window and needs one to draw, a job the old Tk window quietly did. Without PyObjC it
        just waits."""
        try:
            from AppKit import NSApplication, NSApplicationActivationPolicyAccessory
            from PyObjCTools import AppHelper
        except ImportError:
            try:
                threading.Event().wait()
            except KeyboardInterrupt:
                self.bridge.stop()
            return
        NSApplication.sharedApplication().setActivationPolicy_(NSApplicationActivationPolicyAccessory)
        try:
            AppHelper.runEventLoop(installInterrupt=True)
        finally:
            self.bridge.stop()


def main() -> None:
    Cranberry().run()


if __name__ == "__main__":
    main()
