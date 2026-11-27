#!/usr/bin/env python3
"""Self-check for QR pairing. Starts a throwaway server; does not touch config.json."""

from __future__ import annotations

import json
import os
import sys
import threading
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import qr
import server


def _get(url: str, token: str | None = None, timeout: float = 5):
    headers = {}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return resp.status, resp.read().decode(), dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(), dict(e.headers)


def main() -> None:
    grid = qr.matrix("lumen-pair-test")
    assert grid and len(grid) == len(grid[0])
    assert grid[0][0] is True and grid[0][6] is True and grid[6][0] is True
    picture = qr.svg("lumen-pair-test")
    assert picture.startswith("<svg") and 'd="' in picture

    token = "pair-test-token-not-real"
    payload = server.pairing_payload(["http://192.168.1.9:8787", "http://100.64.1.2:8787"], token)
    obj = json.loads(payload)
    assert obj["lumen"] == 1
    assert obj["token"] == token
    assert obj["urls"][0].startswith("http://")
    assert "provider_key" not in payload

    saved = dict(server.CONFIG)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), server.Handler)
    try:
        server.CONFIG["token"] = token
        server.CONFIG["port"] = httpd.server_address[1]
        server.CONFIG["provider_key"] = "xai-should-never-appear-on-pair-page"
        thread = threading.Thread(target=httpd.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{httpd.server_address[1]}"

        code, body, _headers = _get(base + "/pair")
        assert code == 200, (code, body[:200])
        assert token in body
        assert "xai-should-never-appear-on-pair-page" not in body
        assert "<svg" in body
        assert "/pair" not in json.loads(payload)["urls"][0]
        assert "Scan QR code" in body or "scan" in body.lower()

        code, body, _headers = _get(base + "/health")
        assert code == 401, (code, body)

        code, body, headers = _get(base + "/health", token=token)
        assert code == 200, (code, body)
        data = json.loads(body)
        assert data.get("ok") is True
        assert "LumenDesktop" in headers.get("Server", headers.get("server", ""))
    finally:
        httpd.shutdown()
        server.CONFIG.clear()
        server.CONFIG.update(saved)

    print("ok")


if __name__ == "__main__":
    main()
