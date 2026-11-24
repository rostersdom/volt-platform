#!/usr/bin/env python3
"""Integration tests for the VOLT static viewer CLI."""
import gzip
import socket
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "apps" / "browser.volt"
DOCUMENT_LIMIT = 2 * 1024 * 1024


class BrowserLocalViewer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-browser-local-")
        cls.root = Path(cls.temp.name)
        cls.exe = cls.root / "browser"
        built = subprocess.run([str(ROOT / "volt"), str(SOURCE), "-o", str(cls.exe)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise AssertionError(built.stdout + built.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def run_viewer(self, *args):
        return subprocess.run([str(self.exe), *map(str, args)], cwd=ROOT,
                              capture_output=True, text=True, timeout=10)

    def test_default_local_fixture_has_expected_rendering(self):
        result = self.run_viewer("--check")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "VOLT native viewer pixel check passed: 91987\n")
        pixels = subprocess.run([str(ROOT / "volt"), "tests/paint.volt", "--run"],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(pixels.returncode, 0, pixels.stdout + pixels.stderr)
        self.assertIn("default fixture pixels ok", pixels.stdout)

    def test_custom_local_file_and_invalid_document(self):
        fixture = self.root / "local.html"
        fixture.write_text('<body style="background: white"><p>OK</p></body>', encoding="ascii")
        result = self.run_viewer("--check", fixture)
        self.assertEqual(result.returncode, 0, result.stderr)
        missing = self.run_viewer("--check", self.root / "missing.html")
        self.assertEqual(missing.returncode, 1)
        self.assertIn("cannot read local document", missing.stderr)
        malformed = self.root / "bad.html"
        malformed.write_text("<!-- unterminated", encoding="ascii")
        self.assertNotEqual(self.run_viewer("--check", malformed).returncode, 0)

    def test_unsupported_at_rules_do_not_discard_styles(self):
        base = "body { background: #335588 }"
        tail = "b { display: none }"
        recovered = (base + ' @media screen { body { background: white } } '
                     + "@import 'unused.css'; " + tail)
        fixtures = []
        for index, sheet in enumerate((recovered, base + tail, "")):
            page = self.root / f"styles-{index}.html"
            page.write_text(f"<style>{sheet}</style><body><p>One<p>Two <b>hidden</b></body>", encoding="ascii")
            result = self.run_viewer("--check", page)
            self.assertEqual(result.returncode, 0, result.stderr)
            fixtures.append(result.stdout)
        self.assertEqual(fixtures[0], fixtures[1])
        self.assertNotEqual(fixtures[0], fixtures[2])

    def test_local_fragment_and_literal_hash_in_filename(self):
        fixture = self.root / "anchors.html"
        fixture.write_text('<p>Line</p>' * 60 + '<p id="я">End</p>', encoding="utf-8")
        first = self.run_viewer("--check", fixture)
        jumped = self.run_viewer("--check", f"{fixture}#%D1%8F")
        self.assertEqual(first.returncode, 0, first.stderr)
        self.assertEqual(jumped.returncode, 0, jumped.stderr)
        self.assertNotEqual(first.stdout, jumped.stdout)

        literal = self.root / "anchors.html#я"
        literal.write_text(fixture.read_text(encoding="utf-8"), encoding="utf-8")
        opened = self.run_viewer("--check", literal)
        self.assertEqual(opened.returncode, 0, opened.stderr)
        self.assertEqual(opened.stdout, first.stdout)

    def serve(self, response):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(5)
        port = listener.getsockname()[1]
        observed = []
        errors = []
        def worker():
            try:
                conn, _ = listener.accept()
                with conn:
                    request = b""
                    while b"\r\n\r\n" not in request:
                        part = conn.recv(1024)
                        if not part: break
                        request += part
                    observed.append(request)
                    for chunk in response: conn.sendall(chunk)
            except (OSError, TimeoutError) as error:
                errors.append(error)
            finally:
                listener.close()
        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        return port, observed, thread, errors

    def serve_sequence(self, responses):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(8)
        listener.settimeout(4)
        port = listener.getsockname()[1]
        observed = []
        errors = []
        def worker():
            try:
                for response in responses:
                    conn, _ = listener.accept()
                    conn.settimeout(3)
                    with conn:
                        request = b""
                        while b"\r\n\r\n" not in request:
                            part = conn.recv(1024)
                            if not part: break
                            request += part
                        observed.append(request)
                        conn.sendall(response(port) if callable(response) else response)
            except (OSError, TimeoutError) as error:
                errors.append(error)
            finally:
                listener.close()
        thread = threading.Thread(target=worker, daemon=True)
        thread.start()
        return port, observed, thread, errors

    def test_http_url_renders_fragmented_loopback_response(self):
        body = b'<body style="background: white"><p>OK</p></body>'
        local = self.root / "network-equivalent.html"
        local.write_bytes(body)
        local_result = self.run_viewer("--check", local)
        response = b"HTTP/1.1 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\nContent-Type: text/html\r\n\r\n" + body
        port, observed, thread, errors = self.serve((response[:17], response[17:43], response[43:]))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/path?q=1")
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive(), "loopback server did not finish")
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, local_result.stdout)
        self.assertEqual(observed, [f"GET /path?q=1 HTTP/1.0\r\nHost: 127.0.0.1:{port}\r\n"
                                    f"Accept-Encoding: identity\r\nConnection: close\r\n\r\n".encode()])

    def test_http_body_can_end_at_tcp_eof(self):
        body = b'<p id="top">Close delimited</p>'
        local = self.root / "close-delimited.html"
        local.write_bytes(body)
        headers = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n\r\n"
        port, requests, thread, errors = self.serve((headers, body))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/#top")
        thread.join(timeout=3)
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(requests[0].split(b"\r\n", 1)[0], b"GET / HTTP/1.0")
        self.assertEqual(result.stdout, self.run_viewer("--check", local).stdout)

    def run_with_open_response(self, wire):
        with socket.create_server(("127.0.0.1", 0)) as listener:
            listener.settimeout(3)
            url = f"http://127.0.0.1:{listener.getsockname()[1]}/keep-alive"
            with subprocess.Popen([str(self.exe), "--check", url], cwd=ROOT, text=True,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE) as browser:
                try:
                    client, _ = listener.accept()
                    with client, client.makefile("rb") as stream:
                        client.settimeout(3)
                        self.assertTrue(stream.readline().startswith(b"GET /keep-alive "))
                        while stream.readline() not in (b"\r\n", b""):
                            pass
                        client.sendall(wire)
                        try:
                            self.assertEqual(client.recv(1), b"")
                        except ConnectionResetError:
                            pass  # There may be unread surplus after the first frame.
                    out, err = browser.communicate(timeout=3)
                    return browser.returncode, out, err
                finally:
                    if browser.poll() is None:
                        browser.kill()
                        browser.communicate()

    def test_framed_body_finishes_without_waiting_for_eof(self):
        body = b"<p>Keep-alive response</p>"
        local = self.root / "keep-alive.html"
        local.write_bytes(body)
        expected = self.run_viewer("--check", local)
        prefix = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        for wire in (f"Content-Length: {len(body)}\r\n\r\n".encode() + body,
                     b"Transfer-Encoding: chunked\r\n\r\n" + f"{len(body):x}\r\n".encode() + body + b"\r\n0\r\n\r\n"):
            for extra in (b"", b"<h1>Not part of this response</h1>"):
                with self.subTest(framing=wire.split(b":", 1)[0], extra=bool(extra)):
                    self.assertEqual(self.run_with_open_response(prefix + wire + extra), (0, expected.stdout, ""))

    def test_declared_body_over_limit_is_rejected_without_waiting_for_eof(self):
        prefix = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        for wire in (f"Content-Length: {DOCUMENT_LIMIT + 1}\r\n\r\n".encode(),
                     b"Transfer-Encoding: chunked\r\n\r\n" + f"{DOCUMENT_LIMIT + 1:x}\r\n".encode()):
            with self.subTest(framing=wire.split(b":", 1)[0]):
                self.assertEqual(self.run_with_open_response(prefix + wire),
                                 (1, "", "browser: document or response too large\n"))

    def test_hostname_loopback_preserves_host_and_pixels(self):
        body = b'<body style="background: white"><p>OK</p></body>'
        local = self.root / "hostname-equivalent.html"
        local.write_bytes(body)
        local_result = self.run_viewer("--check", local)
        response = b"HTTP/1.0 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\nContent-Type: text/html\r\n\r\n" + body
        port, observed, thread, errors = self.serve((response,))
        result = self.run_viewer("--check", f"http://LOCALHOST:{port}/same?q=1")
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, local_result.stdout)
        self.assertEqual(observed, [f"GET /same?q=1 HTTP/1.0\r\nHost: LOCALHOST:{port}\r\n"
                                    f"Accept-Encoding: identity\r\nConnection: close\r\n\r\n".encode()])

    def test_redirect_statuses_and_location_forms(self):
        body = b'<body style="background: white"><p>OK</p></body>'
        final = b"HTTP/1.0 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\nContent-Type: text/html\r\n\r\n" + body
        for status in (301, 302, 303, 307, 308):
            redirect = f"HTTP/1.0 {status} Redirect\r\nLocation: /final\r\nContent-Type: text/html\r\nContent-Length: 3\r\n\r\nxyz".encode()
            port, observed, thread, errors = self.serve_sequence((redirect, final))
            result = self.run_viewer("--check", f"http://127.0.0.1:{port}/start")
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(len(observed), 2)
            self.assertIn(b"GET /start HTTP/1.0", observed[0])
            self.assertIn(b"GET /final HTTP/1.0", observed[1])

        def redirect_to(location):
            return b"HTTP/1.0 302 Found\r\nLocation: " + location + b"\r\nContent-Type: text/html\r\nContent-Length: 0\r\n\r\n"
        for location, expected in ((b"next%2Fpart?q=%3F#top", b"GET /dir/next%2Fpart?q=%3F HTTP/1.0"),
                                  (b"/root", b"GET /root HTTP/1.0"),
                                  (b"next", b"GET /dir/next HTTP/1.0"),
                                  (b"../up?q=1", b"GET /up?q=1 HTTP/1.0")):
            port, observed, thread, errors = self.serve_sequence((redirect_to(location), final))
            result = self.run_viewer("--check", f"http://127.0.0.1:{port}/dir/start")
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn(expected, observed[1])
        absolute = lambda selected_port: f"HTTP/1.0 302 Found\r\nLocation: http://localhost:{selected_port}/absolute\r\nContent-Type: text/html\r\nContent-Length: 0\r\n\r\n".encode()
        port, observed, thread, errors = self.serve_sequence((absolute, final))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/dir/start")
        thread.join(timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(b"GET /absolute HTTP/1.0", observed[1])
        self.assertIn(f"Host: localhost:{port}".encode(), observed[1])

    def test_redirect_preserves_client_side_fragment(self):
        body = ('<p>Line</p>' * 60 + '<p id="я">End</p>').encode("utf-8")
        local = self.root / "redirected-anchor.html"
        local.write_bytes(body)
        expected = self.run_viewer("--check", f"{local}#%D1%8F")
        self.assertEqual(expected.returncode, 0, expected.stderr)
        redirect = b"HTTP/1.0 302 Found\r\nLocation: /target\r\nContent-Length: 0\r\n\r\n"
        response = (b"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nContent-Length: "
                    + str(len(body)).encode() + b"\r\n\r\n" + body)
        port, requests, worker, errors = self.serve_sequence((redirect, response))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/start#%D1%8F")
        worker.join(timeout=3)
        self.assertFalse(worker.is_alive())
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, expected.stdout)
        self.assertEqual([r.split(b"\r\n", 1)[0] for r in requests],
                         [b"GET /start HTTP/1.0", b"GET /target HTTP/1.0"])

    def test_redirect_loop_limit_and_bad_locations(self):
        body = b'<body style="background: white"><p>OK</p></body>'
        final = b"HTTP/1.0 200 OK\r\nContent-Length: " + str(len(body)).encode() + b"\r\nContent-Type: text/html\r\n\r\n" + body
        redirect = lambda loc: b"HTTP/1.0 302 Found\r\nLocation: " + loc + b"\r\nContent-Type: text/html\r\nContent-Length: 0\r\n\r\n"
        port, observed, thread, errors = self.serve_sequence((redirect(b"/same"),))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/same")
        thread.join(timeout=3)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "browser: HTTP redirect loop\n")
        self.assertEqual(len(observed), 1)
        responses = tuple(redirect(f"/hop{i + 1}".encode()) for i in range(6))
        port, observed, thread, errors = self.serve_sequence(responses)
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/h0")
        thread.join(timeout=3)
        self.assertEqual(result.returncode, 1)
        self.assertIn("redirect limit", result.stderr)
        self.assertEqual(len(observed), 6)
        long_host = ".".join(("a" * 63, "b" * 63, "c" * 63, "d" * 45, "localhost"))
        for target, url in ((b"/" + b"c" * 7990, f"http://{long_host}:"),
                            (b"b" * 100, "")):
            port, observed, thread, errors = self.serve_sequence((redirect(target),))
            input_url = url + str(port) + "/start" if url else f"http://127.0.0.1:{port}/" + "a" * 8098 + "/"
            result = self.run_viewer("--check", input_url)
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(result.returncode, 1)
            self.assertEqual(result.stderr, "browser: invalid HTTP response\n")
        for location in (b"", b"//127.0.0.1/x", b"https://x/", b"?q=1", b"#frag", b"/bad%GG", b"/space here"):
            response = redirect(location)
            port, observed, thread, errors = self.serve_sequence((response,))
            result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
            thread.join(timeout=3)
            self.assertEqual(result.returncode, 1, (location, result.stderr))
            self.assertEqual(len(observed), 1)

    def test_bad_url_and_http_error_are_rejected(self):
        for url in (
            "https:///missing-host", "http://bad_name/", "http://-bad/", "http://bad..name/", "http://127.000.0.1/", "http://127.000.000.001/", "http://127.0.0.1:0/",
            "http://user@127.0.0.1/", "http://127.0.0.1:abc/", "http://127.0.0.1:65536/",
            "http://999.1.1.1/", "http://127.0.0.1/%GG", "http://bad_host/", "http://bad-.example/", "http://.example/", "http://example./", "http://caf\u00e9.example/", "http://bad%20name/",
        ):
            result = self.run_viewer("--check", url)
            self.assertEqual(result.returncode, 2, (url, result.stderr))
            self.assertEqual(result.stderr, "browser: invalid or unsupported HTTP URL\n")
        response = b"HTTP/1.0 404 Not Found\r\nContent-Type: text/html\r\nContent-Length: 9\r\n\r\nnot found"
        port, _, thread, errors = self.serve((response,))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
        thread.join(timeout=3)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "browser: HTTP status 404\n")

    def test_encoded_response_is_not_mistaken_for_html(self):
        body = gzip.compress(b"<p>Compressed</p>")
        headers = (b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Encoding: gzip\r\n"
                   + f"Content-Length: {len(body)}\r\n\r\n".encode())
        port, _, thread, errors = self.serve((headers, body))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
        thread.join(timeout=3)
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(result.stderr, "browser: unsupported HTTP Content-Encoding\n")

    def test_statuses_without_a_body_are_not_malformed_responses(self):
        for status, headers in ((204, b""), (304, b"Content-Length: 5000000\r\n")):
            with self.subTest(status=status):
                response = f"HTTP/1.1 {status} Status\r\n".encode() + headers + b"\r\n"
                port, _, thread, errors = self.serve((response,))
                result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
                thread.join(timeout=3)
                self.assertFalse(errors)
                self.assertEqual((result.returncode, result.stderr), (1, f"browser: HTTP status {status}\n"))

    def test_chunked_response_decodes_fragmented_body(self):
        body = b'<body style="background: white"><p>OK</p></body>'
        local = self.root / "chunked-equivalent.html"
        local.write_bytes(body)
        local_result = self.run_viewer("--check", local)
        first = b"<body"
        second = body[len(first):]
        wires = (
            b"5\r\n<body\r\n" + format(len(second), "x").encode() + b"\r\n" + second + b"\r\n0\r\n\r\n",
            format(len(body), "x").encode() + b"\r\n" + body + b"\r\n0\r\n\r\n",
        )
        for index, chunked_body in enumerate(wires[:2]):
            wire = b"HTTP/1.1 200 OK\r\nTransfer-Encoding: ChUnKeD\r\nContent-Type: text/html\r\n\r\n" + chunked_body
            port, observed, thread, errors = self.serve((wire[:41], wire[41:73], wire[73:]))
            result = self.run_viewer("--check", f"http://127.0.0.1:{port}/chunked{index}")
            thread.join(timeout=3)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(result.stdout, local_result.stdout)
            self.assertEqual(len(observed), 1)

    def test_chunked_zero_chunk_and_invalid_framing(self):
        valid_empty = b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n0\r\n\r\n"
        cases = (valid_empty,
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Length: 1\r\nContent-Type: text/html\r\n\r\n0\r\n\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n0\r\n\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: gzip, chunked\r\nContent-Type: text/html\r\n\r\n0\r\n\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\nZ\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n5;ext=x\r\n<body\r\n0\r\n\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n10001\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n" + b"0" * 64 + b"\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n5\r\n<ab",
                 b"HTTP/1.0 200 OK\nContent-Length: 1\nContent-Type: text/html\n\n<x",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n4\r\n<abcxx0\r\n\r\n",
                 b"HTTP/1.0 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n0\r\nX: y\r\n\r\n")
        for response in cases:
            with self.subTest(response=response):
                port, _, thread, errors = self.serve((response,))
                result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
                self.assertFalse(errors)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stderr, "browser: invalid HTTP response\n")

    def test_http_framing_errors_are_rejected(self):
        cases = (
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Type: text/html\r\n\r\n",
            b"HTTP/1.1 200 OK\r\nContent-Length: 3\r\nContent-Type: text/html\r\n\r\n<x",
            b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nContent-Type: text/html\r\n\r\n0\r\n\r\n",
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 1\r\nContent-Type: text/html\r\n\r\n<x",
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Type: application/octet-stream\r\n\r\n<x",
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Type: text/html\r\nX-Bad Header: x\r\n\r\n<x",
            b"HTTP/1.1 200 OK\nContent-Length: 1\nContent-Type: text/html\n\n<x",
            b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nContent-Type: text/html\r\n\r\n",
            b"HTTP/1.1 204 No Content\r\nContent-Length: 1\r\nContent-Type: text/html\r\n\r\n<x",
            b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\nContent-Length: 2\r\nContent-Type: text/html\r\n\r\n<x",
            b"HTTP/1.1 200 OK\r\nContent-Length: nope\r\nContent-Type: text/html\r\n\r\n<x")
        for response in cases:
            with self.subTest(response=response):
                port, _, thread, errors = self.serve((response,))
                result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive(), "loopback server did not finish")
                self.assertFalse(errors)
                self.assertEqual(result.returncode, 1, (response, result.stderr))
                self.assertEqual(result.stderr, "browser: invalid HTTP response\n")

    def test_invalid_html_body_is_rejected(self):
        for body in (b"", b"<!-- unterminated"):
            with self.subTest(body_prefix=body[:20], body_length=len(body)):
                response = (b"HTTP/1.0 200 OK\r\nContent-Length: " + str(len(body)).encode()
                            + b"\r\nContent-Type: text/html\r\n\r\n" + body)
                port, _, thread, errors = self.serve((response,))
                result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
                self.assertFalse(errors)
                self.assertEqual(result.returncode, 1, result.stderr)

    def test_large_document_renders_after_growing_dom_and_layout(self):
        # Push past the previous wire, node, attribute, fragment and text limits.
        rows = (f'<p id="row{i}" data-text="yes">test one two three long text</p>' for i in range(5000))
        body = "".join(rows).encode() + b'<p id="tail" style="background: #126ab5">END</p>'
        file = self.root / "long-page.html"
        file.write_bytes(body)
        plain = self.run_viewer("--check", file)
        self.assertEqual(plain.returncode, 0, plain.stderr)
        local = self.run_viewer("--check", f"{file}#tail")
        self.assertEqual(local.returncode, 0, local.stderr)
        self.assertNotEqual(plain.stdout, local.stdout)

        head = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        for framing in ("Content-Length", "chunked"):
            with self.subTest(framing=framing):
                if framing == "chunked":
                    headers = head + b"Transfer-Encoding: chunked\r\n\r\n"
                    wire_body = f"{len(body):x}\r\n".encode() + body + b"\r\n0\r\n\r\n"
                else:
                    headers = head + f"Content-Length: {len(body)}\r\n\r\n".encode()
                    wire_body = body
                port, _, thread, errors = self.serve((headers, wire_body))
                remote = self.run_viewer("--check", f"http://127.0.0.1:{port}/#tail")
                thread.join(timeout=3)
                self.assertFalse(thread.is_alive())
                self.assertFalse(errors)
                self.assertEqual(remote.returncode, 0, remote.stderr)
                self.assertEqual(remote.stdout, local.stdout)

    def test_large_document_applies_styles_without_repeated_source_scans(self):
        fixture = self.root / "large-styled.html"
        fixture.write_bytes(b'<style>' + b' ' * 24000 + b'p { color:#112244 }</style>'
                            + b'<p style="color:#446688">Large page</p>' * 2600)
        result = self.run_viewer("--check", fixture)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "VOLT native viewer pixel check passed: 4440\n")

    def test_oversize_input_and_extra_arguments_are_rejected(self):
        large = self.root / "large.html"
        tail = b"<p>Boundary</p>"
        large.write_bytes(b" " * (DOCUMENT_LIMIT - len(tail)) + tail)
        exact = self.run_viewer("--check", large)
        self.assertEqual(exact.returncode, 0, exact.stderr)
        self.assertRegex(exact.stdout, r"pixel check passed: [1-9][0-9]*\n$")

        large.write_bytes(b" " * (DOCUMENT_LIMIT + 1))
        result = self.run_viewer("--check", large)
        self.assertEqual(result.returncode, 1)
        self.assertIn("too large", result.stderr)
        response = (b"HTTP/1.0 200 OK\r\nContent-Type: text/html\r\n"
                    + f"Content-Length: {DOCUMENT_LIMIT + 1}\r\n\r\n".encode())
        port, _, thread, errors = self.serve((response,))
        result = self.run_viewer("--check", f"http://127.0.0.1:{port}/")
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive())
        self.assertFalse(errors)
        self.assertEqual(result.returncode, 1)
        self.assertIn("too large", result.stderr)
        self.assertEqual(self.run_viewer("--check", "one", "extra").returncode, 2)


if __name__ == "__main__":
    unittest.main()
