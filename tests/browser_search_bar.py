#!/usr/bin/env python3
"""Address-bar web search: provider override, URL detection and request bytes."""
import http.server
from pathlib import Path
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"


class BrowserSearchBar(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-search-bar-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)
        cls.browser = cls.dir / "browser"
        built = subprocess.run([str(ROOT / "volt"), str(ROOT / "browser" / "browser.volt"),
                                "-o", str(cls.browser)],
                               cwd=ROOT, capture_output=True, text=True, timeout=90)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)
        cls.fixture = cls.dir / "search-bar"
        built = subprocess.run([str(ROOT / "volt"), str(FIXTURES / "browser_search_bar.volt"),
                                "-o", str(cls.fixture)],
                               cwd=ROOT, capture_output=True, text=True, timeout=60)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)

    def convert(self, value, base="https://search.example/?q="):
        return subprocess.run([str(self.fixture), value],
                              env={"PATH": "", "VOLT_SEARCH_URL": base},
                              capture_output=True, text=True, timeout=10)

    def test_typed_text_becomes_a_search_url(self):
        result = self.convert("hello world + тест", "https://search.example/?q=")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout,
                         "search https://search.example/?q=hello+world+%2B+%D1%82%D0%B5%D1%81%D1%82\n")

    def test_missing_or_malformed_override_uses_the_built_in_provider(self):
        result = self.convert("hello", "not-a-url")
        self.assertEqual(result.stdout, "search https://html.duckduckgo.com/html/?q=hello\n")

    def test_urls_and_paths_are_never_rewritten(self):
        for value in ("https://example.org/a?b=1", "http://127.0.0.1:8080/", "/etc/hosts",
                      "./notes.html", "../up", "example.org", "localhost:8080", "127.0.0.1"):
            with self.subTest(value=value):
                result = self.convert(value)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(result.stdout, "address\n")

    def test_explicit_search_flag_sends_the_encoded_query(self):
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                body = b"<p>Search results</p>"
                self.send_response(200)
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, *_):
                pass

        with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
            thread = threading.Thread(target=server.serve_forever, daemon=True)
            thread.start()
            base = f"http://127.0.0.1:{server.server_port}/search?q="
            try:
                result = subprocess.run([str(self.browser), "--check", "--search", "hello world"],
                                        env={"PATH": "", "VOLT_SEARCH_URL": base},
                                        capture_output=True, text=True, timeout=20)
            finally:
                server.shutdown()
                server.server_close()
                thread.join(timeout=2)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("pixel check passed", result.stdout)
        self.assertEqual(requests, ["/search?q=hello+world"])


if __name__ == "__main__":
    unittest.main()
