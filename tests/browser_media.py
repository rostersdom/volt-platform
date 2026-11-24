#!/usr/bin/env python3
"""Exercise the VOLT-owned video layout, decoder and audio lifecycle."""
from pathlib import Path
import os
import shutil
import socket
import struct
import subprocess
import tempfile
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import browser_visual


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
MUXED = FIXTURES / "muxed-h264-aac.mp4"  # testsrc2, 10 fps, two one-second fragments, 44.1 kHz sine
DIRECT_MP4 = FIXTURES / "direct-h264-aac.mp4"  # testsrc, 10 fps, two seconds, 44.1 kHz sine
DECODED_BUDGET = FIXTURES / "muxed-decoded-budget.mp4"  # 45 solid-color 960x540 frames and 48 kHz sine
DEPENDENCIES = ("libavformat", "libavcodec", "libavutil", "libswscale", "libswresample", "libseccomp")
HAVE_MEDIA = shutil.which("pkg-config") is not None and subprocess.run(
    ["pkg-config", "--exists", *DEPENDENCIES], check=False
).returncode == 0
MEDIA_PAGE = '''<!doctype html><style>
body {margin:16px; background:#eef2fc}
video {display:block; width:100%; max-width:320px; aspect-ratio:16 / 9;
       border-radius:12px; background:#101827; object-fit:contain}
</style><video controls><source src="clip.webm" type="video/webm"></video>'''


