#!/usr/bin/env python3
"""Local helper server for the EDA Playground runs of the release skill.

Serves the bundle directory (tools/bundle_for_eda.py output) on
http://127.0.0.1:8765 with a CORS header, so a page on edaplayground.com can
fetch `<bundle>/eda_tb.sv` with fetch(). A POST to /log/<name> stores the
request body as <logs>/<name>.txt: the in-page runner (eda_runner.js) posts
every Playground log there, which keeps the logs greppable on disk and out of
the Claude in Chrome tool output.

Usage:
    python3 .claude/skills/release/scripts/eda_server.py [bundle_dir] [logs_dir]

Defaults: bundle_dir = eda_bundle, logs_dir = sim/eda_playground/logs (both
relative to the repo root, both gitignored). Runs until killed:
    fuser -k 8765/tcp
"""
import http.server
import os
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
ROOT = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "eda_bundle"
LOGS = Path(sys.argv[2]) if len(sys.argv) > 2 else REPO / "sim" / "eda_playground" / "logs"
PORT = 8765

LOGS.mkdir(parents=True, exist_ok=True)
os.chdir(ROOT)


class Handler(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Private-Network", "true")
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_OPTIONS(self):
        self.send_response(204)
        self.end_headers()

    def do_POST(self):
        m = re.fullmatch(r"/log/([A-Za-z0-9_.-]+)", self.path)
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        if not m:
            self.send_response(404)
            self.end_headers()
            return
        (LOGS / (m.group(1) + ".txt")).write_bytes(body)
        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"ok")

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"eda_server: serving {ROOT} on http://127.0.0.1:{PORT}, logs -> {LOGS}")
    http.server.ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
