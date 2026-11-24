#!/usr/bin/env python3
"""Loopback HTTPS checks for the VOLT browser's verified TLS transport."""
import gzip
import os
from pathlib import Path
import socket
import ssl
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BrowserHttpsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-browser-https-")
        cls.root = Path(cls.temp.name)
        cls.cert = cls.root / "cert.pem"
        cls.key = cls.root / "key.pem"
        generated = subprocess.run(
            ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
             "-keyout", str(cls.key), "-out", str(cls.cert), "-days", "1",
             "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1"],
            capture_output=True, text=True, timeout=20,
        )
        if generated.returncode:
            raise RuntimeError(generated.stdout + generated.stderr)
        cls.exe = cls.root / "browser"
        built = subprocess.run(
            [str(ROOT / "volt"), str(ROOT / "apps" / "browser.volt"), "-o", str(cls.exe)],
            cwd=ROOT, capture_output=True, text=True, timeout=60,
        )
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def request(self, trusted, host="127.0.0.1", expect_valid=True, *, length=True, clean_close=False, hold_open=False, body=None, config=None, screenshot=None, tls11=None):
        if body is None:
            body = b'<body style="background: white"><p>HTTPS OK</p></body>'
        encoding = b"identity" if screenshot is None and tls11 is None else b"gzip"
        if encoding == b"gzip":
            body = gzip.compress(body)
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        listener.settimeout(5)
        port = listener.getsockname()[1]
        errors = []

        def serve():
            try:
                conn, _ = listener.accept()
                context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
                context.load_cert_chain(self.cert, self.key)
                if host == "127.0.0.1":
                    # RFC 6066 permits SNI host names, excluding literal IP addresses.
                    context.set_servername_callback(
                        lambda _, name, __: ssl.ALERT_DESCRIPTION_UNRECOGNIZED_NAME if name is not None else None
                    )
                with context.wrap_socket(conn, server_side=True) as client:
                    client.settimeout(5)
                    request = b""
                    while b"\r\n\r\n" not in request:
                        part = client.recv(1024)
                        if not part:
                            break
                        request += part
                    if b"\r\nAccept-Encoding: " + encoding + b"\r\n" not in request:
                        errors.append(f"missing Accept-Encoding: {encoding.decode()}")
                    version = b"HTTP/1.0" if tls11 is None else b"HTTP/1.1"
                    if not request.startswith(b"GET / " + version + b"\r\n"):
                        errors.append("wrong HTTP request version")
                    headers = version + b" 200 OK\r\nContent-Type: text/html\r\nConnection: close\r\n"
                    if encoding == b"gzip":
                        headers += b"Content-Encoding: gzip\r\n"
                    if tls11 is not None:
                        headers += b"Transfer-Encoding: chunked\r\n"
                        halfway = len(body) // 2
                        body_parts = body[:halfway], body[halfway:]
                        body_wire = b"".join(b"%x\r\n" % len(part) + part + b"\r\n" for part in body_parts) + b"0\r\n\r\n"
                    else:
                        body_wire = body
                    if length and tls11 is None:
                        headers += b"Content-Length: " + str(len(body)).encode() + b"\r\n"
                    client.sendall(headers + b"\r\n" + body_wire)
                    if hold_open:
                        if client.recv(1) != b"": errors.append("unexpected request data")
                    elif clean_close:
                        try:
                            client.unwrap().close()
                        except ssl.SSLEOFError:
                            # The server has already sent its close-notify.
                            pass
            except (OSError, TimeoutError, ssl.SSLError) as error:
                errors.append(error)
            finally:
                listener.close()

        thread = threading.Thread(target=serve, daemon=True)
        thread.start()
        env = os.environ.copy()
        if trusted:
            env["SSL_CERT_FILE"] = str(self.cert)
        else:
            env.pop("SSL_CERT_FILE", None)
        env["SSL_CERT_DIR"] = str(self.root / "empty-ca-dir")
        if config is not None:
            env["OPENSSL_CONF"] = str(config)
        mode = ["--check"] if screenshot is None else ["--screenshot", str(screenshot)]
        result = subprocess.run(
            ([str(self.exe), *mode] if tls11 is None else [str(tls11)]) + [f"https://{host}:{port}/"],
            cwd=ROOT, env=env, capture_output=True, text=True, timeout=20,
        )
        thread.join(timeout=3)
        self.assertFalse(thread.is_alive(), "TLS server did not finish")
        if expect_valid:
            self.assertFalse(errors, errors)
        return result

    def test_verified_https_document_loads(self):
        result = self.request(trusted=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pixel check passed", result.stdout)

    def test_gzip_visual_document_over_verified_tls(self):
        screenshot = self.root / "tls-gzip.png"
        page = b'<style>body{background:#246789}</style><p>HTTPS document</p>'
        result = self.request(trusted=True, body=page, screenshot=screenshot, hold_open=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        local = self.root / "tls-reference.html"
        local.write_bytes(page)
        expected = self.root / "tls-reference.png"
        reference = subprocess.run([str(self.exe), "--screenshot", str(expected), str(local)],
                                   cwd=ROOT, capture_output=True, text=True, timeout=6)
        self.assertEqual(reference.returncode, 0, reference.stdout + reference.stderr)
        self.assertEqual(screenshot.read_bytes(), expected.read_bytes())

    def test_https_document_larger_than_old_transport_limit_loads(self):
        body = b" " * 100_000 + b"<p>Large HTTPS document</p>"
        result = self.request(trusted=True, body=body, clean_close=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"pixel check passed: [1-9][0-9]*\n$")

    def test_length_delimited_body_does_not_wait_for_tls_shutdown(self):
        result = self.request(trusted=True, hold_open=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pixel check passed", result.stdout)

    def test_http11_chunked_gzip_does_not_wait_for_tls_shutdown(self):
        binary = self.root / "tls11"
        build = subprocess.run([str(ROOT / "volt"), "tests/fixtures/browser_tls11.volt", "-o", str(binary)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        result = self.request(trusted=True, body=b"<p>Framed over HTTPS</p>", hold_open=True, tls11=binary)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_close_delimited_body_requires_authenticated_tls_shutdown(self):
        clean = self.request(trusted=True, length=False, clean_close=True)
        self.assertEqual(clean.returncode, 0, clean.stderr)
        self.assertIn("pixel check passed", clean.stdout)
        abrupt = self.request(trusted=True, length=False)
        self.assertNotEqual(abrupt.returncode, 0)

    def test_system_config_cannot_allow_unauthenticated_eof(self):
        config = self.root / "ignore-eof.cnf"
        config.write_text("openssl_conf = init\n[init]\nssl_conf = ssl_conf\n"
                          "[ssl_conf]\nsystem_default = tls\n[tls]\nOptions = IgnoreUnexpectedEOF\n",
                          encoding="ascii")
        result = self.request(trusted=True, length=False, config=config)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertNotIn("pixel check passed", result.stdout)

    def test_untrusted_certificate_is_rejected(self):
        result = self.request(trusted=False, expect_valid=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("pixel check passed", result.stdout)

    def test_certificate_for_another_hostname_is_rejected(self):
        result = self.request(trusted=True, host="localhost", expect_valid=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertNotIn("pixel check passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
