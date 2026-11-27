#!/usr/bin/env python3
"""Small Lumen desktop server.

Stdlib only. Listens on the LAN, checks the iPhone app's Bearer token, and
forwards text to one AI provider (or to a local Ollama). Speech stays on the
phone. The provider key never leaves this computer.

    python3 desktop/server.py
"""

from __future__ import annotations

import json
import os
import secrets
import socket
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import actions

DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_PATH = os.path.join(DIR, "config.json")
SYSTEM = "You are Lumen, a helpful voice assistant. " + actions.INSTRUCTION + " " + actions.shell_hint()
HISTORY: list[dict] = []
LOCK = threading.Lock()


class _Flight:
    """One provider call shared by overlapping copies of the same question."""

    def __init__(self) -> None:
        self.done = threading.Event()
        self.say = ""
        self.action: dict | None = None
        self.error: BaseException | None = None


INFLIGHT: dict[str, _Flight] = {}

PROVIDERS = {
    "grok": ("Grok", "https://api.x.ai/v1/chat/completions", "grok-4"),
    "claude": ("Claude", "https://api.anthropic.com/v1/messages", "claude-sonnet-4-5"),
    "gemini": (
        "Gemini",
        "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent",
        "gemini-2.5-flash",
    ),
    "groq": ("Groq", "https://api.groq.com/openai/v1/chat/completions", "llama-3.3-70b-versatile"),
    "openrouter": ("OpenRouter", "https://openrouter.ai/api/v1/chat/completions", "meta-llama/llama-3.3-70b-instruct"),
}


def host_os() -> str:
    """linux or windows for this computer. Other systems report nothing."""
    return actions.host_label()


def detect(key: str) -> str | None:
    k = (key or "").strip()
    if k.startswith("xai-"):
        return "grok"
    if k.startswith("sk-ant-"):
        return "claude"
    if k.startswith("AIza"):
        return "gemini"
    if k.startswith("gsk_"):
        return "groq"
    if k.startswith("sk-or-"):
        return "openrouter"
    return None


def load_config() -> dict:
    cfg = {
        "token": "",
        "provider_key": "",
        "backend": "auto",
        "ollama_url": "http://127.0.0.1:11434",
        "ollama_model": "llama3.2",
        "port": 8787,
    }
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, encoding="utf-8") as f:
                saved = json.load(f)
            if isinstance(saved, dict):
                cfg.update(saved)
        except (OSError, json.JSONDecodeError):
            pass
    if not cfg.get("token"):
        cfg["token"] = secrets.token_urlsafe(24)
        save_config(cfg)
    if os.environ.get("LUMEN_TOKEN"):
        cfg["token"] = os.environ["LUMEN_TOKEN"]
    if os.environ.get("LUMEN_PROVIDER_KEY"):
        cfg["provider_key"] = os.environ["LUMEN_PROVIDER_KEY"]
    if os.environ.get("LUMEN_PORT"):
        try:
            cfg["port"] = int(os.environ["LUMEN_PORT"])
        except ValueError:
            pass
    if os.environ.get("LUMEN_OLLAMA_URL"):
        cfg["ollama_url"] = os.environ["LUMEN_OLLAMA_URL"]
    if os.environ.get("LUMEN_OLLAMA_MODEL"):
        cfg["ollama_model"] = os.environ["LUMEN_OLLAMA_MODEL"]
    return cfg


def save_config(cfg: dict) -> None:
    # The provider key stays in this file (or in the environment). Never print it.
    tmp = CONFIG_PATH + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(
            {
                "token": cfg.get("token", ""),
                "provider_key": cfg.get("provider_key", ""),
                "backend": cfg.get("backend", "auto"),
                "ollama_url": cfg.get("ollama_url", "http://127.0.0.1:11434"),
                "ollama_model": cfg.get("ollama_model", "llama3.2"),
                "port": int(cfg.get("port", 8787)),
            },
            f,
            indent=2,
        )
        f.write("\n")
    os.replace(tmp, CONFIG_PATH)
    try:
        os.chmod(CONFIG_PATH, 0o600)
    except OSError:
        pass


CONFIG = load_config()


def provider_key() -> str:
    return (os.environ.get("LUMEN_PROVIDER_KEY") or CONFIG.get("provider_key") or "").strip()