@unittest.skipUnless(HAVE_MEDIA, "optional FFmpeg and libseccomp development packages missing")
class BrowserMedia(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        folder = tempfile.TemporaryDirectory(prefix="volt-media-")
        cls.addClassCleanup(folder.cleanup)
        cls.folder = Path(folder.name)
        cls.binary = cls.folder / "fixture"
        result = subprocess.run(["make", f"BINDIR={cls.folder}", str(cls.folder / "volt-media")],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        result = subprocess.run([str(ROOT / "volt"), "tests/fixtures/browser_media.volt", "-o", str(cls.binary)],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.video = (ROOT / "examples/video-demo.webm").read_bytes()
        cls.stream_fixture = cls.folder / "stream-fixture"
        result = subprocess.run([str(ROOT / "volt"), "tests/fixtures/browser_stream.volt", "-o", str(cls.stream_fixture)],
                                cwd=ROOT, capture_output=True, text=True, timeout=30)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)

    def invoke(self, target, output):
        result = subprocess.run([str(self.binary), str(target), str(output)], cwd=self.folder,
                                env={**os.environ, "PATH": "", "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def assert_frame(self, output):
        screenshot = browser_visual.Screenshot(output)
        self.assertEqual((screenshot.width, screenshot.height), (240, 300))
        self.assertEqual(screenshot.rgb(16, 16), 0xEEF2FC)
        self.assertTrue(any((screenshot.rgb(x, y) & 0xFF00) > 0x7000
                            for y in range(40, 108) for x in range(32, 200)))

    def test_local_playback_audio_pause_resume_and_reflow(self):
        page = self.folder / "video.html"
        page.write_text(MEDIA_PAGE)
        (self.folder / "clip.webm").write_bytes(self.video)
        output = self.folder / "local-frame.png"
        self.invoke(page, output)
        self.assert_frame(output)

    def test_local_mp4_playback_queues_pcm_and_ends(self):
        page = self.folder / "video-mp4.html"
        page.write_text(MEDIA_PAGE.replace("webm", "mp4"))
        shutil.copyfile(DIRECT_MP4, self.folder / "clip.mp4")
        self.invoke_stream([], "direct")

    def test_youtube_view_checks_and_plays_only_on_click(self):
        # Replace only the provider transport; the served bytes, navigation,
        # HTTP validation, player and decoder all follow the production path.
        stage = self.folder / "youtube-fixture"
        shutil.copytree(ROOT / "vstd", stage / "vstd")
        shutil.copy2(ROOT / "volt", stage / "volt")
        shutil.copy2(ROOT / "tests/fixtures/youtube_transport.volt",
                     stage / "vstd/browser_youtube_transport.volt")
        binary = self.folder / "youtube-view"
        build = subprocess.run([str(stage / "volt"), "tests/fixtures/browser_youtube.volt", "-o", str(binary)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(build.returncode, 0, build.stdout + build.stderr)
        result = subprocess.run([str(binary)], cwd=ROOT,
                                env={"PATH": "", "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
                                capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_local_video_cannot_follow_a_symlink_out_of_the_page_directory(self):
        site = self.folder / "confined"
        site.mkdir()
        page = site / "video.html"
        page.write_text(MEDIA_PAGE, encoding="utf-8")
        (site / "clip.webm").symlink_to(ROOT / "examples/video-demo.webm")
        self.invoke(page, "blocked")

    def test_decoder_rejects_non_media_input(self):
        document = self.folder / "not-a-clip.webm"
        document.write_bytes(b"<html>not media</html>")
        browser, decoder = socket.socketpair()
        browser.settimeout(3)
        with browser, decoder, document.open("rb") as source, subprocess.Popen(
                [str(self.folder / "volt-media")], stdin=decoder, stdout=source, env={}) as worker:
            decoder.close()
            self.assertEqual(browser.recv(40), b"")
            self.assertEqual(worker.wait(timeout=3), 1)

    @unittest.skipUnless(shutil.which("ffmpeg"), "FFmpeg CLI not available for fixture remux")
    def test_youtube_decoder_requires_a_combined_file(self):
        for stream in ("v", "a"):
            with self.subTest(stream=stream):
                source_path = self.folder / f"separate-{stream}.webm"
                remux = subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-i", str(ROOT / "examples/video-demo.webm"),
                                        "-map", f"0:{stream}", "-c", "copy", str(source_path)],
                                       capture_output=True, text=True, timeout=10)
                self.assertEqual(remux.returncode, 0, remux.stdout + remux.stderr)
                browser, decoder = socket.socketpair()
                browser.settimeout(3)
                with browser, decoder, source_path.open("rb") as source, subprocess.Popen(
                        [str(self.folder / "volt-media"), "--combined"], stdin=decoder, stdout=source, env={}) as worker:
                    decoder.close()
                    self.assertEqual(browser.recv(40), b"")
                    self.assertEqual(worker.wait(timeout=3), 1)

    def test_decoder_timestamps_and_end_packet(self):
        browser, decoder = socket.socketpair()
        browser.settimeout(4)
        with browser, decoder, (ROOT / "examples/video-demo.webm").open("rb") as source, subprocess.Popen(
                [str(self.folder / "volt-media")], stdin=decoder, stdout=source, env={}) as worker:
            decoder.close()
            counts = {1: 0, 2: 0, 3: 0, 4: 0}
            with browser.makefile("rb") as stream:
                while True:
                    header = stream.read(40)
                    self.assertEqual(len(header), 40)
                    kind, size, width, height, pts = struct.unpack("<5q", header)
                    counts[kind] += 1
                    if kind == 3:
                        self.assertEqual((size, width, height), (0, 0, 0))
                        break
                    if kind == 4:
                        self.assertGreaterEqual(pts, 6000)
                        self.assertEqual(size, 0)
                    else:
                        self.assertGreaterEqual(pts, 0)
                        self.assertGreater(size, 0)
                        self.assertLessEqual(size, 960 * 540 * 4)
                        self.assertEqual(len(stream.read(size)), size)
            self.assertGreater(counts[1], 100)
            self.assertGreater(counts[2], 100)
            self.assertEqual((counts[3], counts[4], worker.wait(timeout=3)), (1, 1, 0))

    def video_only_fmp4(self):
        ffmpeg = shutil.which("ffmpeg")
        if not ffmpeg:
            self.skipTest("FFmpeg CLI not available for fMP4 fixture")
        encoders = subprocess.run([ffmpeg, "-hide_banner", "-encoders"], capture_output=True, text=True,
                                  check=True, timeout=5).stdout
        if "libx264" not in encoders:
            self.skipTest("FFmpeg libx264 not available for fMP4 fixture")
        result = subprocess.run([ffmpeg, "-nostdin", "-v", "error", "-f", "lavfi", "-i",
                                 "testsrc2=size=320x180:rate=10:duration=2", "-vf", "noise=alls=28:allf=t+u:all_seed=4",
                                 "-c:v", "libx264", "-threads", "1", "-preset", "ultrafast", "-tune", "zerolatency", "-crf", "0",
                                 "-pix_fmt", "yuv420p", "-g", "10", "-keyint_min", "10",
                                 "-sc_threshold", "0", "-video_track_timescale", "10240",
                                 "-movflags", "+empty_moov+frag_keyframe+default_base_moof+skip_trailer",
                                 "-f", "mp4", "pipe:1"], capture_output=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        return result.stdout

    def mp4_boxes(self, data, at=0, end=None):
        end = len(data) if end is None else end
        while at < end:
            length, kind = struct.unpack_from(">I4s", data, at)
            self.assertGreaterEqual(length, 8)
            self.assertLessEqual(at + length, end)
            yield kind, at, at + length
            at += length

    def fmp4_parts(self, data, fragments=2):
        boxes = list(self.mp4_boxes(data))
        self.assertEqual([box[0] for box in boxes], [b"ftyp", b"moov"] + [b"moof", b"mdat"] * fragments)
        return [bytearray(data[boxes[i][1]:boxes[i + 1][2]]) for i in range(0, len(boxes), 2)]

    def fragment_runs(self, data):
        moof, _ = self.mp4_boxes(data)
        for kind, start, end in self.mp4_boxes(data, moof[1] + 8, moof[2]):
            if kind == b"traf":
                yield {kind: start for kind, start, _ in self.mp4_boxes(data, start + 8, end)}

    def shift_fmp4(self, parts):
        # The first decoded track is video but AAC starts 20 ms earlier.
        for part in parts[1:]:
            for run in self.fragment_runs(part):
                track, = struct.unpack_from(">I", part, run[b"tfhd"] + 12)
                tfdt = run[b"tfdt"]
                self.assertEqual(part[tfdt + 8], 1)
                timestamp, = struct.unpack_from(">Q", part, tfdt + 12)
                shift = 8 * 10240 if track == 1 else 7980 * 44100 // 1000
                struct.pack_into(">Q", part, tfdt + 12, timestamp + shift)

    def invoke_stream(self, parts, *args):
        for name, data in zip(("init.bin", "media-1.bin", "media-2.bin"), parts):
            (self.folder / name).write_bytes(data)
        result = subprocess.run([str(self.stream_fixture), *args], cwd=self.folder,
                                env={"PATH": "", "SDL_VIDEODRIVER": "dummy", "SDL_AUDIODRIVER": "dummy"},
                                capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_fragmented_mp4_renders_before_end_and_resumes_after_starvation(self):
        parts = self.fmp4_parts(self.video_only_fmp4())
        self.assertTrue(all(262144 < len(data) <= 1048576 for data in parts[1:]))
        self.shift_fmp4(parts)
        self.invoke_stream(parts)
        image = browser_visual.Screenshot(self.folder / "stream-frame.png")
        self.assertGreater(len({image.rgb(x, y) for x in range(20, 280, 12) for y in range(20, 150, 10)}), 10)

    def test_muxed_fmp4_renders_and_queues_pcm_before_next_append(self):
        parts = self.fmp4_parts(MUXED.read_bytes())
        self.shift_fmp4(parts)
        self.invoke_stream(parts, "audio")
        image = browser_visual.Screenshot(self.folder / "stream-frame.png")
        self.assertGreater(len({image.rgb(x, y) for x in range(20, 280, 12) for y in range(20, 150, 10)}), 10)

    def test_muxed_fmp4_limits_decoded_bytes_per_append(self):
        parts = self.fmp4_parts(DECODED_BUDGET.read_bytes(), fragments=1)
        self.assertLess(len(parts[1]), 1048576)
        self.invoke_stream(parts, "budget")

    def test_muxed_fmp4_worker_decodes_non_silent_resampled_pcm_before_next_append(self):
        init, media, _ = parts = self.fmp4_parts(MUXED.read_bytes())
        self.shift_fmp4(parts)
        browser, decoder = socket.socketpair()
        browser.settimeout(4)
        credit = struct.pack("<5q", 5, 0, 0, 0, 0)
        with subprocess.Popen([str(self.folder / "volt-media"), "--stream-fmp4"], stdin=decoder, env={}) as worker, \
                browser, decoder, browser.makefile("rb") as stream:
            decoder.close()
            self.assertEqual(stream.read(40), credit)
            browser.sendall(struct.pack("<q", len(init)) + init)
            self.assertEqual(stream.read(40), credit)
            browser.sendall(struct.pack("<q", len(media)) + media)
            self.assertEqual(stream.read(40), struct.pack("<5q", 6, 0, 0, 0, 0))
            frames, pcm_pts, pcm_bytes, nonzero = [], [], 0, False
            while (header := stream.read(40)) != credit:
                self.assertEqual(len(header), 40)
                kind, size, width, height, pts = struct.unpack("<5q", header)
                if kind == 1:
                    self.assertEqual((size, width, height), (320 * 180 * 4, 320, 180))
                    frames.append(pts)
                else:
                    self.assertEqual((kind, size % 4, width, height), (2, 0, 0, 0))
                    self.assertTrue(0 < size <= 32768)
                    pcm_pts.append(pts)
                    pcm_bytes += size
                data = stream.read(size)
                self.assertEqual(len(data), size)
                if kind == 2:
                    nonzero |= any(data)
            self.assertEqual((len(frames), frames[0], pcm_pts[0]), (10, 8000, 7980))
            self.assertEqual(pcm_pts, sorted(pcm_pts))
            self.assertTrue(nonzero)
            self.assertTrue(49000 <= pcm_bytes // 4 <= 51000, pcm_bytes)
            # Neither the second fragment nor EOF was sent.
            browser.shutdown(socket.SHUT_WR)
            self.assertEqual(worker.wait(timeout=3), 1)

    def test_muxed_fmp4_worker_limits_total_input(self):
        init, media, _ = self.fmp4_parts(MUXED.read_bytes())
        moof, mdat = self.mp4_boxes(media)
        runs = list(self.fragment_runs(media))
        mfhd = next(start for kind, start, _ in self.mp4_boxes(media, 8, moof[2]) if kind == b"mfhd")
        limit = 1048576
        struct.pack_into(">I", media, mdat[1], limit - mdat[1])
        media.extend(bytes(limit - len(media)))
        browser, decoder = socket.socketpair()
        browser.settimeout(4)
        credit = struct.pack("<5q", 5, 0, 0, 0, 0)
        size = struct.pack("<q", len(media))
        with subprocess.Popen([str(self.folder / "volt-media"), "--stream-fmp4"], stdin=decoder, env={}) as worker, \
                browser, decoder, browser.makefile("rb") as stream:
            decoder.close()
            self.assertEqual(stream.read(40), credit)
            browser.sendall(struct.pack("<q", len(init)) + init)
            self.assertEqual(stream.read(40), credit)
            for i in range(31):
                struct.pack_into(">I", media, mfhd + 12, i + 1)
                for run, delta in zip(runs, (10240, 46080)):
                    struct.pack_into(">Q", media, run[b"tfdt"] + 12, i * delta)
                browser.sendall(size + media)
                while (header := stream.read(40)) != credit:
                    self.assertEqual(len(header), 40)
                    length, = struct.unpack_from("<q", header, 8)
                    self.assertTrue(0 <= length <= 320 * 180 * 4)
                    self.assertEqual(len(stream.read(length)), length)
            browser.sendall(size)  # 32 full appends plus init would exceed 32 MiB.
            self.assertEqual(stream.read(40), b"")
            self.assertEqual(worker.wait(timeout=3), 1)

    def test_fragmented_mp4_worker_rejects_bad_appends(self):
        init, media, _ = self.fmp4_parts(self.video_only_fmp4())
        other_track = bytearray(media)
        struct.pack_into(">I", other_track, media.index(b"tfhd") + 8, 2)
        empty_run = bytearray(media)
        struct.pack_into(">I", empty_run, media.index(b"trun") + 8, 0)
        audio_init, muxed, _ = self.fmp4_parts(MUXED.read_bytes())
        duplicate_run = muxed[:]
        audio_run = list(self.fragment_runs(duplicate_run))[1]
        struct.pack_into(">I", duplicate_run, audio_run[b"tfhd"] + 12, 1)
        undeclared_audio = muxed[:]
        struct.pack_into(">I", undeclared_audio, audio_run[b"tfhd"] + 12, 3)
        protected_audio = audio_init.replace(b"mp4a", b"enca", 1)
        for label, payloads in (("media first", [media]), ("truncated media", [init, media[:-1]]),
                                ("unexpected track", [init, other_track]), ("empty run", [init, empty_run]),
                                ("duplicate muxed track", [audio_init, duplicate_run]),
                                ("undeclared audio track", [audio_init, undeclared_audio]),
                                ("protected audio sample entry", [protected_audio, muxed]),
                                ("over budget", [None]), ("end before init", [b""])):
            with self.subTest(label=label):
                browser, decoder = socket.socketpair()
                browser.settimeout(4)
                with subprocess.Popen([str(self.folder / "volt-media"), "--stream-fmp4"], stdin=decoder, env={}) as worker, \
                        browser, decoder:
                    decoder.close()
                    with browser.makefile("rb") as stream:
                        for data in payloads:
                            self.assertEqual(stream.read(40), struct.pack("<5q", 5, 0, 0, 0, 0))
                            length = len(data) if data is not None else 1048577
                            browser.sendall(struct.pack("<q", length) + (data or b""))
                        self.assertEqual(stream.read(40), b"")
                    self.assertEqual(worker.wait(timeout=3), 1)

    def test_http_media_requests_are_click_driven_and_confined(self):
        requested, redirected = [], []

        class Other(BaseHTTPRequestHandler):
            def do_GET(self):
                redirected.append(self.path)
                self.send_error(404)

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                requested.append(self.path)
                if self.path == "/redirect/clip.webm":
                    self.send_response(302)
                    self.send_header("Location", forbidden)
                    self.send_header("Content-Length", "0")
                    self.end_headers()
                    return
                is_video = self.path == "/clip.webm"
                data = video if is_video else MEDIA_PAGE.encode()
                self.send_response(200)
                self.send_header("Content-Type", "video/webm" if is_video else "text/html")
                self.send_header("Content-Length", str(len(data)))
                if self.path == "/blocked/":
                    self.send_header("Content-Security-Policy", "media-src 'none'")
                self.end_headers()
                self.wfile.write(data)

            def log_message(self, *_):
                pass

        video = self.video
        with ThreadingHTTPServer(("127.0.0.1", 0), Other) as other:
            forbidden = f"http://127.0.0.1:{other.server_port}/private.webm"
            with ThreadingHTTPServer(("127.0.0.1", 0), Handler) as server:
                with browser_visual.BrowserVisual.running(other), browser_visual.BrowserVisual.running(server):
                    origin = f"http://127.0.0.1:{server.server_port}"
                    self.invoke(origin + "/blocked/", "blocked")
                    self.invoke(origin + "/redirect/", "blocked")
                    output = self.folder / "http-frame.png"
                    self.invoke(origin + "/", output)
                    self.assert_frame(output)
        self.assertEqual(requested, ["/blocked/", "/redirect/", "/redirect/clip.webm", "/", "/clip.webm"])
        self.assertEqual(redirected, [])


if __name__ == "__main__":
    unittest.main()
