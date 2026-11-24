#!/usr/bin/env python3
"""Offline integration tests for the VOLT local search CLI."""
import os
import subprocess
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parents[1]
TITLE = ROOT / "tests/search_title.html"
BODY = ROOT / "tests/search_body.txt"


class ResultPage(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.links = []
        self.tags = []
        self.feed(source)

    def handle_starttag(self, tag, attrs):
        self.tags.append(tag)
        if tag == "a":
            self.links.append(dict(attrs)["href"])


class BrowserSearch(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="volt-search-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.work = Path(cls.temp.name)
        cls.exe = cls.work / "volt-search"
        built = subprocess.run([str(ROOT / "volt"), "tools/volt_search.volt", "-o", str(cls.exe)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        if built.returncode:
            raise AssertionError(built.stdout + built.stderr)

    def run_search(self, query, *paths):
        return subprocess.run([str(self.exe), query, *map(str, paths)], cwd=ROOT,
                              capture_output=True, text=True, timeout=5)

    def test_russian_query_prioritizes_title_over_repeated_body_terms(self):
        result = self.run_search("ёЖиК", BODY, TITLE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([Path(unquote(link)) for link in ResultPage(result.stdout).links], [TITLE, BODY])
        self.assertIn("Ёжик &amp; чай", result.stdout)
        self.assertIn("Тёплый лес.", result.stdout)

    def test_empty_query_and_no_matches(self):
        for query in ("", "!?", "несуществующее", "ёж", "секретныймаркер"):
            with self.subTest(query=query):
                result = self.run_search(query, TITLE, BODY)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Ничего не найдено.", result.stdout)
                self.assertEqual(ResultPage(result.stdout).links, [])

    def test_distinct_terms_outrank_title_and_ties_keep_input_order(self):
        text = self.work / "search_more.txt"
        tied = self.work / "search_tied.txt"
        text.write_text("ЁЖИК поляна необычный", encoding="utf-8")
        tied.write_text("ёжик поляна необычный", encoding="utf-8")
        result = self.run_search("ЁЖИК, ёжик поляна необычный", TITLE, BODY, tied, text)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([Path(unquote(link)) for link in ResultPage(result.stdout).links],
                         [tied, text, TITLE, BODY])
        self.assertIn("Слов запроса: 3; в заголовке: 0", result.stdout)
        self.assertIn("Слов запроса: 2; в заголовке: 1", result.stdout)

    def test_query_title_text_and_filename_cannot_inject_html(self):
        path = self.work / 'тест "#%<&>.HTML'
        path.write_text("<title>ёжик &lt;img&gt;</title><p>ёжик &lt;/p&gt; &amp; &#39; &quot;</p>", encoding="utf-8")
        text = self.work / "search_plain.txt"
        text.write_text('ёжик <b> & " \' >', encoding="utf-8")
        result = self.run_search('ёжик <a id="fake">', path, text)
        self.assertEqual(result.returncode, 0, result.stderr)
        page = ResultPage(result.stdout)
        self.assertEqual([Path(unquote(link)) for link in page.links], [path, text])
        self.assertTrue(page.links[0].endswith("/%D1%82%D0%B5%D1%81%D1%82%20%22%23%25%3C%26%3E.HTML"))
        self.assertIn("ёжик &lt;a id=&quot;fake&quot;&gt;", result.stdout)
        self.assertIn("ёжик &lt;img&gt;", result.stdout)
        self.assertIn("ёжик &lt;/p&gt; &amp; &#39; &quot;", result.stdout)
        self.assertIn("ёжик &lt;b&gt; &amp; &quot; &#39; &gt;", result.stdout)
        self.assertNotIn("img", page.tags)
        self.assertNotIn("b", page.tags)

    def test_only_supplied_files_are_indexed(self):
        listed = self.work / "search_listed.txt"
        unlisted = self.work / "search_unlisted.txt"
        listed.write_text("другой текст", encoding="utf-8")
        unlisted.write_text("отпечаток", encoding="utf-8")
        result = self.run_search("отпечаток", listed)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Ничего не найдено.", result.stdout)
        self.assertNotIn(unlisted.name, result.stdout)

    def test_match_beyond_utf8_preview(self):
        path = self.work / "search_late.txt"
        path.write_text("🦔" * 170 + "\nпоздно", encoding="utf-8")
        result = self.run_search("ПОЗДНО", path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ResultPage(result.stdout).links, [str(path)])
        self.assertIn("<p>" + "🦔" * 160 + "…</p>", result.stdout)

    def test_link_for_whitespace_filename_has_a_visible_label(self):
        path = self.work / "   "
        path.write_text("ёжик", encoding="utf-8")
        result = self.run_search("ёжик", path)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([Path(unquote(link)) for link in ResultPage(result.stdout).links], [path])
        self.assertIn(">Без названия</a>", result.stdout)

    def test_last_document_id_and_corpus_limit(self):
        paths = [self.work / f"search_{i}.txt" for i in range(65)]
        for path in paths:
            path.write_text("предел" if path == paths[63] else "текст", encoding="utf-8")
        result = self.run_search("предел", *paths[:64])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(ResultPage(result.stdout).links, [str(paths[63])])
        overflow = self.run_search("предел", *paths)
        self.assertEqual(overflow.returncode, 1, overflow.stderr)
        self.assertEqual(overflow.stdout, "")
        self.assertIn("limit exceeded", overflow.stderr)

    def test_invalid_explicit_inputs_fail_without_any_results(self):
        fifo = self.work / "search_fifo.txt"
        os.mkfifo(fifo)
        bad_utf8 = self.work / "search_bad.txt"
        bad_utf8.write_bytes(b"text \xff")
        nul = self.work / "search_nul.txt"
        nul.write_bytes(b"text\x00hidden")
        large = self.work / "search_large.txt"
        large.write_bytes(b"x" * (256 * 1024 + 1))
        for path in (self.work, self.work / "missing.txt", fifo, bad_utf8, nul, large, "https://example.invalid/"):
            with self.subTest(path=path):
                result = self.run_search("ёжик", TITLE, path)
                self.assertEqual(result.returncode, 1, result.stderr)
                self.assertEqual(result.stdout, "")
                self.assertIn("volt-search:", result.stderr)

    def test_invalid_query_fails_without_any_results(self):
        for query in ("a" * 1025, b"\xff"):
            result = self.run_search(query, TITLE)
            self.assertEqual(result.returncode, 2, result.stderr)
            self.assertEqual(result.stdout, "")

    def test_reusable_index_and_rollback(self):
        exe = self.work / "check-search-index"
        built = subprocess.run([str(ROOT / "volt"), "tests/fixtures/browser_search_index.volt", "-o", str(exe)],
                               cwd=ROOT, capture_output=True, text=True, timeout=30)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        result = subprocess.run([str(exe)], cwd=ROOT, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("browser search reusable index ok", result.stdout)


if __name__ == "__main__":
    unittest.main()