def backend() -> tuple[str, str]:
    """Return (display name, kind) where kind is a provider id or 'ollama'."""
    forced = (CONFIG.get("backend") or "auto").strip().lower()
    key = provider_key()
    if forced == "ollama":
        return "Ollama", "ollama"
    kind = detect(key) if key else None
    if kind and forced in ("auto", kind):
        return PROVIDERS[kind][0], kind
    if forced in PROVIDERS and key:
        return PROVIDERS[forced][0], forced
    if kind:
        return PROVIDERS[kind][0], kind
    return "Ollama", "ollama"


def lan_ips() -> list[str]:
    ips = []
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ips.append(s.getsockname()[0])
        s.close()
    except OSError:
        pass
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ip = info[4][0]
            if ip not in ips and not ip.startswith("127."):
                ips.append(ip)
    except OSError:
        pass
    return ips or ["127.0.0.1"]


def public_urls(port: int) -> list[str]:
    """Addresses the phone can try, LAN first. 127.0.0.1 is last-resort only."""
    urls = [f"http://{ip}:{port}" for ip in lan_ips() if not ip.startswith("127.")]
    if not urls:
        urls = [f"http://127.0.0.1:{port}"]
    return urls


def pairing_payload(urls: list[str], token: str) -> str:
    """Compact JSON the iPhone app scans. Token never goes to a third-party QR API."""
    return json.dumps({"lumen": 1, "urls": list(urls), "token": token}, separators=(",", ":"))


def _html_esc(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )


def post_json(url: str, payload: dict, headers: dict, timeout: int = 60) -> dict:
    data = json.dumps(payload).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            body = resp.read()
    except urllib.error.HTTPError as e:
        # Don't include the request, the key, or the body in the raised text.
        if e.code in (401, 403):
            raise RuntimeError("rejected") from None
        if e.code == 400:
            raise RuntimeError("badrequest") from None
        raise RuntimeError("unreachable") from None
    except (urllib.error.URLError, TimeoutError, OSError):
        raise RuntimeError("unreachable") from None
    try:
        obj = json.loads(body.decode() or "{}")
    except json.JSONDecodeError:
        raise RuntimeError("unreachable") from None
    return obj if isinstance(obj, dict) else {}


def answer(text: str) -> tuple[str, dict | None]:
    """Reuse an identical question that is already running instead of asking twice."""
    key = text.strip()
    with LOCK:
        flight = INFLIGHT.get(key)
        if flight is None:
            flight = _Flight()
            INFLIGHT[key] = flight
            owner = True
        else:
            owner = False
    if not owner:
        flight.done.wait()
        if flight.error is not None:
            raise flight.error
        return flight.say, flight.action
    try:
        flight.say, flight.action = forward(key)
        return flight.say, flight.action
    except BaseException as exc:
        flight.error = exc
        raise
    finally:
        flight.done.set()
        with LOCK:
            if INFLIGHT.get(key) is flight:
                del INFLIGHT[key]


def forward(text: str) -> tuple[str, dict | None]:
    _name, kind = backend()
    with LOCK:
        history = list(HISTORY)
    messages = [{"role": "system", "content": SYSTEM}]
    messages += history
    messages.append({"role": "user", "content": text})
    if kind == "ollama":
        raw, proposal = ollama(messages)
    else:
        raw, proposal = provider_chat(kind, messages)
    action = None
    if proposal:
        say, action = actions.queued_reply(proposal["title"], proposal["command"])
    else:
        if not raw:
            raise RuntimeError("empty")
        say = raw
    with LOCK:
        HISTORY.append({"role": "user", "content": text})
        HISTORY.append({"role": "assistant", "content": say})
        del HISTORY[:-40]
    return say, action


def provider_chat(kind: str, messages: list[dict]) -> tuple[str, dict | None]:
    _title, url, model = PROVIDERS[kind]
    key = provider_key()
    if not key:
        raise RuntimeError("nokey")
    headers = {"Content-Type": "application/json", "User-Agent": "LumenVoice"}
    if kind == "claude":
        headers["x-api-key"] = key
        headers["anthropic-version"] = "2023-06-01"
    elif kind == "gemini":
        headers["x-goog-api-key"] = key
    else:
        headers["Authorization"] = "Bearer " + key
    payload = _chat_payload(kind, model, messages)
    try:
        obj = post_json(url, actions.tool_payload(kind, payload), headers)
    except RuntimeError as exc:
        if str(exc) != "badrequest":
            raise
        obj = post_json(url, payload, headers)
    text = _reply_text(kind, obj)
    proposal = actions.proposal_from_response(kind, obj, text)
    if not text and not proposal:
        raise RuntimeError("empty")
    return text, proposal


