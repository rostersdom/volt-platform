#!/usr/bin/env python3
"""Opt-in script execution, DOM IPC, isolation and browser integration."""
import http.server
from contextlib import contextmanager
import os
from pathlib import Path
import shutil
import socket
import struct
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
HAVE_JS_DEPS = shutil.which("pkg-config") is not None and subprocess.run(
    ["pkg-config", "--exists", "duktape", "libseccomp"], check=False
).returncode == 0
QUICKJS_DIR = os.environ.get("QUICKJS_DIR")
HAVE_SECCOMP = shutil.which("pkg-config") is not None and subprocess.run(
    ["pkg-config", "--exists", "libseccomp"], check=False
).returncode == 0


@contextmanager
def loopback(routes):
    requests = []

    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            requests.append(self.path)
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
            yield f"http://127.0.0.1:{server.server_port}", requests
        finally:
            server.shutdown()
            thread.join(timeout=2)


def html_response(text, **headers):
    return text.encode("utf-8"), {"Content-Type": "text/html", **headers}, 200


def js_response(code, mime="application/javascript"):
    return code, {"Content-Type": mime} if mime is not None else {}, 200


def redirect(location):
    return b"", {"Location": location}, 302


class BrowserJavaScriptSuite:
    worker_name = "volt-js"

    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="volt-js-")
        cls.addClassCleanup(temporary.cleanup)
        cls.dir = Path(temporary.name)
        install = cls.dir / "toolchain"
        install.mkdir()
        for name in ("vstd", "browser"):
            (install / name).symlink_to(ROOT / name, target_is_directory=True)
        cls.compiler = install / "volt"
        cls.viewer = cls.dir / "browser"
        subprocess.run([str(ROOT / "bootstrap/volt-linux-x86_64"), "compiler/volt_main.volt", "-o", str(cls.compiler)],
                       cwd=ROOT, check=True, timeout=90)
        subprocess.run([str(cls.compiler), "browser/browser.volt", "-o", str(cls.viewer)], cwd=ROOT, check=True, timeout=30)
        target = cls.dir / cls.worker_name if cls.worker_name == "volt-js" else "browser-js-modern"
        # The worker targets need no rebuild of the shared ./volt.
        subprocess.run(["make", f"BINDIR={cls.dir}", "-o", str(cls.viewer), str(target)],
                       cwd=ROOT, check=True, timeout=90)

    def build_fixture(self):
        fixture = self.dir / "javascript-fixture"
        if not fixture.exists():
            subprocess.run([str(self.compiler), str(FIXTURES / "browser_javascript.volt"), "-o", str(fixture)],
                           cwd=ROOT, check=True, timeout=30)
        return fixture

    def html(self, name, text):
        path = self.dir / (name + ".html")
        path.write_text(text, encoding="utf-8")
        return path

    def render(self, path, *, scripts=False, viewer=None):
        args = [str(viewer or self.viewer), "--check"]
        if scripts:
            args.append("--js")
        return subprocess.run([*args, str(path)], env={"PATH": ""}, cwd=self.dir,
                              text=True, capture_output=True, timeout=4, check=True)

    def test_inline_scripts_run_in_order_and_text_never_becomes_markup(self):
        source = self.html("inline", '''<p id="out">Fallback</p>
<script>'use strict'; var answer = 6 * 7;</script>
<script type="application/json">throw new Error('not script')</script>
<template><script>throw new Error('inert')</script></template>
<noscript><script>throw new Error('inert')</script></noscript>
<title>Title with a literal <script>throw new Error('inert title')</script></title>
<style>textarea { display: none }</style>
<textarea><script>throw new Error('inert textarea')</script></textarea>
<script src="unused.js">throw new Error('external')</script>
<script type="module">throw new Error('module')</script>
<script>
if (typeof require !== 'undefined' || typeof process !== 'undefined' ||
    typeof fetch !== 'undefined' || typeof Duktape !== 'undefined') throw new Error('host API');
if (new Date(0).getTimezoneOffset() !== 0 || !String(new Date(0))) throw new Error('clock');
document.addEventListener('DOMContentLoaded', function () {
    document.querySelector('#out').textContent = '<b>Я🙂 & ' + answer + '</b>';
});
</script>
<script>document.getElementById('out').textContent = 'unterminated does not run';''')
        rendered = self.render(source, scripts=True)
        literal = self.html("literal", "<p>&lt;b&gt;Я🙂 &amp; 42&lt;/b&gt;</p>")
        baseline = self.html("static", "<p>Fallback</p>")
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(literal).stdout)
        self.assertEqual(self.render(source).stdout, self.render(baseline).stdout)
        self.assertNotEqual(rendered.stdout, self.render(baseline).stdout)

    def test_same_origin_script_is_only_requested_with_opt_in(self):
        routes = {
            "/page": html_response('<p id="out">Fallback</p><script src="/script.js"></script>'),
            "/script.js": js_response((FIXTURES / "browser_javascript_external.js").read_bytes(),
                                      'Text/JavaScript; charset="UTF-8"'),
        }
        with loopback(routes) as (base, requests):
            disabled = self.render(f"{base}/page")
            self.assertEqual(requests, ["/page"])
            rendered = self.render(f"{base}/page", scripts=True)
            local = self.html("local-script", f'<p id="out">Fallback</p><script src="{base}/script.js"></script>')
            local_rendered = self.render(local, scripts=True)
        self.assertEqual(requests, ["/page", "/page", "/script.js"])
        self.assertEqual(disabled.stderr, "")
        self.assertEqual(disabled.stdout, self.render(self.html("fallback", "<p>Fallback</p>")).stdout)
        self.assertEqual(local_rendered.stdout, disabled.stdout)
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(self.html("loopback", "<p>Loopback works</p>")).stdout)
        self.assertNotEqual(rendered.stdout, disabled.stdout)

    def test_relative_external_redirect_and_inline_scripts_share_document_order(self):
        routes = {
            "/dir/step.js?v=1&k=2": redirect("?final=1"),
            "/dir/step.js?final=1": js_response(b"order += 'B';"),
            "/finish.js": js_response((FIXTURES / "browser_javascript_order.js").read_bytes()),
        }
        with loopback(routes) as (base, requests):
            host = base.split("://", 1)[1].replace("127.0.0.1", "localhost")
            routes["/dir/page"] = html_response(f'''<p id="out">Fallback</p>
<script>var order = 'A';</script>
<script src="./step.js?v=1&amp;k=2#ignored">throw new Error('src must ignore inline body');</script>
<script>order += 'C';</script>
<script src="//{host.upper()}/finish.js" type="application/javascript"></script>
<script>order += 'E';</script>''')
            with loopback({"/start": redirect(f"http://{host}/dir/page")}) as (entry, navigation):
                result = self.render(f"{entry}/start", scripts=True)
        self.assertEqual(navigation, ["/start"])
        self.assertEqual(requests, ["/dir/page", "/dir/step.js?v=1&k=2", "/dir/step.js?final=1", "/finish.js"])
        self.assertEqual(result.stderr, "")
        self.assertEqual(result.stdout, self.render(self.html("ordered", "<p>ABCDE</p>")).stdout)

    def test_external_rejections_do_not_run_or_follow_other_origins(self):
        bad_js = b"throw new Error('a rejected script ran');"
        with loopback({"/foreign.js": js_response(bad_js)}) as (foreign, foreign_requests):
            routes = {
                "/wrong-mime.js": js_response(bad_js, "text/plain"),
                "/no-mime.js": js_response(bad_js, None),
                "/charset.js": js_response(bad_js, "text/javascript; charset=windows-1252"),
                "/bad-parameters.js": js_response(bad_js, "text/javascript; charset=utf-8 unexpected=yes"),
                "/invalid-text.js": js_response(bad_js + b"//\xff"),
                "/too-big.js": js_response(bad_js + b" " * 32768),
                "/redirect.js": redirect(f"//{foreign.split('://', 1)[1]}/foreign.js"),
                "/base": html_response('<base href="/elsewhere/">'
                                       '<script src="/not-loaded.js"></script><p>Fallback</p>'),
                "/raw-text": html_response('<p>Fallback</p><script type="application/json"><!--<script></script>'
                                           '<script src="/not-loaded.js"></script>--></script>'),
            }
            with loopback(routes) as (base, requests):
                routes["/change-scheme.js"] = redirect(f"{base.replace('http:', 'https:')}/foreign.js")
                routes["/page"] = html_response(f'''<p id="out">Fallback</p>
<template><script src="/not-loaded.js"></script></template>
<noscript><script src="/not-loaded.js"></script></noscript>
<svg><script src="/not-loaded.js"></script></svg>
<script src="/not-loaded.js" type="module"></script>
<script src="/not-loaded.js" type="application/json"></script>
<script src="/not-loaded.js" async></script><script src="/not-loaded.js" defer></script>
<script src="/not-loaded.js" integrity="sha256-invalid"></script>
<script src="{foreign}/foreign.js"></script>
<script src="{base.replace('127.0.0.1', 'localhost')}/foreign.js"></script>
<script src="/redirect.js"></script><script src="/change-scheme.js"></script>
<script src="/wrong-mime.js"></script><script src="/no-mime.js"></script>
<script src="/charset.js"></script><script src="/invalid-text.js"></script>
<script src="/too-big.js"></script><script src="/bad-parameters.js"></script>
<script>document.getElementById('out').textContent = 'Still works';</script>
<script src="/not-loaded.js">''')
                rendered = self.render(f"{base}/page", scripts=True)
                for path in ("/base", "/raw-text"):
                    with self.subTest(path=path):
                        fallback = self.render(base + path).stdout
                        self.assertEqual(self.render(base + path, scripts=True).stdout, fallback)
        self.assertEqual(foreign_requests, [])
        self.assertEqual(requests, ["/page", "/redirect.js", "/change-scheme.js", "/wrong-mime.js", "/no-mime.js",
                                    "/charset.js", "/invalid-text.js", "/too-big.js", "/bad-parameters.js",
                                    "/base", "/base", "/raw-text", "/raw-text"])
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(self.html("still-works", "<p>Still works</p>")).stdout)

    def test_csp_document_never_requests_scripts(self):
        document = ('''<p id="out">Fallback</p><script src="/not-loaded.js"></script>
<script>document.getElementById('out').textContent = 'Inline JS';</script>''')
        with loopback({
            "/header": html_response(document, **{"Content-Security-Policy": "script-src 'self' 'unsafe-inline'"}),
            "/meta": html_response(document + '<meta http-equiv="Content-Security-Policy" content="script-src \'self\'">'),
        }) as (base, requests):
            fallback = self.render(self.html("csp-fallback", "<p>Fallback</p>")).stdout
            for path in ("/header", "/meta"):
                with self.subTest(path=path):
                    blocked = self.render(base + path, scripts=True)
                    self.assertIn("JavaScript disabled by page security policy", blocked.stderr)
                    self.assertEqual(blocked.stdout, fallback)
        self.assertEqual(requests, ["/header", "/meta"])

    def test_script_byte_budget_includes_inline_and_external_sources(self):
        large = b"var order = 'A';".ljust(32768, b" ")
        excess = b"throw new Error('combined budget ignored');"
        # Keep the prepared program under 64 KiB, but with too little room for the next script.
        inline = "order += 'B'; document.getElementById('out').textContent = order;".ljust(32768 - 16)
        page = f'<p id="out">Fallback</p><script src="/large.js"></script><script>{inline}</script><script src="/excess.js"></script>'
        with loopback({"/page": html_response(page), "/large.js": js_response(large), "/excess.js": js_response(excess)}) as (base, requests):
            rendered = self.render(f"{base}/page", scripts=True)
        self.assertEqual(requests, ["/page", "/large.js", "/excess.js"])
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(self.html("budget", "<p>AB</p>")).stdout)

    def test_request_budget_counts_rejected_redirect_hops(self):
        page = "<p>Fallback</p>" + '<script src="/redirect.js"></script>' * 25
        routes = {"/page": html_response(page), "/redirect.js": redirect("/wrong-mime.js"),
                  "/wrong-mime.js": js_response(b"throw new Error('wrong MIME');", "text/plain")}
        with loopback(routes) as (base, requests):
            rendered = self.render(f"{base}/page", scripts=True)
        self.assertEqual(requests, ["/page"] + ["/redirect.js", "/wrong-mime.js"] * 12)
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(self.html("request-budget", "<p>Fallback</p>")).stdout)

    def test_slow_script_honors_deadline_and_navigation_cancellation(self):
        started = threading.Event()
        release = threading.Event()

        def slow():
            started.set()
            release.wait(3)
            return b"throw new Error('slow source ran');"

        page = '''<p id="out">Fallback</p><script>document.getElementById('out').textContent = 'Partial';</script>
<script src="/slow.js"></script><script src="/not-loaded.js"></script>'''
        routes = {"/page": html_response(page), "/slow.js": js_response(slow)}
        with loopback(routes) as (base, requests):
            try:
                rendered = self.render(f"{base}/page", scripts=True)
            finally:
                release.set()
        self.assertEqual(requests, ["/page", "/slow.js"])
        self.assertIn("JavaScript stopped or unavailable", rendered.stderr)
        self.assertEqual(rendered.stdout, self.render(self.html("timeout-fallback", "<p>Fallback</p>")).stdout)

        fixture = self.build_fixture()
        started.clear()
        release.clear()
        with loopback(routes) as (base, requests):
            with subprocess.Popen([str(fixture), f"{base}/page", "cancel"], env={"SDL_VIDEODRIVER": "dummy"},
                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as child:
                try:
                    self.assertTrue(started.wait(3), "the navigation worker never started the script request")
                    stdout, stderr = child.communicate(input=b"x", timeout=3)
                    self.assertEqual(child.returncode, 0, stdout + stderr)
                finally:
                    release.set()
                    if child.poll() is None:
                        child.kill()
        self.assertEqual(requests, ["/page", "/slow.js"])

    def test_invalid_utf8_id_does_not_shadow_a_valid_id(self):
        source = self.dir / "utf8-id.html"
        source.write_bytes(b'<p id="\xff">First</p><p id="\xef\xbf\xbd">Second</p>'
                           b'<script>document.getElementById("\\uFFFD").textContent="Updated";</script>')
        reference = self.html("utf8-id-reference", "<p>First</p><p>Updated</p>")
        rendered = self.render(source, scripts=True)
        self.assertEqual(rendered.stderr, "")
        self.assertEqual(rendered.stdout, self.render(reference).stdout)
        self.assertNotEqual(rendered.stdout, self.render(source).stdout)

    def test_meta_policy_keeps_document_static(self):
        source = self.html("meta-csp", '<meta http-equiv=" Content-Security-Policy " content="script-src \'none\'">'
                           '<noscript><p id="out">Fallback</p></noscript>'
                           '<script>document.getElementById("out").textContent="JS"</script>')
        result = self.render(source, scripts=True)
        self.assertIn("JavaScript disabled by page security policy", result.stderr)
        self.assertEqual(result.stdout, self.render(source).stdout)

    def test_loop_or_missing_worker_keeps_static_document(self):
        source = self.html("loop", '<p id="out">Fallback</p><script>document.getElementById("out").textContent="Partial"; while(true) {}</script>')
        baseline = self.render(source).stdout
        missing = self.dir / "no-helper"
        missing.mkdir(exist_ok=True)
        viewer = Path(shutil.copy(self.viewer, missing))
        for binary in (self.viewer, viewer):
            with self.subTest(binary=binary):
                result = self.render(source, scripts=True, viewer=binary)
                self.assertEqual(result.stdout, baseline)
                self.assertIn("JavaScript stopped or unavailable", result.stderr)

    def test_worker_must_be_a_regular_protected_sibling(self):
        source = self.html("protected", '<p id="out">Fallback</p><script>document.getElementById("out").textContent="JS"</script>')
        directory = self.dir / "helper-permissions"
        directory.mkdir()
        viewer = Path(shutil.copy(self.viewer, directory))
        helper = directory / self.worker_name
        helper.symlink_to(self.dir / self.worker_name)
        for mode in (None, 0o775):
            with self.subTest(mode=mode):
                if mode is not None:
                    helper.unlink()
                    shutil.copy(self.dir / self.worker_name, helper)
                    helper.chmod(mode)
                result = self.render(source, scripts=True, viewer=viewer)
                self.assertEqual(result.stdout, self.render(source).stdout)
                self.assertIn("JavaScript stopped or unavailable", result.stderr)

    def test_worker_installs_kernel_filter_before_evaluating(self):
        browser, worker = socket.socketpair()
        def status(pid):
            return dict(line.split(":", 1) for line in Path(f"/proc/{pid}/status").read_text().splitlines())
        with browser, worker, subprocess.Popen([str(self.dir / self.worker_name)], stdin=worker, env={}) as child:
            try:
                worker.close()
                browser.settimeout(3)
                script = b"6 * 7;"
                browser.sendall(struct.pack("<4q", 1, 0, 1, len(script)) + script)
                with browser.makefile("rb") as response:
                    self.assertEqual(response.read(24), struct.pack("<3q", 16, 0, 0))
                secured, parent = status(child.pid), status("self")
                self.assertEqual(secured["NoNewPrivs"].strip(), "1")
                self.assertEqual(secured["Seccomp"].strip(), "2")
                if "Seccomp_filters" in secured:
                    self.assertGreater(int(secured["Seccomp_filters"]), int(parent["Seccomp_filters"]))
            finally:
                browser.close()
                if child.poll() is None:
                    try:
                        child.wait(timeout=3)
                    except subprocess.TimeoutExpired:
                        child.kill()
                        raise
            self.assertEqual(child.returncode, 0)

    def test_clicks_keep_state_reflow_and_reset_on_navigation(self):
        markup = '''<style>button { display: block }</style>
<p id="out">Initial</p><p><a id="run" href="#not-opened">Run</a></p><button id="hang">Hang</button>
<p><a href="plain.html">Next</a></p>'''
        code = (FIXTURES / "browser_javascript_click.js").read_text(encoding="utf-8")
        source = self.html("click", f"{markup}<script>{code}</script>")
        plain = self.html("plain", "<p>Plain</p>")
        fixture = self.build_fixture()
        with loopback({
            "/click": html_response(markup + '<script src="click.js"></script>'),
            "/click.js": js_response(code.encode("utf-8")),
            "/plain.html": html_response("<p>Plain</p>"),
        }) as (base, requests):
            for page, other in ((str(source), str(plain)), (base + "/click", base + "/plain.html")):
                for options in ([], ["visual"]):
                    with self.subTest(page=page, options=options):
                        result = subprocess.run([str(fixture), page, other, *options], env={"SDL_VIDEODRIVER": "dummy"},
                                                text=True, capture_output=True, timeout=6)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(requests.count("/click.js"), 6)


@unittest.skipUnless(HAVE_JS_DEPS, "optional Duktape/libseccomp development dependencies not installed")
class BrowserJavaScript(BrowserJavaScriptSuite, unittest.TestCase):
    pass


@unittest.skipUnless(QUICKJS_DIR and HAVE_SECCOMP, "set QUICKJS_DIR to test the optional QuickJS-NG worker")
class BrowserModernJavaScript(BrowserJavaScriptSuite, unittest.TestCase):
    worker_name = "volt-js-modern"

    def test_modern_syntax_jobs_and_unicode_reach_the_native_dom(self):
        source = self.html("modern", r'''<p id="out">Fallback</p>
<script>
const stackHook = Object.getOwnPropertyDescriptor(Error, 'prepareStackTrace');
if (!stackHook || stackHook.configurable || stackHook.writable || stackHook.value !== undefined)
    throw new Error('stack hook not disabled');
class Clip { #track = {codec: 'AVC'}; name() { return this.#track?.codec ?? '?'; } }
const views = async () => {
    let denied = false;
    try { await import('std'); } catch (e) { denied = true; }
    if (!denied || typeof std !== 'undefined' || typeof os !== 'undefined') throw new Error('host module');
    return `${new Clip().name()} ${42n}🙂`;
};
const out = document.querySelector('#out');
views().then(value => out.textContent = value);
</script><script>
if (out.textContent !== 'AVC 42🙂') throw new Error('missed microtask checkpoint');
let textLimit = false;
try { out.textContent = '🙂'.repeat(1025); } catch (e) { textLimit = e instanceof RangeError; }
if (!textLimit || out.textContent !== 'AVC 42🙂') throw new Error('text byte limit');
document.addEventListener('DOMContentLoaded', () => {
    Promise.resolve().then(() => out.textContent += ' \uD800\u0000');
});
</script>''')
        expected = self.html("modern-reference", "<p>AVC 42🙂 ��</p>")
        actual = self.render(source, scripts=True)
        self.assertEqual(actual.stderr, "")
        self.assertEqual(actual.stdout, self.render(expected).stdout)
        self.assertNotEqual(actual.stdout, self.render(source).stdout)

    def test_microtask_limit_discards_unfinished_dom_reply(self):
        source = self.html("job-limit", '''<p id="out">Fallback</p><script>
document.getElementById('out').textContent = 'uncommitted';
const again = () => { Promise.resolve().then(again); };
again();
</script>''')
        result = self.render(source, scripts=True)
        self.assertIn("JavaScript stopped or unavailable", result.stderr)
        self.assertEqual(result.stdout, self.render(source).stdout)

    @unittest.skipUnless(HAVE_JS_DEPS, "optional Duktape dependency not installed")
    def test_modern_worker_is_preferred_and_invalid_helper_does_not_fall_back(self):
        both = self.dir / "both-engines"
        both.mkdir()
        viewer = Path(shutil.copy2(self.viewer, both))
        helper = Path(shutil.copy2(self.dir / self.worker_name, both))
        subprocess.run(["make", f"BINDIR={both}", str(both / "volt-js")], cwd=ROOT, check=True, timeout=20)
        source = self.html("engine-choice", '''<p id="out">Static</p><script>
document.getElementById('out').textContent = typeof Promise === 'function' ? 'Modern' : 'Legacy';
</script>''')
        for expected in ("Modern", "Static", "Legacy"):
            with self.subTest(expected=expected):
                result = self.render(source, scripts=True, viewer=viewer)
                reference = self.html("engine-reference", f"<p>{expected}</p>")
                self.assertEqual(result.stdout, self.render(reference).stdout)
                if expected == "Modern":
                    helper.chmod(0o775)
                elif expected == "Static":
                    self.assertIn("JavaScript stopped or unavailable", result.stderr)
                    helper.unlink()


if __name__ == "__main__":
    unittest.main()
