"""End-to-end test of Cranberry's chat protocol, with no network and no real desktop.

Run from the repo root:   python3 cranberry/tests/test_chat_protocol.py

A fake "Cariberry" socket server and a mock Ollama server stand in for the real things, and
the macOS-only RPA actions are stubbed, so this checks the streaming chat, the conversation
memory, the fallback when a provider fails, task chaining, the focus command back to the app,
the SSE parsers and missing-key handling, all without touching your desktop.
"""

import json, socket, sys, threading, time, types, http.server, socketserver
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

# stub the macOS-only RPA actions module so the test never touches the real desktop
fake_actions = types.ModuleType("cranberry.rpa.actions")
calls = []
fake_actions.open_app = lambda name, overlay=None: calls.append(("open", name)) or True
fake_actions.close_app = lambda name: calls.append(("close", name)) or True
fake_actions.start_music = lambda q="": calls.append(("music", q)) or "spotify"
fake_actions.open_url = lambda u: calls.append(("url", u))
fake_actions.close_frontmost_window = lambda: True
sys.modules["cranberry.rpa.actions"] = fake_actions
import cranberry.rpa as rpa_pkg; rpa_pkg.actions = fake_actions

from cranberry.main import Cranberry
from cranberry.bridge import CariberryBridge
from cranberry.brain import llm

# ---- mock Ollama: streams NDJSON, or fails on demand ----
fail = {"on": False}
class Ollama(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        n = int(self.headers["Content-Length"]); body = json.loads(self.rfile.read(n))
        assert body["stream"] is True and body["messages"][0]["role"] == "system"
        assert "kitten" in body["messages"][0]["content"].lower(), "persona must reach the system prompt"
        if fail["on"]:
            self.send_response(500); self.end_headers(); self.wfile.write(b"boom"); return
        self.send_response(200); self.send_header("Content-Type", "application/x-ndjson"); self.end_headers()
        for word in ["hi ", "bestie ", "💗"]:
            self.wfile.write((json.dumps({"message": {"content": word}, "done": False}) + "\n").encode()); self.wfile.flush()
        self.wfile.write((json.dumps({"message": {"content": ""}, "done": True}) + "\n").encode())
http_srv = socketserver.TCPServer(("127.0.0.1", 0), Ollama); threading.Thread(target=http_srv.serve_forever, daemon=True).start()
llm.OLLAMA_URL = f"http://127.0.0.1:{http_srv.server_address[1]}"

# ---- fake Cariberry: a socket server that records what Python sends ----
srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1); srv.bind(("127.0.0.1", 0)); srv.listen(1)
port = srv.getsockname()[1]
inbox = []; conn_holder = {}
def serve():
    c, _ = srv.accept(); conn_holder["c"] = c; buf = b""
    while True:
        d = c.recv(4096)
        if not d: break
        buf += d
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1); inbox.append(json.loads(line))
threading.Thread(target=serve, daemon=True).start()
def send(obj): conn_holder["c"].sendall((json.dumps(obj) + "\n").encode())
def wait(pred, t=5):
    end = time.time() + t
    while time.time() < end:
        hit = [m for m in inbox if pred(m)]
        if hit: return hit
        time.sleep(0.05)
    raise AssertionError("timed out; saw " + json.dumps(inbox)[-600:])

c = Cranberry(); c.bridge = CariberryBridge(port=port)
c.bridge.on("config", c._on_config); c.bridge.on("chat", c._on_chat); c.bridge.start()
time.sleep(0.6)
persona = {"name": "Mochi", "species": "Kitten", "voice": "a sassy kitten", "vibe": "Her own voice", "mood": "Cozy"}

# 1. config -> ollama, then a streamed chat reply
send({"type": "config", "provider": "ollama", "model": "", "keys": {}, "persona": persona}); time.sleep(0.3)
assert c.llm.settings.provider == "ollama"
send({"type": "chat", "id": "A1", "text": "how do I study for a chem exam?", "persona": persona})
chunks = wait(lambda m: m["type"] == "chat_chunk" and m["id"] == "A1" and m.get("done"))
text = "".join(m["text"] for m in inbox if m["type"] == "chat_chunk" and m["id"] == "A1")
assert text == "hi bestie 💗", text
print("1. streamed chat OK:", repr(text), "in", sum(1 for m in inbox if m['type']=='chat_chunk' and m['id']=='A1'), "chunks")

# 2. conversation memory: history now holds the exchange
assert len(c.llm._history) == 2 and c.llm._history[1]["content"] == "hi bestie 💗"
print("2. history kept OK")

# 3. brain failure -> falls back to the local brain, tells Swift
fail["on"] = True
send({"type": "chat", "id": "B2", "text": "hello", "persona": persona})
wait(lambda m: m["type"] == "chat_reply" and m["id"] == "B2")
wait(lambda m: m["type"] == "task_status" and "couldn't reach ollama" in m["text"])
print("3. fallback on provider failure OK")
fail["on"] = False

# 4. desktop chain from one sentence, with the focus timer delegated back to Swift
calls.clear()
send({"type": "chat", "id": "C3", "text": "Cranberry, open Notion and start my study playlist", "persona": persona})
r = wait(lambda m: m["type"] == "chat_reply" and m["id"] == "C3")[0]
assert ("open", "Notion") in calls and ("music", "study") in calls, calls
print("4. chain OK:", calls, "->", r["text"])
send({"type": "chat", "id": "D4", "text": "start a 25 minute focus", "persona": persona})
wait(lambda m: m["type"] == "command" and m["name"] == "focus" and m["minutes"] == 25)
print("5. focus command sent to Swift OK")

# 6. local provider = no LLM call at all
send({"type": "config", "provider": "local", "model": "", "keys": {}, "persona": persona}); time.sleep(0.2)
assert not c.llm.is_remote_or_llm()
send({"type": "chat", "id": "E5", "text": "thank you", "persona": persona})
r = wait(lambda m: m["type"] == "chat_reply" and m["id"] == "E5")[0]
print("6. local brain OK:", r["text"])

# 7. SSE parsers (OpenAI / Claude / Gemini) against canned streams
R = llm.LLMRouter()
def stream(lines): return [("data: " + json.dumps(l) + "\n").encode() for l in lines] + [b"data: [DONE]\n"]
assert "".join(ch["choices"][0]["delta"]["content"] for ch in R._sse_json(stream([{"choices":[{"delta":{"content":"a"}}]},{"choices":[{"delta":{"content":"b"}}]}]))) == "ab"
print("7. SSE parsing OK")
# 8. no key -> LLMError, never a crash
R.configure({"provider": "claude", "keys": {}})
try: list(R.stream("hi", persona)); raise SystemExit("should have failed")
except llm.LLMError as e: print("8. missing key handled OK:", e)
print("ALL PASSED")
