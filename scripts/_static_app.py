"""Serve the TalkMate single-page app.

Bind address and port come from TALKMATE_HOST / TALKMATE_APP_PORT so that
scripts/start-all.ps1 can control them without rewriting this file.
"""
import http.server
import os
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parent.parent
ALLOWED = {"/", "/index.html", "/scripts/local-models.json"}
MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "application/javascript",
    ".css": "text/css",
    ".json": "application/json",
}


class H(http.server.BaseHTTPRequestHandler):
    def serve_path(self, rel):
        root = os.path.realpath(ROOT)
        full = os.path.realpath(os.path.join(root, rel.lstrip("/").replace("/", os.sep)))
        if full != root and not full.startswith(root + os.sep):
            self.send_error(404)
            return
        if not os.path.isfile(full):
            self.send_error(404)
            return
        body = Path(full).read_bytes()
        self.send_response(200)
        self.send_header("Content-Type", MIME.get(os.path.splitext(full)[1].lower(), "application/octet-stream"))
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/":
            path = "/index.html"
        if unquote(path) not in ALLOWED:
            self.send_error(404)
            return
        self.serve_path(path)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    host = os.environ.get("TALKMATE_HOST", "127.0.0.1")
    port = int(os.environ.get("TALKMATE_APP_PORT", "8080"))
    http.server.ThreadingHTTPServer.allow_reuse_address = True
    # Threading: one phone holding a connection must not block the PC's requests.
    with http.server.ThreadingHTTPServer((host, port), H) as httpd:
        print(f"TalkMate web -> http://{host}:{port}/", flush=True)
        httpd.serve_forever()
