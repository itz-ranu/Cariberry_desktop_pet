"""Chat brains for Cranberry: Ollama (local), OpenAI and Gemini.

Pure standard library (urllib), so there is nothing extra to install. A reply is *streamed*:
`LLMRouter.stream()` yields text chunks as they arrive, which main.py forwards to the floating
chat drawer so words appear as they're written.

Privacy: what a provider receives is the conversation you type in the chat plus a short persona
prompt saying who she is (her name, species, personality, the coaching style you chose and the
mood you picked at check-in). Never your screen, files or browsing. API keys come
from the macOS Keychain via Cariberry (sent over the loopback socket and kept in memory only),
or from the usual environment variables if you run Cranberry yourself.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Iterator

OLLAMA_URL = "http://127.0.0.1:11434"

_ENV_KEYS = {
    "openai": "OPENAI_API_KEY",
    "gemini": "GEMINI_API_KEY",
}

_DEFAULT_MODELS = {
    "ollama": "llama3.2",
    "openai": "gpt-4o-mini",
    "gemini": "gemini-2.0-flash",
}

HISTORY_TURNS = 12
TIMEOUT = 40


class LLMError(Exception):
    """The chosen brain couldn't answer (no key, offline, rate-limited...)."""


@dataclass
class Settings:
    provider: str = "local"           # local | ollama | openai | gemini
    model: str = ""
    keys: dict = field(default_factory=dict)


def system_prompt(persona: dict) -> str:
    """Who she is, so the model answers as her (not as a generic assistant)."""
    name = persona.get("name") or "Cranberry"
    species = persona.get("species") or "pet"
    voice = persona.get("voice") or "a sweet, encouraging desktop pet"
    vibe = persona.get("vibe") or ""
    mood = persona.get("mood") or ""
    lines = [
        f"You are {name}, a {species} who lives on the user's Mac as a desktop pet and study bestie.",
        f"Your personality: {voice}.",
        "Talk like a warm, witty friend: short messages (1 to 4 sentences), a few emoji, never preachy.",
        "You can help with homework (explain simply, step by step), rewrite emails or messages "
        "(reply with just the rewrite unless asked otherwise), and have cozy chit-chat.",
        "Stay in character. Don't claim to have done things on the computer yourself; you only chat here.",
        "If a request is unsafe or harmful, decline gently and suggest something kinder.",
    ]
    if vibe and vibe != "Her own voice":
        lines.append(f"Coaching style the user chose: {vibe}.")
    if mood:
        lines.append(f"The user said they feel {mood.lower()} today. Be gentle if that's stressed or tired.")
    return "\n".join(lines)


class LLMRouter:
    def __init__(self) -> None:
        self.settings = Settings()
        self._history: list = []      # [{"role": "user"|"assistant", "content": str}]

    # -- configuration ---------------------------------------------------------

    def configure(self, message: dict) -> None:
        self.settings.provider = (message.get("provider") or "local").lower()
        self.settings.model = (message.get("model") or "").strip()
        keys = message.get("keys") or {}
        if isinstance(keys, dict):
            self.settings.keys = {k: v for k, v in keys.items() if isinstance(v, str) and v}

    def _key(self, provider: str) -> str:
        return self.settings.keys.get(provider) or os.environ.get(_ENV_KEYS.get(provider, ""), "")

    @property
    def model(self) -> str:
        return self.settings.model or _DEFAULT_MODELS.get(self.settings.provider, "")

    def is_remote_or_llm(self) -> bool:
        """True if a real LLM is chosen (and has what it needs). "local" means: use the built-in brain."""
        provider = self.settings.provider
        if provider == "ollama":
            return True
        return provider in _ENV_KEYS and bool(self._key(provider))

    def reset(self) -> None:
        self._history.clear()

    # -- streaming -------------------------------------------------------------

    def stream(self, user_text: str, persona: dict) -> Iterator[str]:
        """Yields the reply in chunks. Raises LLMError if the brain can't answer."""
        provider = self.settings.provider
        if not self.is_remote_or_llm():
            raise LLMError("no chat brain connected")
        messages = self._history[-HISTORY_TURNS * 2:] + [{"role": "user", "content": user_text}]
        system = system_prompt(persona)

        if provider == "ollama":
            source = self._ollama(system, messages)

        elif provider == "openai":
            source = self._openai(system, messages)
        elif provider == "gemini":
            source = self._gemini(system, messages)
        else:
            raise LLMError(f"unknown provider {provider!r}")

        reply = []
        try:
            for chunk in source:
                if chunk:
                    reply.append(chunk)
                    yield chunk
        except LLMError:
            raise
        except (urllib.error.URLError, OSError, ValueError, KeyError) as exc:
            raise LLMError(str(exc)) from exc
        finally:
            if reply:
                self._history.append({"role": "user", "content": user_text})
                self._history.append({"role": "assistant", "content": "".join(reply)})

    # -- providers -------------------------------------------------------------

    @staticmethod
    def _open(request: urllib.request.Request):
        try:
            return urllib.request.urlopen(request, timeout=TIMEOUT)
        except urllib.error.HTTPError as exc:
            detail = ""
            try:
                detail = exc.read().decode("utf-8", "replace")[:200]
            except Exception:
                pass
            raise LLMError(f"HTTP {exc.code} {detail}".strip()) from exc

    @staticmethod
    def _sse_json(response) -> Iterator[dict]:
        """Server-sent events: yields the JSON of every `data:` line."""
        for raw in response:
            line = raw.decode("utf-8", "replace").strip()
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload in ("", "[DONE]"):
                continue
            try:
                yield json.loads(payload)
            except json.JSONDecodeError:
                continue

    def _post(self, url: str, body: dict, headers: dict):
        data = json.dumps(body).encode("utf-8")
        request = urllib.request.Request(url, data=data, method="POST",
                                         headers={"Content-Type": "application/json", **headers})
        return self._open(request)

    def _ollama(self, system: str, messages: list) -> Iterator[str]:
        body = {"model": self.model, "stream": True,
                "messages": [{"role": "system", "content": system}] + messages}
        with self._post(f"{OLLAMA_URL}/api/chat", body, {}) as response:
            for raw in response:
                line = raw.decode("utf-8", "replace").strip()
                if not line:
                    continue
                event = json.loads(line)
                if event.get("error"):
                    raise LLMError(str(event["error"]))
                yield (event.get("message") or {}).get("content", "")
                if event.get("done"):
                    break

    def _openai(self, system: str, messages: list) -> Iterator[str]:
        body = {"model": self.model, "stream": True,
                "messages": [{"role": "system", "content": system}] + messages}
        headers = {"Authorization": f"Bearer {self._key('openai')}", "Accept": "text/event-stream"}
        with self._post("https://api.openai.com/v1/chat/completions", body, headers) as response:
            for event in self._sse_json(response):
                for choice in event.get("choices", []):
                    yield (choice.get("delta") or {}).get("content") or ""



    def _gemini(self, system: str, messages: list) -> Iterator[str]:
        contents = [{"role": "model" if m["role"] == "assistant" else "user", "parts": [{"text": m["content"]}]}
                    for m in messages]
        body = {"systemInstruction": {"parts": [{"text": system}]}, "contents": contents}
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{self.model}:streamGenerateContent?alt=sse"
        headers = {"x-goog-api-key": self._key("gemini"), "Accept": "text/event-stream"}
        with self._post(url, body, headers) as response:
            for event in self._sse_json(response):
                for cand in event.get("candidates", []):
                    for part in (cand.get("content") or {}).get("parts", []):
                        yield part.get("text") or ""
