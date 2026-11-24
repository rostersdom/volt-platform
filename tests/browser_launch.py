#!/usr/bin/env python3
"""Check the native VOLT browser's command-line entry point."""
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class BrowserLaunchTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temporary = tempfile.TemporaryDirectory(prefix="volt-browser-launch-")
        cls.addClassCleanup(temporary.cleanup)
        cls.directory = Path(temporary.name)
        cls.browser = cls.directory / "browser"
        build = subprocess.run([str(ROOT / "volt"), str(ROOT / "browser/browser.volt"), "-o", str(cls.browser)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        if build.returncode:
            raise RuntimeError(build.stdout + build.stderr)

    def run_browser(self, *args, cwd=ROOT):
        return subprocess.run([str(self.browser), *args], cwd=cwd, env={"PATH": ""},
                              capture_output=True, text=True, timeout=10)

    def test_default_page_is_available_outside_project_directory(self):
        fallback = self.run_browser("--check", cwd=self.directory)
        home = self.run_browser("--check", "about:home", cwd=self.directory)
        self.assertEqual(fallback.returncode, 0, fallback.stderr)
        self.assertEqual(home.returncode, 0, home.stderr)
        self.assertEqual(fallback.stdout, home.stdout)
        self.assertRegex(home.stdout, r"pixel check passed: [1-9][0-9]*\n$")

    def test_native_check_opens_literal_paths_with_spaces_or_percent_escapes(self):
        space = self.directory / "a page.html"
        percent = self.directory / "a%20page.html"
        space.write_text("<p>VOLT Browser</p>", encoding="ascii")
        percent.write_text("<p>VOLT Browser</p><p>Literal percent in filename</p>", encoding="ascii")
        plain = self.run_browser("--check", str(space))
        encoded = self.run_browser("--check", str(percent))
        for result in (plain, encoded):
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertRegex(result.stdout, r"pixel check passed: [1-9][0-9]*\n$")
        self.assertNotEqual(plain.stdout, encoded.stdout)

    def test_unsupported_schemes_and_extra_arguments_return_usage_status(self):
        for arguments in (("javascript:alert(1)",), ("file:///tmp/page.html",),
                          ("--check", "one.html", "extra"), ("one.html", "extra")):
            with self.subTest(arguments=arguments):
                result = self.run_browser(*arguments)
                self.assertEqual(result.returncode, 2, result.stderr)
                self.assertEqual(result.stdout, "")

    def test_youtube_watch_and_share_urls_open_the_same_local_view(self):
        targets = ("https://www.youtube.com/watch?v=AbC_123-xyz",
                   "https://youtu.be/AbC_123-xyz?si=discard&t=8",
                   "about:youtube:AbC_123-xyz")
        images = []
        for index, target in enumerate(targets):
            output = self.directory / f"youtube-{index}.png"
            result = self.run_browser("--js", "--screenshot", str(output), target, cwd=self.directory)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(result.stderr, "")
            images.append(output.read_bytes())
        self.assertEqual(images, [images[0]] * len(targets))

    def test_window_closes_while_waiting_for_a_response(self):
        with socket.create_server(("127.0.0.1", 0)) as server:
            server.settimeout(8)
            url = f"http://127.0.0.1:{server.getsockname()[1]}/slow"
            env = {**os.environ, "SDL_VIDEODRIVER": "dummy", "SDL_NO_SIGNAL_HANDLERS": "0"}
            with subprocess.Popen([str(self.browser), url], cwd=ROOT, env=env,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) as browser:
                try:
                    connection, _ = server.accept()
                    with connection:
                        browser.send_signal(signal.SIGINT)
                        output, errors = browser.communicate(timeout=3)
                        self.assertEqual((browser.returncode, output, errors), (0, "", ""))
                finally:
                    if browser.poll() is None:
                        browser.kill()
                        browser.communicate()


if __name__ == "__main__":
    unittest.main()
