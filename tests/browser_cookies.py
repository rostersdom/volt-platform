#!/usr/bin/env python3
"""Session cookies: redirect capture, path scoping, HttpOnly invisibility and deletion."""
import http.server
from contextlib import contextmanager
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
HAVE_JS_DEPS = shutil.which("pkg-config") is not None and subprocess.run(
    ["pkg-config", "--exists", "duktape", "libseccomp"], check=False
).returncode == 0


@contextmanager
def loopback(routes):
    seen = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            seen.append((self.path, self.headers.get("Cookie")))
            if self.path in ("/echo", "/only/echo"):
                body = str(self.headers.get("Cookie")).encode()
                self.send_response(200)
                # The no-JS redirect tests load /echo as a document, so it must
                # look like HTML; the body is still the raw Cookie header.
                self.send_header("Content-Type", "text/html")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            body, headers, status = routes.get(self.path, (b"", {}, 404))
            if callable(body):
                body = body()
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            for name, value in headers.items():
                self.send_header(name, value)
            try:
                self.end_headers()
                self.wfile.write(body)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):
            pass

    with http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield f"http://127.0.0.1:{server.server_port}", seen
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


class BrowserCookies(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-cookies-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)
        cls.browser = cls.dir / "browser"
        built = subprocess.run([str(ROOT / "volt"), str(ROOT / "browser" / "browser.volt"),
                                "-o", str(cls.browser)],
                               cwd=ROOT, capture_output=True, text=True, timeout=90)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)
        if HAVE_JS_DEPS:
            built = subprocess.run(["make", f"BINDIR={cls.dir}", "-o", str(cls.browser),
                                    str(cls.dir / "volt-js")],
                                   cwd=ROOT, capture_output=True, text=True, timeout=90)
            if built.returncode:
                raise RuntimeError(built.stdout + built.stderr)

    def render(self, url, scripts=False):
        args = [str(self.browser), "--check"]
        if scripts:
            args.append("--js")
        return subprocess.run([*args, url], env={"PATH": ""}, capture_output=True,
                              text=True, timeout=20)

    def reference(self, text):
        path = self.dir / ("ref-" + str(abs(hash(text))) + ".html")
        path.write_text(f"<p>{text}</p>", encoding="utf-8")
        return self.render(str(path)).stdout

    def test_redirect_set_cookie_is_sent_on_the_next_hop(self):
        routes = {
            "/start": (b"", {"Set-Cookie": "session=abc; Path=/; HttpOnly",
                             "Location": "/echo"}, 302),
            "/echo": (b"<p>Echo</p>", {"Content-Type": "text/html"}, 200),
        }
        with loopback(routes) as (base, seen):
            result = self.render(base + "/start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertIn("pixel check passed", result.stdout)
        self.assertEqual([cookie for path, cookie in seen if path == "/echo"], ["session=abc"])

    def test_secure_cookie_is_ignored_over_http(self):
        routes = {
            "/start": (b"", {"Set-Cookie": "secure=1; Path=/; Secure",
                             "Location": "/echo"}, 302),
            "/echo": (b"<p>Echo</p>", {"Content-Type": "text/html"}, 200),
        }
        with loopback(routes) as (base, seen):
            result = self.render(base + "/start")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual([cookie for path, cookie in seen if path == "/echo"], [None])

    def test_path_attribute_scopes_the_cookie(self):
        routes = {
            "/out": (b"", {"Set-Cookie": "scoped=1; Path=/only",
                           "Location": "/echo"}, 302),
            "/in": (b"", {"Set-Cookie": "scoped=1; Path=/only",
                          "Location": "/only/echo"}, 302),
            "/echo": (b"<p>Echo</p>", {"Content-Type": "text/html"}, 200),
            "/only/echo": (b"<p>Echo</p>", {"Content-Type": "text/html"}, 200),
        }
        with loopback(routes) as (base, seen):
            outside = self.render(base + "/out")
            inside = self.render(base + "/in")
        self.assertEqual(outside.returncode, 0, outside.stderr)
        self.assertEqual(inside.returncode, 0, inside.stderr)
        self.assertEqual([cookie for path, cookie in seen if path == "/echo"], [None])
        self.assertEqual([cookie for path, cookie in seen if path == "/only/echo"], ["scoped=1"])

    @unittest.skipUnless(HAVE_JS_DEPS, "optional Duktape dependency not installed")
    def test_httponly_cookie_is_sent_to_fetch_but_invisible_to_scripts(self):
        page = b'''<p id="out">Fallback</p><script>
fetch('/echo').then(function (r) { return r.text(); }).then(function (t) {
  document.getElementById('out').textContent =
    (t === 'session=abc' && typeof document.cookie === 'undefined') ? 'OK' : 'BAD';
});
</script>'''
        routes = {
            "/page": (page, {"Content-Type": "text/html",
                             "Set-Cookie": "session=abc; Path=/; HttpOnly"}, 200),
        }
        with loopback(routes) as (base, seen):
            result = self.render(base + "/page", scripts=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout, self.reference("OK"))
        self.assertEqual([cookie for path, cookie in seen if path == "/echo"], ["session=abc"])

    @unittest.skipUnless(HAVE_JS_DEPS, "optional Duktape dependency not installed")
    def test_max_age_zero_deletes_the_cookie(self):
        page = b'''<p id="out">Fallback</p><script>
fetch('/echo').then(function (r) { return r.text(); }).then(function () {
  return fetch('/clear').then(function () {
    return fetch('/echo').then(function (r) { return r.text(); });
  }).then(function () {
    document.getElementById('out').textContent = 'OK';
  });
});
</script>'''
        routes = {
            "/page": (page, {"Content-Type": "text/html",
                             "Set-Cookie": "gone=1; Path=/"}, 200),
            "/clear": (b"", {"Set-Cookie": "gone=; Path=/; Max-Age=0"}, 200),
        }
        with loopback(routes) as (base, seen):
            result = self.render(base + "/page", scripts=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout, self.reference("OK"))
        self.assertEqual([cookie for path, cookie in seen if path == "/echo"], ["gone=1", None])


if __name__ == "__main__":
    unittest.main()
