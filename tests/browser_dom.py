#!/usr/bin/env python3
"""Build-once DOM API: createElement, appendChild, attributes, classList, clicks."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests/fixtures"
HAVE_JS_DEPS = shutil.which("pkg-config") is not None and subprocess.run(
    ["pkg-config", "--exists", "duktape", "libseccomp"], check=False
).returncode == 0


@unittest.skipUnless(HAVE_JS_DEPS, "optional Duktape dependency not installed")
class BrowserDom(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-dom-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)
        cls.browser = cls.dir / "browser"
        built = subprocess.run([str(ROOT / "volt"), str(ROOT / "browser" / "browser.volt"),
                                "-o", str(cls.browser)],
                               cwd=ROOT, capture_output=True, text=True, timeout=90)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)
        built = subprocess.run(["make", f"BINDIR={cls.dir}", "-o", str(cls.browser),
                                str(cls.dir / "volt-js")],
                               cwd=ROOT, capture_output=True, text=True, timeout=90)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)
        cls.fixture = cls.dir / "dom-click"
        built = subprocess.run([str(ROOT / "volt"), str(FIXTURES / "browser_fetch_click.volt"),
                                "-o", str(cls.fixture)],
                               cwd=ROOT, capture_output=True, text=True, timeout=60)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)

    def screenshot(self, source, name, scripts=False):
        path = self.dir / (name + ".html")
        path.write_text(source, encoding="utf-8")
        image = self.dir / (name + ".png")
        args = [str(self.browser), "--screenshot", str(image)]
        if scripts:
            args.append("--js")
        result = subprocess.run([*args, str(path)], env={"PATH": ""},
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return image.read_bytes()

    def test_create_append_attributes_class_and_text_match_static_html(self):
        style = ".box { background: #ff0000; color: #ffffff; padding: 4px; }"
        script = '''<script>
var d = document.createElement('div');
d.id = 'created';
d.className = 'box';
d.setAttribute('title', 'hello');
d.textContent = 'DOM works';
document.getElementById('out').appendChild(d);
</script>'''
        actual = self.screenshot(
            f'<style>{style}</style><div id="out"></div>{script}', "create", scripts=True)
        expected = self.screenshot(
            f'<style>{style}</style><div id="out">'
            f'<div id="created" class="box" title="hello">DOM works</div></div>',
            "create-reference")
        self.assertEqual(actual, expected)

    def test_nested_detached_tree_and_getters(self):
        style = ".box { background: #00ff00; padding: 2px; }"
        script = '''<script>
var d = document.createElement('div');
d.className = 'box';
d.textContent = 'A';
var s = document.createElement('span');
s.textContent = 'B';
d.appendChild(s);
document.getElementById('out').appendChild(d);
var ok = d.tagName === 'div' && d.getAttribute('class') === 'box' &&
  d.classList.contains('box') && !d.hasAttribute('title') && d.textContent === 'AB';
document.getElementById('status').textContent = ok ? 'OK' : 'BAD';
</script>'''
        actual = self.screenshot(
            f'<style>{style}</style><div id="status">Start</div><div id="out"></div>{script}',
            "nested", scripts=True)
        expected = self.screenshot(
            f'<style>{style}</style><div id="status">OK</div>'
            f'<div id="out"><div class="box">A<span>B</span></div></div>',
            "nested-reference")
        self.assertEqual(actual, expected)

    def test_click_on_created_element_runs_listener(self):
        page = self.dir / "click.html"
        page.write_text('''<div id="status">Start</div><div id="out"></div><script>
var b = document.createElement('button');
b.textContent = 'Go';
b.addEventListener('click', function () {
  document.getElementById('status').textContent = 'Clicked';
});
document.getElementById('out').appendChild(b);
</script>''', encoding="utf-8")
        result = subprocess.run([str(self.fixture), str(page), "Go"],
                                env={"SDL_VIDEODRIVER": "dummy"},
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "ClickedGo\n")

    def test_click_handler_can_append_a_new_element(self):
        page = self.dir / "click-append.html"
        page.write_text('''<div id="status">Start</div><div id="out"></div><script>
var b = document.createElement('button');
b.textContent = 'Add';
b.addEventListener('click', function () {
  var d = document.createElement('div');
  d.textContent = 'New';
  document.getElementById('out').appendChild(d);
  document.getElementById('status').textContent = 'Done';
});
document.getElementById('out').appendChild(b);
</script>''', encoding="utf-8")
        result = subprocess.run([str(self.fixture), str(page), "Add", "visual"],
                                env={"SDL_VIDEODRIVER": "dummy"},
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(result.stdout, "DoneAddNew\n")

    def test_connected_element_is_immutable(self):
        page = self.dir / "immutable.html"
        page.write_text('''<div id="status">Start</div><div id="out"></div><script>
var b = document.createElement('button');
b.textContent = 'Go';
document.getElementById('out').appendChild(b);
var ok = false;
try { b.textContent = 'Changed'; } catch (e) { ok = true; }
document.getElementById('status').textContent = ok ? 'OK' : 'BAD';
</script>''', encoding="utf-8")
        actual = self.screenshot(page.read_text(encoding="utf-8"), "immutable", scripts=True)
        expected = self.screenshot(
            '<div id="status">OK</div><div id="out"><button>Go</button></div>',
            "immutable-reference")
        self.assertEqual(actual, expected)


class BrowserDomCore(unittest.TestCase):
    """Parent-side DOM insertion, runnable without the optional JS worker."""

    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-dom-core-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.dir = Path(cls.temp.name)
        cls.fixture = cls.dir / "dom-apply"
        built = subprocess.run([str(ROOT / "volt"), str(FIXTURES / "browser_dom_apply.volt"),
                                "-o", str(cls.fixture)],
                               cwd=ROOT, capture_output=True, text=True, timeout=60)
        if built.returncode:
            raise RuntimeError(built.stdout + built.stderr)

    def test_append_fragment_without_js_worker(self):
        result = subprocess.run([str(self.fixture)], env={"PATH": ""},
                                capture_output=True, text=True, timeout=20)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("text DOM\n", result.stdout)
        self.assertRegex(result.stdout, r"nodes [0-9]+\n")


if __name__ == "__main__":
    unittest.main()