def _chat_payload(kind: str, model: str, messages: list[dict]) -> dict:
    if kind == "claude":
        user_msgs = [m for m in messages if m["role"] != "system"]
        return {"model": model, "max_tokens": 400, "system": SYSTEM, "messages": user_msgs}
    if kind == "gemini":
        contents = [
            {"role": "user" if m["role"] == "user" else "model", "parts": [{"text": m["content"]}]}
            for m in messages
            if m["role"] != "system"
        ]
        return {
            "systemInstruction": {"parts": [{"text": SYSTEM}]},
            "contents": contents,
            "generationConfig": {"maxOutputTokens": 400},
        }
    return {"model": model, "messages": messages, "max_tokens": 400}


def _reply_text(kind: str, obj: dict) -> str:
    if kind == "claude":
        parts = obj.get("content") or []
        text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    elif kind == "gemini":
        candidates = obj.get("candidates") or []
        parts = (((candidates[0] or {}).get("content") or {}).get("parts") or []) if candidates else []
        text = "".join(p.get("text", "") for p in parts if isinstance(p, dict))
    else:
        choices = obj.get("choices") or []
        message = (choices[0] or {}).get("message") if choices else {}
        text = (message or {}).get("content") or ""
    return (text or "").strip()


SUMMARY_SYSTEM = (
    "Turn this finished computer command into one or two spoken sentences. "
    "Include the key numbers. Skip column headings. "
    "If it was only partly successful, say what worked and mention the problem in a few words. "
    "Do not propose another command."
)


def spoken_summary(title: str, command: str, output: str, status: str, budget: float = 4) -> str | None:
    """Ask the configured provider. Returns None so the caller can use a local summary."""
    if budget < 1.5:
        return None
    user = f"Title: {title}\nCommand: {command}\nStatus: {status}\nOutput:\n{(output or '')[:1500]}"
    timeout = max(2, int(round(budget)))
    try:
        _name, kind = backend()
        if kind == "ollama":
            url = (CONFIG.get("ollama_url") or "http://127.0.0.1:11434").rstrip("/") + "/api/chat"
            payload = {
                "model": CONFIG.get("ollama_model") or "llama3.2",
                "messages": [
                    {"role": "system", "content": SUMMARY_SYSTEM},
                    {"role": "user", "content": user},
                ],
                "stream": False,
            }
            obj = post_json(url, payload, {"Content-Type": "application/json", "User-Agent": "LumenVoice"}, timeout)
            text = ((obj.get("message") or {}).get("content") or "").strip()
        else:
            _title, url, model = PROVIDERS[kind]
            key = provider_key()
            if not key:
                return None
            headers = {"Content-Type": "application/json", "User-Agent": "LumenVoice"}
            if kind == "claude":
                headers["x-api-key"] = key
                headers["anthropic-version"] = "2023-06-01"
                payload = {
                    "model": model,
                    "max_tokens": 120,
                    "system": SUMMARY_SYSTEM,
                    "messages": [{"role": "user", "content": user}],
                }
            elif kind == "gemini":
                headers["x-goog-api-key"] = key
                payload = {
                    "systemInstruction": {"parts": [{"text": SUMMARY_SYSTEM}]},
                    "contents": [{"role": "user", "parts": [{"text": user}]}],
                    "generationConfig": {"maxOutputTokens": 120},
                }
            else:
                headers["Authorization"] = "Bearer " + key
                payload = {
                    "model": model,
                    "messages": [
                        {"role": "system", "content": SUMMARY_SYSTEM},
                        {"role": "user", "content": user},
                    ],
                    "max_tokens": 120,
                }
            obj = post_json(url, payload, headers, timeout)
            text = _reply_text(kind, obj)
    except Exception:
        return None
    if not text or text.startswith("{") or "propose_command" in text:
        return None
    return text


def _speak_result(title: str, command: str, output: str, status: str, budget: float = 4) -> str | None:
    return spoken_summary(title, command, output, status, budget)


actions.SPEAK = _speak_result


def ollama(messages: list[dict]) -> tuple[str, dict | None]:
    url = (CONFIG.get("ollama_url") or "http://127.0.0.1:11434").rstrip("/") + "/api/chat"
    payload = {
        "model": CONFIG.get("ollama_model") or "llama3.2",
        "messages": messages,
        "stream": False,
    }
    obj = post_json(url, payload, {"Content-Type": "application/json", "User-Agent": "LumenVoice"})
    text = ((obj.get("message") or {}).get("content") or "").strip()
    proposal = actions.proposal_from_text(text)
    if not text and not proposal:
        raise RuntimeError("empty")
    return text, proposal


