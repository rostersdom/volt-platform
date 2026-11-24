#!/usr/bin/env python3
"""Exercise the window's renderer through the headless screenshot entry point."""
import base64
from contextlib import contextmanager
import ctypes
import gzip
import http.server
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import threading
import unittest
import zlib


ROOT = Path(__file__).resolve().parent.parent
JPEG = base64.b64decode(
    "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAQDAwQDAwQEAwQFBAQFBgoHBgYGBg0J"
    "CggKDw0QEA8NDw4RExgUERIXEg4PFRwVFxkZGxsbEBQdHx0aHxgaGxr/2wBDAQQF"
    "BQYFBgwHBwwaEQ8RGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoaGhoa"
    "GhoaGhoaGhoaGhoaGhr/wAARCAAEAAQDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAA"
    "AAAAAAAAAAb/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAA"
    "AAAABgf/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCVAWAFf//Z"
)
WEBP = base64.b64decode("UklGRh4AAABXRUJQVlA4TBEAAAAvA8AAAAfQtwoVuP+BiOh/AAA=")


def png_chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))


def square_png(width=4, height=4):
    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    scanline = b"\0" + b"\x08\x98\xb0\xff" * 4
    return (b"\x89PNG\r\n\x1a\n" + png_chunk(b"IHDR", header)
            + png_chunk(b"IDAT", zlib.compress(scanline * 4)) + png_chunk(b"IEND", b""))


class Screenshot:
    cairo = ctypes.CDLL("libcairo.so.2")
    signatures = {
        "cairo_image_surface_create_from_png": ([ctypes.c_char_p], ctypes.c_void_p),
        "cairo_surface_status": ([ctypes.c_void_p], ctypes.c_int),
        "cairo_surface_flush": ([ctypes.c_void_p], None),
        "cairo_image_surface_get_data": ([ctypes.c_void_p], ctypes.POINTER(ctypes.c_uint32)),
        "cairo_image_surface_get_stride": ([ctypes.c_void_p], ctypes.c_int),
        "cairo_image_surface_get_width": ([ctypes.c_void_p], ctypes.c_int),
        "cairo_image_surface_get_height": ([ctypes.c_void_p], ctypes.c_int),
        "cairo_surface_destroy": ([ctypes.c_void_p], None),
    }
    for name, (args, result) in signatures.items():
        func = getattr(cairo, name)
        func.argtypes, func.restype = args, result

    def __init__(self, path):
        c = self.cairo
        image = c.cairo_image_surface_create_from_png(os.fsencode(path))
        try:
            if c.cairo_surface_status(image):
                raise ValueError(f"could not decode screenshot {path}")
            self.width = c.cairo_image_surface_get_width(image)
            self.height = c.cairo_image_surface_get_height(image)
            self.stride = c.cairo_image_surface_get_stride(image) // 4
            c.cairo_surface_flush(image)
            self.pixels = c.cairo_image_surface_get_data(image)[:self.stride * self.height]
        finally:
            c.cairo_surface_destroy(image)

    def rgb(self, x, y):
        return self.pixels[y * self.stride + x] & 0xFFFFFF


