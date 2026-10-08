"""Cranberry's "brain": combines the intent classifier and persona generator.

Works even before you've trained anything — falls back to keyword matching
and a small canned reply pool (in Cariberry's own voice) so the assistant is
usable immediately, and gets more personality as you train `train.py` on a
larger dataset_gen.py corpus.
"""

from __future__ import annotations

import random
from dataclasses import dataclass
from pathlib import Path

from .. import config
from .slots import extract_app_slot, resolve_open_target
from .tokenizer import Tokenizer

# PyTorch is optional. Without it Cranberry still works: keyword matching for commands, canned
# replies for small talk, and any chat brain you've connected (see llm.py). With it (and after
# `python -m cranberry.brain.train`) you also get the learned intent classifier and TinyGPT.
try:  # pragma: no cover - depends on the environment
    import torch

    from .intent_classifier import IntentClassifier
    from .model import TinyGPT
    HAVE_TORCH = True
except ImportError:  # pragma: no cover
    torch = None  # type: ignore[assignment]
    IntentClassifier = None  # type: ignore[assignment,misc]
    TinyGPT = None  # type: ignore[assignment,misc]
    HAVE_TORCH = False

_FALLBACK_REPLIES = {
    "open_app": ["on it! opening {app} 🐾", "opening {app} now 💪"],
    "close_app": ["closing {app} for you 🐾", "on it — shutting {app} down"],
    "close_window": ["closing this window 🐾", "on it — closing that window"],
    "greeting": ["hi!! 🐾 what can i do for you?", "hey! good to hear you 💗"],
    "thanks": ["anytime! 💗", "that's what i'm here for 🐾"],
    "how_are_you": ["doing great, thanks for asking! 💗 how about you?"],
    "small_talk": ["i'm still learning, but i'm doing my best for you 🐕", "aww thank you!! 🥹"],
}


def _friendly_url_name(url: str) -> str:
    return config.WEB_APP_NAMES.get(url, url)


@dataclass
class BrainResult:
    intent: str
    app: str | None
    reply: str
    # "app" (a real installed app), "url" (a known web app with no native
    # Dock icon, e.g. NotebookLM), or "window" (close_app with no app named
    # -- close whatever's in front instead). None for anything else.
    target_kind: str | None = None


class Brain:
    def __init__(self, weights_dir: Path = config.WEIGHTS_DIR):
        self.tokenizer: Tokenizer | None = None
        self.intent_model: IntentClassifier | None = None
        self.generator: TinyGPT | None = None
        self._load(weights_dir)

    def _load(self, weights_dir: Path) -> None:
        vocab_path = weights_dir / "vocab.json"
        if not HAVE_TORCH or not vocab_path.exists():
            return
        self.tokenizer = Tokenizer.load(vocab_path)

        intent_path = weights_dir / "intent_classifier.pt"
        if intent_path.exists():
            model = IntentClassifier(vocab_size=len(self.tokenizer))
            model.load_state_dict(torch.load(intent_path, map_location="cpu"))
            model.eval()
            self.intent_model = model

        generator_path = weights_dir / "generator.pt"
        if generator_path.exists():
            from .train import GENERATOR_D_MODEL, GENERATOR_N_LAYERS, MAX_LEN

            model = TinyGPT(
                vocab_size=len(self.tokenizer),
                d_model=GENERATOR_D_MODEL,
                n_layers=GENERATOR_N_LAYERS,
                max_len=MAX_LEN - 1,
            )
            model.load_state_dict(torch.load(generator_path, map_location="cpu"))
            model.eval()
            self.generator = model

    @property
    def is_trained(self) -> bool:
        return self.intent_model is not None

    def _understand(self, text: str) -> tuple[str, str | None, str | None]:
        """Returns (intent, target_value, target_kind). target_kind is only
        meaningful for open_app ("app"/"url") and close_app ("app"/"window")."""
        app_for_classification = extract_app_slot(text, config.KNOWN_APPS)
        if self.intent_model and self.tokenizer:
            intent = self.intent_model.predict(text, self.tokenizer)
        else:
            intent = self._keyword_intent(text, app_for_classification)

        if intent == "open_app":
            resolved = resolve_open_target(text)
            if resolved is None:
                return "small_talk", None, None
            kind, value = resolved
            return intent, value, kind

        if intent == "close_app":
            app = extract_app_slot(text, config.KNOWN_APPS)
            if app is None:
                return intent, None, "window"
            return intent, app, "app"

        return intent, None, None

    @staticmethod
    def _keyword_intent(text: str, app: str | None) -> str:
        lowered = text.lower()
        if app and any(w in lowered for w in ("open", "launch", "start", "pull up")):
            return "open_app"
        if app and any(w in lowered for w in ("close", "quit", "shut")):
            return "close_app"
        if "thank" in lowered:
            return "thanks"
        if "how are you" in lowered or "how're you" in lowered:
            return "how_are_you"
        if any(w in lowered for w in ("hi", "hello", "hey", "morning", "evening")):
            return "greeting"
        return "small_talk"

    def _generate(self, text: str) -> str | None:
        if not (self.generator and self.tokenizer):
            return None
        prompt = f"user: {text} cranberry:"
        prompt_ids = self.tokenizer.encode(prompt, add_special=True)[:-1]  # drop trailing <eos>
        generated_ids = self.generator.generate(prompt_ids, eos_id=self.tokenizer.eos_id)
        reply = self.tokenizer.decode(generated_ids).strip()
        return reply or None

    def respond(self, text: str) -> BrainResult:
        intent, value, target_kind = self._understand(text)

        reply: str | None = None
        # Action intents get a template reply (reliable, always names the
        # right app); the generator only speaks for itself on chit-chat,
        # where a wrong word doesn't cause a wrong click.
        if intent == "open_app":
            display_name = value if target_kind == "app" else _friendly_url_name(value)
            reply = random.choice(_FALLBACK_REPLIES["open_app"]).format(app=display_name)
        elif intent == "close_app":
            reply_key = "close_window" if target_kind == "window" else "close_app"
            reply = random.choice(_FALLBACK_REPLIES[reply_key]).format(app=value)
        else:
            reply = self._generate(text)

        if not reply:
            reply = random.choice(_FALLBACK_REPLIES.get(intent, _FALLBACK_REPLIES["small_talk"])).format(app=value or "")

        app_field = value if intent in ("open_app", "close_app") and target_kind != "window" else None
        return BrainResult(intent=intent, app=app_field, reply=reply, target_kind=target_kind)
