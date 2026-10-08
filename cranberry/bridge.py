"""Client for the loopback socket that Cariberry.app hosts.

Cariberry (Swift) is the long-running process, so it listens; we connect to it, retrying
quietly if it isn't up yet. Everything is newline-delimited JSON, one object per line, in both
directions. See Sources/DesktopPup/CranberryBridge.swift for the other end.

Messages from Cariberry:
  config      {provider, model, keys{}, persona{}}   which chat brain to use, and who she is
  chat        {id, text, persona{}}                  something typed in the floating chat drawer
  event       {event, ...}                           a mood check-in, a finished session...
  transcribed {id, text}                             the answer to a `transcribe` request

Messages to Cariberry:
  say         {text, mood?, seconds?}                show a speech bubble
  chat_chunk  {id, text, done?, mood?}               part of a streamed reply
  chat_reply  {id, text, mood?}                      a whole (final) reply
  task_status {text}                                 "opening Notion…": shown under the chat
  command     {name, ...}                            make her do something: focus {minutes}, dance, stay
  heard       {text}                                 a voice command, so it shows in the transcript
  transcribe  {id, max_seconds}                      record + transcribe the next utterance
"""

from __future__ import annotations

import json
import socket
import threading
import time
import uuid
from typing import Callable, Optional

from . import config

Handler = Callable[[dict], None]


class CariberryBridge:
    """Talks to the running Cariberry.app over 127.0.0.1.

    Safe to use even when Cariberry isn't running yet or gets restarted: it reconnects in the
    background and every send swallows connection errors, so Cranberry degrades gracefully.
    """

    def __init__(self, host: str = config.BRIDGE_HOST, port: int = config.BRIDGE_PORT):
        self._host = host
        self._port = port
        self._sock: Optional[socket.socket] = None
        self._lock = threading.Lock()
        self._pending: dict[str, threading.Event] = {}
        self._results: dict[str, str] = {}
        self._reader_thread: Optional[threading.Thread] = None
        self._handlers: dict[str, list[Handler]] = {}
        self._on_connect: list[Callable[[], None]] = []
        self._stop = threading.Event()

    # -- registering handlers -------------------------------------------------

    def on(self, message_type: str, handler: Handler) -> None:
        """Calls `handler(message)` (on the reader thread) for each message of this type."""
        self._handlers.setdefault(message_type, []).append(handler)

    def on_connect(self, callback: Callable[[], None]) -> None:
        self._on_connect.append(callback)

    # -- connection management -------------------------------------------------

    def start(self) -> None:
        """Keeps a connection open in the background, reconnecting whenever it drops."""
        threading.Thread(target=self._keepalive, daemon=True).start()

    def stop(self) -> None:
        self._stop.set()
        with self._lock:
            sock, self._sock = self._sock, None
        if sock:
            try:
                sock.close()
            except OSError:
                pass

    def _keepalive(self) -> None:
        while not self._stop.is_set():
            self._ensure_connected()
            self._stop.wait(1.5)

    @property
    def connected(self) -> bool:
        return self._sock is not None

    def _ensure_connected(self) -> Optional[socket.socket]:
        with self._lock:
            if self._sock is not None:
                return self._sock
            try:
                sock = socket.create_connection((self._host, self._port), timeout=1.5)
            except OSError:
                return None
            sock.settimeout(None)
            self._sock = sock
            self._reader_thread = threading.Thread(target=self._read_loop, args=(sock,), daemon=True)
            self._reader_thread.start()
        for callback in self._on_connect:
            try:
                callback()
            except Exception as exc:  # a bad callback must not kill the connection
                print(f"Cranberry: on_connect callback failed: {exc}")
        return sock

    def _drop(self, sock: socket.socket) -> None:
        with self._lock:
            if self._sock is sock:
                self._sock = None
        try:
            sock.close()
        except OSError:
            pass

    def wait_for_cariberry(self, timeout: Optional[float] = None) -> bool:
        """Blocks (with quiet retries) until Cariberry.app accepts a connection."""
        start = time.monotonic()
        while self._ensure_connected() is None:
            if timeout is not None and time.monotonic() - start > timeout:
                return False
            time.sleep(1.0)
        return True

    # -- reading ---------------------------------------------------------------

    def _read_loop(self, sock: socket.socket) -> None:
        buffer = b""
        try:
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    if line:
                        self._handle_line(line)
        except OSError:
            pass
        finally:
            self._drop(sock)

    def _handle_line(self, line: bytes) -> None:
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            return
        if not isinstance(message, dict):
            return
        message_type = message.get("type")
        if message_type == "transcribed":
            request_id = message.get("id")
            if request_id in self._pending:
                self._results[request_id] = message.get("text", "")
                self._pending[request_id].set()
            return
        for handler in self._handlers.get(message_type, []):
            try:
                handler(message)
            except Exception as exc:
                print(f"Cranberry: handler for {message_type!r} failed: {exc}")

    # -- sending -----------------------------------------------------------

    def _send(self, payload: dict) -> bool:
        sock = self._ensure_connected()
        if sock is None:
            return False
        data = (json.dumps(payload) + "\n").encode("utf-8")
        try:
            sock.sendall(data)
            return True
        except OSError:
            self._drop(sock)
            return False

    def say(self, text: str, mood: Optional[str] = None, seconds: float = 3.5) -> bool:
        """Shows `text` as the pet's speech bubble in Cariberry."""
        payload = {"type": "say", "text": text, "seconds": seconds}
        if mood:
            payload["mood"] = mood
        return self._send(payload)

    def chat_chunk(self, request_id: str, text: str, done: bool = False, mood: Optional[str] = None) -> bool:
        payload = {"type": "chat_chunk", "id": request_id, "text": text, "done": done}
        if mood:
            payload["mood"] = mood
        return self._send(payload)

    def chat_reply(self, request_id: str, text: str, mood: Optional[str] = None) -> bool:
        payload = {"type": "chat_reply", "id": request_id, "text": text}
        if mood:
            payload["mood"] = mood
        return self._send(payload)

    def command(self, name: str, **fields) -> bool:
        """Asks Cariberry to do something on the pet (start a focus timer, dance, ...)."""
        return self._send({"type": "command", "name": name, **fields})

    def task_status(self, text: str) -> bool:
        return self._send({"type": "task_status", "text": text})

    def heard(self, text: str) -> bool:
        return self._send({"type": "heard", "text": text})

    def transcribe(self, max_seconds: float = config.COMMAND_MAX_SECONDS, timeout: float = 20.0) -> str:
        """Asks Cariberry to record + transcribe the next utterance on-device.

        Blocks until Cariberry replies or `timeout` elapses. Returns "" if Cariberry isn't
        running, denied the mic, or heard nothing.
        """
        request_id = str(uuid.uuid4())
        event = threading.Event()
        self._pending[request_id] = event
        sent = self._send({"type": "transcribe", "id": request_id, "max_seconds": max_seconds})
        if not sent:
            del self._pending[request_id]
            return ""
        got_result = event.wait(timeout=timeout)
        text = self._results.pop(request_id, "")
        self._pending.pop(request_id, None)
        return text if got_result else ""
