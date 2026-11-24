#!/usr/bin/env python3
"""Run the VOLT navigation regression against a loopback HTTP server."""
import http.server
import os
from pathlib import Path
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURE = ROOT / "tests/fixtures/browser_navigation.volt"


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.server.requests.append(self.path)
        if self.path == "/slow":
            name = "slow-key" if self.server.requests.count(self.path) == 1 else "slow-click"
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.send_header("Content-Length", "1024")
            self.end_headers()
            self.wfile.write(b"<p>Partial")
            (self.server.test_directory / name).touch()
            self.connection.settimeout(3)
            if self.connection.recv(1) == b"":
                (self.server.test_directory / (name + "-closed")).touch()
            return
        if self.path == "/budget-start":
            time.sleep(0.9)
            status, body = 302, b""
        elif self.path == "/budget-end":
            time.sleep(0.9)
            status, body = 200, b"<p>Too late</p>"
        elif self.path == "/start":
            status, body = 302, b""
        elif self.path == "/docs/section/index?q=/search/path":
            status, body = 200, (b'<body><p><a href="#%D1%8F">Jump</a></p>' + b"<p>Line</p>" * 59
                                 + b'<p id="&#x44f;"><a href="../next?x=1&amp;y=2">&#1071;</a>Q</p></body>')
        elif self.path == "/docs/next?x=1&y=2":
            status, body = 200, (b'<style>body { background-color: #224466; display: grid } '
                                 b'p { color: #112244 !important }</style>'
                                 b'<body style="background-color: #33aa55; background: linear-gradient(red, blue)">'
                                 b'<p style="color: red">Destination</p></body>')
        elif self.path == "/":
            status, body = 200, (b'<p><a href="/#topic">Jump</a></p>' + b"<p>Line</p>" * 59
                                 + b'<p id="topic">Topic</p>')
        elif self.path == "/broken" and self.server.requests.count(self.path) == 2:
            status, body = 200, b'<title>Recovered</title><p>Recovered</p>'
        else:
            status, body = 200, b"<!-- unterminated"
        self.send_response(status)
        if status == 302:
            target = "/budget-end" if self.path == "/budget-start" else "/docs/section/index?q=/search/path"
            self.send_header("Location", target)
        self.send_header("Content-Type", "text/html")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except BrokenPipeError:
            if self.path != "/budget-end":
                raise

    def log_message(self, *_):
        pass


class ControllerIntegration(unittest.TestCase):
    def test_follow_relative_link_after_redirect_and_keep_page_on_failure(self):
        with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server, tempfile.TemporaryDirectory(prefix="volt-browser-controller-") as tmp:
            server.requests = []
            server.test_directory = Path(tmp)
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            try:
                binary = Path(tmp) / "browser-navigation"
                built = subprocess.run([str(ROOT / "volt"), str(FIXTURE), "-o", str(binary)],
                                       cwd=ROOT, capture_output=True, text=True, timeout=30)
                self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
                base = f"http://127.0.0.1:{server.server_port}"
                (Path(tmp) / "index.html").write_text('<p><a href="chapter%202%23draft.html#end">Chapter</a></p>', encoding="utf-8")
                (Path(tmp) / "chapter 2#draft.html").write_text('<p>Line</p>' * 60 + '<p id="end">End</p>', encoding="utf-8")
                (Path(tmp) / "index.html#draft").write_text('<p style="background: #224466">Draft</p>', encoding="utf-8")
                (Path(tmp) / "wide.html").write_text(
                    '<title>Wide test</title><p><a href="#details">Я</a>Q</p><p>' + "abcdefg " * 72
                    + '</p><p id="details">Details</p>' + "<p>Line</p>" * 60, encoding="utf-8")
                (Path(tmp) / "bridge.html").write_text('<p><a href="wide.html">Wide</a></p>', encoding="utf-8")
                (Path(tmp) / "overflow.html").write_text("<p>" + "a " * 132_000 + "</p>", encoding="utf-8")
                run = subprocess.run([str(binary), base, tmp], cwd=ROOT, capture_output=True,
                                     text=True, timeout=15, env={**os.environ, "SDL_VIDEODRIVER": "dummy"})
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                start = "/docs/section/index?q=/search/path"
                destination = "/docs/next?x=1&y=2"
                self.assertEqual(server.requests, ["/start", start, destination, start, destination,
                                                     destination, "/broken", "/broken", "/", "/slow", "/slow",
                                                     "/budget-start", "/budget-end"])
            finally:
                server.shutdown()
                thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