class Handler(BaseHTTPRequestHandler):
    server_version = "LumenDesktop/1.0"
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        # Don't log URLs or headers; a misconfigured client could put a key there.
        return

    def _json(self, code: int, obj: dict) -> None:
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        if host_os():
            self.send_header("X-Server-OS", host_os())
        self.end_headers()
        self.wfile.write(body)

    def _authed(self) -> bool:
        header = self.headers.get("Authorization", "")
        token = header[7:].strip() if header.lower().startswith("bearer ") else ""
        expected = str(CONFIG.get("token") or "")
        if token and expected and secrets.compare_digest(token, expected):
            return True
        self._json(401, {"error": "unauthorized"})
        return False

    def _read(self) -> bytes:
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _html(self, code: int, body: str) -> None:
        raw = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(raw)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(raw)

    def _pair_page(self) -> None:
        port = int(CONFIG.get("port") or 8787)
        token = str(CONFIG.get("token") or "")
        urls = public_urls(port)
        payload = pairing_payload(urls, token)
        try:
            import qr

            picture = qr.svg(payload)
        except Exception:
            picture = (
                "<p class='warn'>QR drawing failed on this computer. "
                "Copy the URL and token into the app instead.</p>"
            )
        url_rows = "".join(
            f"<li><code id='url-{i}'>{_html_esc(u)}</code></li>" for i, u in enumerate(urls)
        )
        self._html(
            200,
            PAIR_PAGE.format(
                svg=picture,
                urls=url_rows,
                token=_html_esc(token),
                payload=_html_esc(payload),
            ),
        )

    def do_GET(self):
        path = self.path.split("?")[0]
        if len(path) > 1 and path.endswith("/"):
            path = path[:-1]
        if path == "/pair":
            return self._pair_page()
        if not self._authed():
            return
        os_name = host_os()
        if path in ("/health", "/v1/health", "/info", "/v1/info"):
            self._json(200, {"ok": True, "os": os_name})
            return
        if path in ("/models", "/v1/models"):
            self._json(200, {
                "object": "list",
                "data": [],
                "os": os_name,
                "metadata": {"os": os_name},
            })
            return
        if path.startswith("/api/status"):
            name, _kind = backend()
            # Speaker ID is not implemented in this small server.
            self._json(200, {"ok": True, "name": name, "voiceLock": False, "os": os_name})
            return
        if path == "/api/actions":
            self._json(200, {"actions": actions.QUEUE.pending()})
            return
        if path.startswith("/api/action/"):
            ident, _op = _action_path(path)
            item = actions.QUEUE.get(ident)
            if not item:
                self._json(404, {"error": "That request is no longer waiting."})
                return
            self._json(200, item)
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        if not self._authed():
            return
        path = self.path.split("?")[0]
        try:
            if path.startswith("/api/transcribe"):
                return self._transcribe()
            if path.startswith("/api/text") or path.startswith("/api/ask"):
                return self._text()
            if path.startswith("/api/reset"):
                self._read()
                with LOCK:
                    HISTORY.clear()
                return self._json(200, {"ok": True})
            if path.startswith("/api/action/"):
                self._read()
                return self._action(path)
        except RuntimeError as e:
            code = {"rejected": 401, "nokey": 400, "empty": 502}.get(str(e), 502)
            message = {
                "rejected": "The provider rejected the key on this computer.",
                "nokey": "Set LUMEN_PROVIDER_KEY, or run Ollama, on this computer.",
                "unreachable": "Couldn't reach the assistant from this computer.",
                "empty": "The assistant sent an empty reply.",
            }.get(str(e), "The assistant didn't answer.")
            return self._json(code, {"error": message})
        self._json(404, {"error": "not found"})

    def _transcribe(self) -> None:
        """Discard the recording. This process has no speech engine."""
        raw = self._read()
        if not raw:
            self._json(400, {"error": "empty"})
            return
        self._json(501, {"error": "This server can't turn a recording into text."})

    def _text(self) -> None:
        raw = self._read()
        ctype = self.headers.get("Content-Type", "")
        if "json" in ctype:
            try:
                text = (json.loads(raw or b"{}").get("text") or "")
            except json.JSONDecodeError:
                text = ""
        else:
            text = raw.decode("utf-8", "replace")
        text = text.strip()[:4000]
        if not text:
            self._json(400, {"error": "empty"})
            return
        say, action = answer(text)
        body = {"say": say, "saved": False, "private": False}
        if action:
            body["action"] = action
        self._json(200, body)

    def _action(self, path: str) -> None:
        ident, op = _action_path(path)
        if op == "approve":
            item = actions.QUEUE.approve(ident)
        elif op == "cancel":
            item = actions.QUEUE.cancel(ident)
        else:
            item = None
        if not item:
            self._json(404, {"error": "That request is no longer waiting."})
            return
        self._json(200, item)