class BrowserVisual(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        temp = tempfile.TemporaryDirectory(prefix="volt-visual-")
        cls.addClassCleanup(temp.cleanup)
        cls.directory = Path(temp.name)
        cls.binary = cls.directory / "browser"
        subprocess.run([str(ROOT / "volt"), "apps/browser.volt", "-o", str(cls.binary)],
                       cwd=ROOT, timeout=30, check=True, capture_output=True)

    def setUp(self):
        temp = tempfile.TemporaryDirectory(dir=self.directory)
        self.addCleanup(temp.cleanup)
        self.site = Path(temp.name)

    def render(self, page, fragment=""):
        if not str(page).startswith("http"):
            local = self.site / "index.html"
            local.write_text(page, encoding="utf-8")
            page = local
        output = self.site / "frame.png"
        rendered = subprocess.run([str(self.binary), "--screenshot", str(output), str(page) + fragment],
                                  cwd=self.site, capture_output=True, text=True, timeout=6)
        self.assertEqual(rendered.returncode, 0, rendered.stdout + rendered.stderr)
        image = Screenshot(output)
        self.assertEqual((image.width, image.height), (640, 480))
        return image

    def test_linked_cascade_grid_media_and_png(self):
        (self.site / "theme.css").write_text('''
* { box-sizing: border-box; }
body { margin: 0; background: #f3f4f5; }
main { max-width: 420px; margin: 20px auto; padding: 10px; background: #d7e3ef; }
.cards { display:grid; grid-template-columns:repeat(2, 1fr); gap: 10px; }
article { min-height: 42px; padding: 6px; background: #ff0000; }
@media screen and (min-width: 600px) and (max-width: 650px) { article { background: rgb(32, 104, 153); } }
@media (max-width: 500px) { article { background: black; } }
''', encoding="utf-8")
        (self.site / "mark.png").write_bytes(square_png())
        image = self.render('''<link rel="stylesheet" href="theme.css?version=1">
<style>article + article { color: red } .second { background: #e29a4f; }</style>
<body><main><section class="cards"><article>A</article><article class="second">B</article></section>
<img src="mark.png" width="42" height="32" alt="Mark"></main></body>''')
        self.assertEqual(image.rgb(10, 10), 0xF3F4F5)
        self.assertEqual(image.rgb(112, 22), 0xD7E3EF)
        self.assertEqual(image.rgb(175, 56), 0x206899)
        self.assertEqual(image.rgb(385, 56), 0xE29A4F)
        self.assertEqual(image.rgb(319, 56), 0xD7E3EF)
        self.assertEqual(image.rgb(139, 87), 0x0898B0)

    def test_font_metrics_and_text_alignment(self):
        image = self.render('''<style>body { margin:0; }
.sample { font: normal; font-family: sans-serif; font-size: 32px; line-height: 48px; margin:0; text-align:center; }
</style><body><p class="sample">WWWW</p><p class="sample">iiii</p></body>''')
        def text_bounds(y_start):
            xs = [x for x in range(image.width) for y in range(y_start, y_start + 48)
                  if image.rgb(x, y) < 0x808080]
            return min(xs), max(xs)
        wide, thin = text_bounds(0), text_bounds(48)
        self.assertGreater(wide[1] - wide[0], 2 * (thin[1] - thin[0]))
        for left, right in (wide, thin):
            self.assertLess(abs((left + right) / 2 - 320), 3)

    def test_font_shorthand_and_light_color_match_longhands(self):
        sample = '<body><p style="margin:0">Proportional text</p></body>'
        shorthand = self.render('''<style>html{background:light-dark(#edf2f7, #162433)}
body {margin:0; padding-top:25vh; font:italic 700 20px/1.5 system-ui, sans-serif}</style>''' + sample)
        longhands = self.render('''<style>html{background:#edf2f7}
body {margin:0; padding-top:120px; font-style:italic; font-weight:700;
font-size:20px; line-height:30px; font-family:system-ui, sans-serif}</style>''' + sample)
        self.assertEqual(shorthand.pixels, longhands.pixels)
        self.assertEqual(shorthand.rgb(12, 12), 0xEDF2F7)
        self.assertTrue(any(shorthand.rgb(x, y) < 0x808080 for x in range(220) for y in range(120, 150)))

    def test_adjacent_sibling_and_attribute_selectors_in_the_cascade(self):
        image = self.render('''<style>
body { margin:0 }
h2, .card { margin:0; height:20px }
.card { background:#334455 }
h2 + .card[DATA-TONE = "blue sky" i] { background:#2266aa }
h2 ~ .card[aria-current] { background:#126633 }
article[data-label="x.#"] { background:#773399 }
article[data-label] { background:#995533 }
#CAPS { background:#aa4433 }
.outer > .branch .card { background:#cc2255 }
article[data-label="hot&cold"] { background:#d89922 }
article[data-label="hot&amp;cold"] { background:#112244 }
</style><h2></h2>\n<article class="card" data-tone="Blue Sky"></article>
<div></div><article class="card" aria-current></article>
<article class="card" id="caps" data-label="x.#"></article>
<section class="outer"><div class="branch"><div class="branch"><p class="card"></p></div></div></section>
<article class="card" data-label="hot&amp;cold"></article>''')
        self.assertEqual([image.rgb(10, y) for y in (30, 50, 70, 90, 110)],
                         [0x2266AA, 0x126633, 0x995533, 0xCC2255, 0xD89922])

    def test_implicit_document_elements_apply_body_and_child_styles(self):
        style = "<style>body {margin:0; background:#dde7ec} html > body > p {margin:0; background:#a67c43}</style>"
        implicit = self.render(style + "<p>First paragraph</p>")
        explicit = self.render("<html><head>" + style + "</head><body><p>First paragraph</p></body></html>")
        self.assertEqual(implicit.pixels, explicit.pixels)
        self.assertEqual(implicit.rgb(500, 4), 0xA67C43)
        self.assertEqual(implicit.rgb(500, 50), 0xDDE7EC)

    def test_empty_inline_anchor_retains_its_flow_position(self):
        page = '''<style>body{margin:0} .before{height:520px;background:#222244}
.after{height:640px;background:#669966}</style><div class="before"></div>
<a id="section"></a><div class="after"></div>'''
        self.assertEqual(self.render(page).rgb(12, 12), 0x222244)
        self.assertEqual(self.render(page, "#section").rgb(12, 12), 0x669966)

    def test_table_cells_share_columns_and_pre_preserves_newlines(self):
        image = self.render('''<style>body {margin:0}
table {width:300px} td {height:32px}
.red {background:#bb3344} .blue {background:#5588cc}
pre {padding:0; margin:0; color:black; font:normal; font-size:20px; line-height:24px}
</style><table><tbody><tr><td class="red"></td><td class="blue"></td></tr>
<tr><td class="blue"></td><td class="red"></td></tr></tbody></table>
<pre>      X\nX</pre>''')
        self.assertEqual(image.rgb(20, 15), 0xBB3344)
        self.assertEqual(image.rgb(160, 15), 0x5588CC)
        self.assertEqual(image.rgb(20, 45), 0x5588CC)
        self.assertEqual(image.rgb(160, 45), 0xBB3344)
        first = {x for x in range(110) for y in range(64, 88) if image.rgb(x, y) < 0x808080}
        second = {x for x in range(110) for y in range(88, 112) if image.rgb(x, y) < 0x808080}
        self.assertTrue(first and second)
        self.assertGreater(min(first), max(second) + 32)

    def test_invalid_color_falls_back_and_transparent_border_keeps_spacing(self):
        image = self.render('''<style>body { margin:0; background:#edf5ff; }
section { width:70px; height:30px; border:4px solid transparent; }
section { background:#558899; background:rgb(0, 128 255); }
</style><section></section><button>OK</button>''')
        self.assertEqual(image.rgb(1, 1), 0x558899)
        self.assertEqual(image.rgb(12, 12), 0x558899)
        self.assertEqual(image.rgb(8, 43), 0xEFEFEF)
        self.assertEqual(image.rgb(160, 43), 0xEDF5FF)

    def test_gradient_alpha_and_background_shorthand_cascade(self):
        image = self.render('''<style>
body {margin:0; background-color:rgba(0,0,0,.5)}
section {height:40px; width:200px; margin-bottom:10px; border-radius:12px}
.gradient {background:linear-gradient(to right, red 20%, rgb(0 255 0) 50%, blue 80%)}
.keep {background-image:linear-gradient(90deg, #f008 20%, #f008 80%); background-color:#204060}
.reset {background-image:linear-gradient(red,blue); background:#123456}
.fallback {background:#567890; background:linear-gradient(red 20%, not-a-color)}
.combined {background:hsl(180 50% 40%) linear-gradient(transparent, #0080);}
</style><section class="gradient"></section><section class="keep"></section>
<section class="reset"></section><section class="fallback"></section><section class="combined"></section>''')
        self.assertIn(image.rgb(400, 200), (0x7F7F7F, 0x808080))
        self.assertEqual(image.rgb(0, 0), image.rgb(400, 200))
        self.assertEqual(image.rgb(30, 20), 0xFF0000)
        self.assertGreater((image.rgb(99, 20) >> 8) & 255, 245)
        self.assertEqual(image.rgb(175, 20), 0x0000FF)
        for shift, value in ((16, 151), (8, 30), (0, 45)):
            self.assertLessEqual(abs(((image.rgb(80, 70) >> shift) & 255) - value), 1)
        self.assertEqual(image.rgb(80, 120), 0x123456)
        self.assertEqual(image.rgb(80, 170), 0x567890)
        self.assertEqual(image.rgb(80, 220), 0x339999)

    def test_box_shadow_does_not_change_layout_and_border_stays_inside(self):
        image = self.render('''<style>body {margin:0; padding:30px}
.card {width:100px; height:50px; border:3px solid #2f4858; border-radius:13px;
        background:#f0f5f9; box-shadow:0 6px 14px 2px rgb(0 0 0 / 40%)}
.next {width:20px; height:12px; background:#338899}
</style><div class="card"></div><div class="next"></div>''')
        self.assertEqual(image.rgb(80, 30), 0x2F4858)
        self.assertEqual(image.rgb(80, 50), 0xF0F5F9)
        self.assertEqual(image.rgb(35, 86), 0x338899)
        self.assertLess(image.rgb(80, 93), image.rgb(80, 101))
        self.assertEqual(image.rgb(80, 118), 0xFFFFFF)

    def test_object_fit_contain_centers_and_cover_clips_a_rounded_image(self):
        (self.site / "image.png").write_bytes(square_png())
        image = self.render('''<style>body{margin:0}
img {display:block; width:120px; height:60px; background:#e8edf2}
.contain {object-fit:contain} .cover {object-fit:cover; border-radius:14px}
</style><img class="contain" src="image.png"><img class="cover" src="image.png">''')
        self.assertEqual(image.rgb(10, 30), 0xE8EDF2)
        self.assertEqual(image.rgb(40, 30), 0x0898B0)
        self.assertEqual(image.rgb(10, 90), 0x0898B0)
        self.assertEqual(image.rgb(0, 60), 0xFFFFFF)

    def test_grid_tracks_use_fixed_lengths_and_fractional_weights(self):
        image = self.render('''<style>body {margin:0}
.grid {display:grid; width:360px; grid-template-columns:80px minmax(0,2fr) 1fr; gap:12px 5px}
.grid > div {height:25px} .a {background:#a83344} .b {background:#349f84} .c {background:#297db9}
.fluid {display:grid; grid-template-columns:repeat(auto-fit, minmax(140px, 1fr)); gap:8px; width:360px; margin-top:60px}
.fluid > div {height:25px; background:#8b4f98}
</style><div class="grid"><div class="a"></div><div class="b"></div><div class="c"></div></div>
<div class="fluid"><div></div><div></div><div></div></div>''')
        self.assertEqual([image.rgb(x, 12) for x in (79, 83, 86, 264, 267, 359, 360)],
                         [0xA83344, 0xFFFFFF, 0x349F84, 0x349F84, 0xFFFFFF, 0x297DB9, 0xFFFFFF])
        self.assertEqual([image.rgb(x, y) for x, y in ((174, 94), (179, 94), (190, 94), (174, 127), (190, 127))],
                         [0x8B4F98, 0xFFFFFF, 0x8B4F98, 0x8B4F98, 0xFFFFFF])

    def test_flex_wrap_justifies_each_line_and_aligns_items(self):
        image = self.render('''<style>body {margin:0}
main {display:flex; width:260px; flex-wrap:wrap; gap:12px 8px; justify-content:space-between; align-items:center; background:#edf2f7}
main > div {flex:0 0 100px; height:20px; background:#cc5544}
main > div.tall {height:40px; background:#336699}
section {display:flex; width:260px; gap:10px}
section > div {height:20px; flex:1; background:#a05080}
section > div.big {flex:2; background:#48a080}
</style><main><div></div><div class="tall"></div><div></div></main>
<section><div></div><div class="big"></div></section>''')
        self.assertEqual([image.rgb(x, y) for x, y in ((0, 3), (0, 10), (159, 16), (160, 16), (0, 48), (0, 58))],
                         [0xEDF2F7, 0xCC5544, 0xEDF2F7, 0x336699, 0xEDF2F7, 0xCC5544])
        self.assertEqual([image.rgb(x, 78) for x in (82, 84, 95, 259, 260)],
                         [0xA05080, 0xFFFFFF, 0x48A080, 0x48A080, 0xFFFFFF])

    def test_flex_cross_axis_uses_the_definite_container_height(self):
        image = self.render('''<style>body {margin:0}
main {display:flex; height:120px; width:200px; gap:10px; justify-content:center; align-items:center}
main > div {width:40px; height:20px; background:#347a86}
main .end {align-self:flex-end; background:#a64562}
</style><main><div></div><div class="end"></div></main>''')
        self.assertEqual([image.rgb(x, y) for x, y in ((55, 49), (55, 50), (105, 99), (105, 100))],
                         [0xFFFFFF, 0x347A86, 0xFFFFFF, 0xA64562])

    def test_raster_formats_and_grid_row_stretch(self):
        (self.site / "mark.jpg").write_bytes(JPEG)
        (self.site / "mark.webp").write_bytes(WEBP)
        image = self.render('''<style>body { margin:0 }
.grid {display:grid; grid-template-columns:1fr 1fr; gap:10px}
.grid > div {background:#edeffc; padding:10px}
img {display:block; width:40px}
</style><body><div class="grid"><div><img src="mark.jpg" height="70"></div>
<div><img src="mark.webp"></div></div></body>''')
        jpeg = image.rgb(20, 20)
        for shift, expected in ((16, 66), (8, 111), (0, 192)):
            self.assertLessEqual(abs(((jpeg >> shift) & 255) - expected), 2)
        self.assertEqual(image.rgb(345, 30), 0x426FC0)
        self.assertEqual(image.rgb(345, 75), 0xEDEFFC)
        self.assertEqual(image.rgb(20, 92), 0xFFFFFF)
        self.assertEqual(image.rgb(345, 92), 0xFFFFFF)

    def test_css_height_auto_uses_intrinsic_image_ratio(self):
        (self.site / "image.png").write_bytes(square_png(4, 4))
        for display in ("inline", "block"):
            with self.subTest(display=display):
                image = self.render(f'''<style>body {{ margin:0 }}
img {{ display:{display}; width:40px; height:auto }}</style>
<img src="image.png" width="100" height="100">''')
                self.assertEqual(image.rgb(20, 30), 0x0898B0)
                self.assertEqual(image.rgb(20, 60), 0xFFFFFF)

    def test_reflow_recascades_media_and_preserves_link_targets(self):
        (self.site / "responsive.css").write_text('''
body { margin:0; }
main { display:grid; grid-template-columns:1fr 1fr; gap:12px; }
main > a { padding:10px; background:#840020; }
@media (max-width:480px) { main { grid-template-columns:1fr; } main > a { background:#005580; } }
''', encoding="utf-8")
        page = self.site / "responsive.html"
        page.write_text('''<link rel="stylesheet" href="responsive.css"><body>
<main><a id="first" href="#first">First card</a><a id="second" href="#second">Second card</a></main>
</body>''', encoding="utf-8")
        fixture = self.site / "reflow"
        built = subprocess.run([str(ROOT / "volt"), "tests/fixtures/browser_visual.volt", "-o", str(fixture)],
                               cwd=ROOT, timeout=30, capture_output=True, text=True)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        result = subprocess.run([str(fixture), str(page)], timeout=8, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_failed_sheet_and_invalid_or_unconfined_images_keep_content(self):
        (self.site / "escaped.css").symlink_to(self.directory / "outside.css")
        (self.directory / "outside.css").write_text("body { background: red }", encoding="utf-8")
        (self.site / "broken.css").write_text("p { color: /* unterminated", encoding="utf-8")
        (self.site / "broken.png").write_bytes(square_png(100_000, 100_000))
        source = '''<link rel="stylesheet" href="escaped.css">
<link rel="stylesheet" href="broken.css">
<style>body { background:#d7e3ef; margin:0; }</style>
<body><img alt="Missing image" src="broken.png"></body>'''
        image = self.render(source)
        baseline = self.render('<style>body { background:#d7e3ef; margin:0; }</style><body>Missing image</body>')
        self.assertEqual(image.rgb(630, 470), 0xD7E3EF)
        self.assertEqual(image.pixels, baseline.pixels)

    def test_http_assets_follow_only_same_origin_redirects(self):
        requests = []
        with http.server.HTTPServer(("127.0.0.1", 0), http.server.BaseHTTPRequestHandler) as other:
            cross = f"http://127.0.0.1:{other.server_port}/private.css"

            class Handler(http.server.BaseHTTPRequestHandler):
                def do_GET(self):
                    requests.append(self.path)
                    if self.path == "/go":
                        self.send_response(302)
                        self.send_header("Location", cross)
                        self.send_header("Content-Length", "0")
                        self.end_headers()
                        return
                    resources = {
                        "/page": ("text/html", b'<link rel="stylesheet" href="/go"><link rel="stylesheet" href="/style.css"><body>'
                                  + b'<img src="/mark.png" width="24" height="24">' * 20 + b'</body>'),
                        "/policy": ("text/html", b'<link rel="stylesheet" href="/style.css">'
                                    b'<style>body {background:red}</style>'
                                    b'<body style="background: blue"><img src="/blocked.png"></body>'),
                        "/style.css": ("text/css; charset=utf-8", b"body {margin:0; background:#aa8033}"),
                        "/mark.png": ("image/png", square_png()),
                    }
                    mime, data = resources[self.path]
                    self.send_response(200)
                    self.send_header("Content-Type", mime)
                    if self.path == "/page":
                        self.send_header("Content-Security-Policy", "default-src 'self'; script-src 'none'")
                    elif self.path == "/policy":
                        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'self'")
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)

                def log_message(self, *_):
                    pass

            with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server:
                with self.running(server):
                    image = self.render(f"http://127.0.0.1:{server.server_port}/page")
                    policy = self.render(f"http://127.0.0.1:{server.server_port}/policy")
                other.socket.setblocking(False)
                with self.assertRaises(BlockingIOError):
                    other.socket.accept()
        self.assertEqual(requests, ["/page", "/go", "/style.css", "/mark.png", "/policy", "/style.css"])
        self.assertEqual(image.rgb(639, 479), 0xAA8033)
        self.assertEqual(image.rgb(12, 12), 0x0898B0)
        self.assertEqual(image.rgb(19 * 24 + 12, 12), 0x0898B0)
        self.assertEqual(policy.rgb(12, 12), 0xAA8033)

    def test_gzip_expands_html_and_css_with_a_decoded_size_limit(self):
        html = gzip.compress(b'<link rel="stylesheet" href="/style"><p>Compressed response</p>')
        css = gzip.compress(b"body { background:#225566 }")
        oversized = gzip.compress(b" " * (2 * 1024 * 1024 + 1))
        observed = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                observed.append((self.path, self.headers.get("Accept-Encoding")))
                mime, data = {"/": ("text/html", html), "/style": ("text/css", css),
                              "/big": ("text/html", oversized), "/broken": ("text/html", html[:-1])}[self.path]
                self.send_response(200)
                self.send_header("Content-Type", mime)
                self.send_header("Content-Encoding", "gzip")
                if self.path == "/style":
                    self.send_header("Transfer-Encoding", "chunked")
                    self.end_headers()
                    self.wfile.write(f"{len(data):x}\r\n".encode() + data + b"\r\n0\r\n\r\n")
                else:
                    self.send_header("Content-Length", str(len(data)))
                    self.end_headers()
                    self.wfile.write(data)

            def log_message(self, *_):
                pass

        with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server, self.running(server):
            url = f"http://127.0.0.1:{server.server_port}"
            self.assertEqual(self.render(url + "/").rgb(620, 460), 0x225566)
            output = self.site / "invalid.png"
            for path, message in (("/big", "too large"), ("/broken", "invalid HTTP response")):
                with self.subTest(path=path):
                    result = subprocess.run([str(self.binary), "--screenshot", str(output), url + path],
                                            capture_output=True, text=True, timeout=6)
                    self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                    self.assertIn(message, result.stderr)
                    self.assertFalse(output.exists())
        self.assertEqual(observed, [(path, "gzip") for path in ("/", "/style", "/big", "/broken")])

    @staticmethod
    @contextmanager
    def running(server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            yield
        finally:
            server.shutdown()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main()
