#!/usr/bin/env python3
"""Loopback integration and validation tests for vstd/http.volt."""
import os
import socket
import subprocess
import tempfile
import threading
import time
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCC = os.path.join(ROOT, "volt")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "http_fixture.volt")
EXPECTED = b"HTTP/1.0 200 OK\r\nContent-Length: 5\r\nConnection: close\r\n\r\nVOLT!"


class HttpIntegration(unittest.TestCase):
    def run_fixture(self, source, server=None):
        with tempfile.TemporaryDirectory(prefix="volt-http-") as tmp:
            src = os.path.join(tmp, "client.volt")
            with open(src, "w", encoding="utf-8") as f:
                f.write(source)
            built = subprocess.run([VCC, src, "-o", os.path.join(tmp, "client")],
                                   capture_output=True, text=True, timeout=20, cwd=ROOT)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            if server is None:
                return subprocess.run([os.path.join(tmp, "client")], capture_output=True,
                                      text=True, timeout=5)
            return server(os.path.join(tmp, "client"))

    def test_validates_arguments_without_networking(self):
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  '        print(http_get_ipv4("127.0.0.1\\r\\nX: y", 80, "/", &response))\n'
                  '        print(http_get_ipv4("127.0.0.1", 0, "/", &response))\n'
                  '        print(http_get_ipv4("127.0.0.1", 80, "/x\\r\\nY: z", &response))\n'
                  '        print(http_get_ipv4("127.0.0.1", 80, "/a b", &response))\n'
                  '        print(http_get_ipv4("127.0.0.1", 80, "/a\\tb", &response))\n'
                  '        let control_path: [5]char\n'
                  '        control_path[0] = \'/\'\n        control_path[1] = \'a\'\n'
                  '        control_path[2] = 1 as char\n        control_path[3] = \'b\'\n'
                  '        control_path[4] = \'\\0\'\n'
                  '        let control_ptr: ptr<char> = &control_path[0]\n'
                  '        print(http_get_ipv4("127.0.0.1", 80, control_ptr as string, &response))\n'
                  '        print(http_get_ipv4("127.0.0.1", 80, "/a#frag", &response))\n'
                  '        bytes_free(&response)\n    return 0\n')
        result = self.run_fixture(source)
        self.assertEqual((result.returncode, result.stdout),
                         (0, "-22\n-22\n-22\n-22\n-22\n-22\n-22\n"))

    def test_hostname_resolver_returns_ipv4_and_unknown_fails_cleanly(self):
        source = ('use dns\nfn main() -> i64:\n    unsafe:\n'
                  '        let address: [4]u8\n'
                  '        print(dns_resolve_ipv4("localhost", &address[0]), address[0], address[1], address[2], address[3])\n'
                  '        print(dns_resolve_ipv4("volt-host-that-does-not-exist.invalid", &address[0]))\n'
                  '    return 0\n')
        result = self.run_fixture(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = result.stdout.splitlines()
        self.assertRegex(lines[0], r"0 (127|0) 0 0 1")
        self.assertEqual(lines[1], "-2")

    def test_explicit_address_transports_reject_invalid_host_before_connecting(self):
        with socket.create_server(("127.0.0.1", 0)) as listener:
            port = listener.getsockname()[1]
            source = f'''use tls
unsafe:
    let response: ByteBuffer
    defer bytes_free(&response)
    let address: [4]u8 = [127, 0, 0, 1]
    print(http_get_address("bad host", {port}, "/", &address[0], &response))
    print(tls_http_get_ipv4("bad\\r\\nname", {port}, "/", &address[0], &response))
'''
            result = self.run_fixture(source)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "-22\n-22\n", ""))
            listener.setblocking(False)
            with self.assertRaises(BlockingIOError):
                listener.accept()

    def test_exact_http_request_and_response(self):
        def serve(executable):
            listener = socket.socket()
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            port = listener.getsockname()[1]
            listener.close()
            listener = socket.socket()
            listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            listener.bind(("127.0.0.1", port))
            listener.listen(1)
            observed = []
            def service():
                conn, _ = listener.accept()
                with conn:
                    data = b""
                    while b"\r\n\r\n" not in data:
                        part = conn.recv(3)
                        if not part:
                            break
                        data += part
                    observed.append(data)
                    for piece in (EXPECTED[:9], EXPECTED[9:34], EXPECTED[34:]):
                        conn.sendall(piece)
                listener.close()
            thread = threading.Thread(target=service, daemon=True)
            thread.start()
            with open(FIXTURE, encoding="utf-8") as f:
                source = f.read().replace("HTTP_TEST_PORT", str(port))
            with tempfile.TemporaryDirectory(prefix="volt-http-client-") as tmp:
                src = os.path.join(tmp, "fixture.volt")
                exe = os.path.join(tmp, "client")
                with open(src, "w", encoding="utf-8") as f:
                    f.write(source)
                built = subprocess.run([VCC, src, "-o", exe], capture_output=True,
                                       text=True, timeout=20, cwd=ROOT)
                if built.returncode:
                    raise AssertionError(built.stdout + built.stderr)
                result = subprocess.run([exe], capture_output=True, text=True, timeout=5)
            thread.join(timeout=2)
            self.assertEqual(observed, [b"GET /x?y=1 HTTP/1.0\r\nHost: 127.0.0.1:" +
                                        str(port).encode() + b"\r\nConnection: close\r\n\r\n"])
            return result
        result = serve(None)
        self.assertEqual((result.returncode, result.stdout, result.stderr),
                         (0, f"HTTP response verified {len(EXPECTED)}\n", ""))

    def test_reused_response_clears_stale_length_on_invalid_port(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        observed = []

        def service():
            conn, _ = listener.accept()
            with conn:
                request = b""
                while b"\r\n\r\n" not in request:
                    piece = conn.recv(1024)
                    if not piece:
                        break
                    request += piece
                observed.append(request)
                conn.sendall(EXPECTED)
            listener.close()

        thread = threading.Thread(target=service, daemon=True)
        thread.start()
        with open(os.path.join(ROOT, "tests", "fixtures", "http_reuse_fixture.volt"),
                  encoding="utf-8") as f:
            source = f.read().replace("HTTP_TEST_PORT", str(port))
        try:
            result = self.run_fixture(source)
        finally:
            thread.join(timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout,
                         f"first {len(EXPECTED)} {len(EXPECTED)}\nsecond -22 0\n")
        self.assertEqual(len(observed), 1)

    def test_response_limit_retains_prefix_and_closes_connection(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        observed_close = []
        def service():
            conn, _ = listener.accept()
            with conn:
                request = b""
                while b"\r\n\r\n" not in request:
                    piece = conn.recv(1024)
                    if not piece:
                        break
                    request += piece
                conn.sendall(b"X" * 65537)
                try:
                    while conn.recv(4096):
                        pass
                except OSError:
                    pass
                observed_close.append(True)
            listener.close()
        thread = threading.Thread(target=service, daemon=True)
        thread.start()
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  f'        let result: i64 = http_get_ipv4("127.0.0.1", {port}, "/", &response)\n'
                  '        print(result, response.len)\n'
                  '        bytes_free(&response)\n    return 0\n')
        try:
            result = self.run_fixture(source)
        finally:
            thread.join(timeout=3)
        self.assertEqual((result.returncode, result.stdout), (0, "-90 65536\n"))
        self.assertEqual(observed_close, [True])

    def test_peer_close_during_request_does_not_raise_sigpipe(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        def service():
            conn, _ = listener.accept()
            conn.close()
            listener.close()
        thread = threading.Thread(target=service, daemon=True)
        thread.start()
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  f'        let result: i64 = http_get_ipv4("127.0.0.1", {port}, "/", &response)\n'
                  '        print(result)\n        bytes_free(&response)\n    return 0\n')
        result = self.run_fixture(source)
        thread.join(timeout=2)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"(?:-\d+|0)\n")

    def test_connection_refusal_returns_negative_errno(self):
        with socket.socket() as reserve:
            reserve.bind(("127.0.0.1", 0))
            port = reserve.getsockname()[1]
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  f'        print(http_get_ipv4("127.0.0.1", {port}, "/", &response))\n'
                  '        bytes_free(&response)\n    return 0\n')
        result = self.run_fixture(source)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout, r"-111\n")

    def test_read_deadline_expires_and_closes_socket(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        request_seen = threading.Event()
        peer_closed = []

        def service():
            try:
                conn, _ = listener.accept()
                with conn:
                    data = b""
                    while b"\r\n\r\n" not in data:
                        piece = conn.recv(1024)
                        if not piece:
                            break
                        data += piece
                    request_seen.set()
                    conn.sendall(b"HTTP/1.0 200 OK\r\nContent-Length: 8\r\nContent-Type: text/html\r\n\r\n<p>x</p>")
                    try:
                        peer_closed.append(conn.recv(1) == b"")
                    except OSError:
                        peer_closed.append(True)
            finally:
                listener.close()

        thread = threading.Thread(target=service, daemon=True)
        thread.start()
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  f'        let result: i64 = http_get_ipv4_timeout("127.0.0.1", {port}, "/", &response, 150)\n'
                  '        print(result, response.len)\n        bytes_free(&response)\n'
                  '    return 0\n')
        started = time.monotonic()
        result = self.run_fixture(source)
        elapsed = time.monotonic() - started
        thread.join(timeout=2)
        self.assertEqual((result.returncode, result.stdout), (0, "-110 0\n"))
        self.assertLess(elapsed, 2.0)
        self.assertTrue(request_seen.is_set())
        self.assertEqual(peer_closed, [True])

    def test_fragmented_progress_uses_total_deadline(self):
        listener = socket.socket()
        listener.bind(("127.0.0.1", 0))
        listener.listen(1)
        port = listener.getsockname()[1]
        request_seen = threading.Event()
        peer_closed = []

        def service():
            try:
                conn, _ = listener.accept()
                with conn:
                    conn.settimeout(1)
                    data = b""
                    while b"\r\n\r\n" not in data:
                        piece = conn.recv(1024)
                        if not piece:
                            break
                        data += piece
                    request_seen.set()
                    payload = b"HTTP/1.0 200 OK\r\nContent-Length: 20\r\nContent-Type: text/html\r\n\r\n<p>slow response</p>"
                    for byte in payload:
                        try:
                            conn.sendall(bytes([byte]))
                        except OSError:
                            break
                        time.sleep(0.03)
                    try:
                        peer_closed.append(conn.recv(1) == b"")
                    except OSError:
                        peer_closed.append(True)
            finally:
                listener.close()

        thread = threading.Thread(target=service, daemon=True)
        thread.start()
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  f'        let result: i64 = http_get_ipv4_timeout("127.0.0.1", {port}, "/", &response, 150)\n'
                  '        print(result, response.len)\n        bytes_free(&response)\n'
                  '    return 0\n')
        started = time.monotonic()
        result = self.run_fixture(source)
        elapsed = time.monotonic() - started
        thread.join(timeout=2)
        self.assertEqual((result.returncode, result.stdout), (0, "-110 0\n"))
        self.assertLess(elapsed, 2.0)
        self.assertTrue(request_seen.is_set())
        self.assertEqual(peer_closed, [True])

    def test_invalid_timeout_is_rejected_without_connecting(self):
        source = ('use http\nfn main() -> i64:\n    unsafe:\n'
                  '        let response: ByteBuffer\n        bytes_init(&response)\n'
                  '        print(http_get_ipv4_timeout("127.0.0.1", 80, "/", &response, 0), response.len)\n'
                  '        print(http_get_ipv4_timeout("127.0.0.1", 80, "/", &response, -1), response.len)\n'
                  '        bytes_free(&response)\n    return 0\n')
        result = self.run_fixture(source)
        self.assertEqual((result.returncode, result.stdout), (0, "-22 0\n-22 0\n"))


if __name__ == "__main__":
    unittest.main()