def _action_path(path: str) -> tuple[str, str]:
    rest = path.split("?", 1)[0]
    if len(rest) > 1 and rest.endswith("/"):
        rest = rest[:-1]
    tail = rest[len("/api/action/"):] if rest.startswith("/api/action/") else ""
    parts = [part for part in tail.split("/") if part]
    if not parts:
        return "", ""
    return parts[0], (parts[1] if len(parts) > 1 else "")


PAIR_PAGE = """<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Pair Lumen Voice</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin: 0; font-family: system-ui, sans-serif; background: #140e08; color: #f4ead8;
         display: flex; justify-content: center; padding: 32px 16px; }}
  main {{ max-width: 36rem; }}
  h1 {{ font-size: 1.5rem; font-weight: 650; color: #ffc24a; margin: 0 0 8px; }}
  p, li {{ line-height: 1.45; }}
  .qr {{ background: #fff; padding: 16px; border-radius: 12px; display: inline-block; margin: 12px 0; }}
  .qr svg {{ display: block; }}
  code, pre {{ font-family: ui-monospace, monospace; background: #24180f; padding: 2px 6px;
               border-radius: 6px; word-break: break-all; }}
  pre {{ padding: 10px 12px; overflow-x: auto; }}
  .warn {{ color: #ffb4a2; }}
  button {{ background: #ffc24a; color: #1a1208; border: 0; border-radius: 8px; padding: 6px 10px;
            font-weight: 650; cursor: pointer; margin-left: 8px; }}
  footer {{ margin-top: 24px; color: #b9a894; font-size: 0.9rem; }}
</style>
</head>
<body>
<main>
  <h1>Pair Lumen Voice</h1>
  <p>On your iPhone, open Lumen Voice, choose <strong>Run your own server</strong>, and tap <strong>Scan QR code</strong>. Point the camera at this square. The address and token stay on this computer until the phone saves them.</p>
  <div class="qr">{svg}</div>
  <p>Or type these by hand:</p>
  <ul>{urls}</ul>
  <p>Token <code id="token">{token}</code>
     <button type="button" onclick="copy('token')">Copy token</button></p>
  <p>Raw pairing payload (same as the QR):</p>
  <pre id="payload">{payload}</pre>
  <footer>Anyone on this network who opens this page can see the token. Don't publish this page on the open internet. The provider key is not shown here.</footer>
</main>
<script>
function copy(id) {{
  const el = document.getElementById(id);
  const text = el ? el.innerText : "";
  if (navigator.clipboard && text) navigator.clipboard.writeText(text);
}}
</script>
</body>
</html>
"""


def main() -> None:
    port = int(CONFIG.get("port") or 8787)
    name, kind = backend()
    httpd = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print("Lumen desktop server")
    print(f"  Assistant: {name}")
    if kind != "ollama" and not provider_key():
        print("  No provider key yet. Set LUMEN_PROVIDER_KEY or provider_key in desktop/config.json.")
        print("  Until then, text is sent to local Ollama if it is running.")
    print()
    print("Pair the iPhone: open this page on this computer and scan the QR in Lumen Voice:")
    print()
    for url in public_urls(port):
        print(f"  {url}/pair")
    print()
    print("Or in the app choose Run your own server and enter:")
    print()
    for url in public_urls(port):
        print(f"  URL    {url}")
    print(f"  Token  {CONFIG.get('token')}")
    print()
    print("Away from home, publish this server with Tailscale (tailscale serve) or another")
    print("HTTPS address, and use that URL in the app. Don't put it on the open internet")
    print("without HTTPS. The provider key stays in desktop/config.json or LUMEN_PROVIDER_KEY.")
    print()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
        sys.exit(0)


if __name__ == "__main__":
    main()
