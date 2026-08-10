#!/usr/bin/env python3
"""Run-scoped User Center fixture for P6 cookie identity and entitlement calls."""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from http.cookies import SimpleCookie


OWNER_A = os.environ.get("P6_OWNER_A", "")
OWNER_B = os.environ.get("P6_OWNER_B", "")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        return

    def _owner(self) -> str | None:
        cookie = SimpleCookie()
        cookie.load(self.headers.get("Cookie", ""))
        selector = cookie.get("p6_owner")
        if selector and selector.value == "a":
            return OWNER_A
        if selector and selector.value == "b":
            return OWNER_B
        return None

    def _json(self, status: int, value: object) -> None:
        payload = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:  # noqa: N802
        if self.path == "/health":
            self._json(200, {"status": "ok"})
            return
        owner = self._owner()
        if not owner:
            self._json(401, {"code": "UNAUTHENTICATED"})
            return
        if self.path.startswith("/ucenter/api/userInfo"):
            self._json(200, {"code": "SUCCESS", "data": {"id": owner, "name": owner, "roles": ["pro"]}})
            return
        if self.path.startswith("/ucenter/api/subscription"):
            self._json(200, {"code": "SUCCESS", "data": []})
            return
        self._json(404, {"code": "NOT_FOUND"})


if not OWNER_A or not OWNER_B:
    raise SystemExit("P6 owner configuration is required")
ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
