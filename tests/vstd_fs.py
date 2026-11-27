#!/usr/bin/env python3
"""Exercise fs.read_all, fs.read_into and owned_buffer_try_new."""
import errno
import os
from pathlib import Path
import platform
import shutil
import struct
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "tests" / "fixtures"
VOLT = Path(os.environ.get("VOLT_COMPILER", ROOT / "volt")).resolve()

PAYLOAD = bytes([0x00, 0x01, 0x02, 0xFF, 0x0A, 0x00, 0x41])
EXACT = b"abcdef"


@unittest.skipUnless(platform.system() == "Linux" and platform.machine() == "x86_64",
                     "vstd fs uses the Linux x86-64 syscall ABI")
class VstdFs(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        tmp = tempfile.TemporaryDirectory(prefix="volt-vstd-fs-")
        cls.addClassCleanup(tmp.cleanup)
        cls.build = Path(tmp.name)
        cls.env = {"PATH": "", "TMPDIR": tmp.name}

    def run_fixture(self, name, cwd, expected, *, compiler=VOLT):
        exe = self.build / name
        built = subprocess.run([compiler, FIXTURES / f"{name}.volt", "-o", exe],
                               cwd=self.build, env=self.env, capture_output=True, text=True, timeout=30)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        elf = exe.read_bytes()
        self.assertEqual(elf[:7], b"\x7fELF\x02\x01\x01")
        offset = struct.unpack_from("<Q", elf, 32)[0]
        size, count = struct.unpack_from("<HH", elf, 54)
        segments = {struct.unpack_from("<I", elf, offset + i * size)[0] for i in range(count)}
        self.assertIn(1, segments)  # PT_LOAD
        self.assertFalse(segments & {2, 3}, "fixture has PT_DYNAMIC or PT_INTERP")

        result = subprocess.run([exe], cwd=cwd, env=self.env, umask=0o027,
                                capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((result.stdout, result.stderr), (expected + "\n", ""))

    def copy_compiler_with_vstd(self, cwd):
        compiler = cwd / "volt"
        shutil.copy2(VOLT, compiler)
        shutil.copytree(ROOT / "vstd", cwd / "vstd")
        return compiler

    def run_read_all_at_capacity(self, cwd, compiler, expected):
        buffers = cwd / "vstd/bytes.volt"
        text = buffers.read_text(encoding="utf-8")
        allocation = "    let mapped: ptr<char> = mmap(new_cap)\n"
        self.assertEqual(text.count(allocation), 1)
        buffers.write_text(text.replace(allocation, '    print("alloc", new_cap)\n' + allocation),
                           encoding="utf-8")
        self.run_fixture("vstd_fs_read_all_limit", cwd, f"alloc 4096\n{expected}", compiler=compiler)

    def test_read_all_through_question_mark_without_manual_release(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-all-") as tmp:
            cwd = Path(tmp)
            (cwd / "payload.bin").write_bytes(PAYLOAD)
            (cwd / "empty.bin").write_bytes(b"")
            (cwd / "exact.bin").write_bytes(EXACT)
            (cwd / "adir").mkdir()
            os.mkfifo(cwd / "pipe")  # no writer: open must not block

            expected = "\n".join([
                f"ok {len(PAYLOAD)} {sum(PAYLOAD)}",
                f"err {errno.ENOENT}",
                f"err {errno.EFBIG}",
                "ok 0 0",
                f"ok {len(EXACT)} {sum(EXACT)}",
                f"err {errno.EINVAL}",
                f"err {errno.EINVAL}",
                f"err {errno.EISDIR}",
                # run_fixture's timeout turns a blocked open into a failure.
                f"err {errno.ESPIPE}",
                "done",
            ])
            self.run_fixture("vstd_fs_read_all", cwd, expected)

            # The error paths must not destroy, truncate or create anything.
            self.assertEqual((cwd / "payload.bin").read_bytes(), PAYLOAD)
            self.assertEqual((cwd / "exact.bin").read_bytes(), EXACT)
            self.assertEqual({p.name for p in cwd.iterdir()},
                             {"payload.bin", "empty.bin", "exact.bin", "adir", "pipe"})

    def test_read_all_at_capacity_probes_eof_without_growing_buffer(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-all-exact-") as tmp:
            cwd = Path(tmp)
            compiler = self.copy_compiler_with_vstd(cwd)
            (cwd / "payload.bin").write_bytes(b"Q" * 4096)
            self.run_read_all_at_capacity(cwd, compiler, "ok 4096 81")

    def test_read_all_rejects_extra_byte_after_statx_reports_exact_limit(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-all-growth-") as tmp:
            cwd = Path(tmp)
            compiler = self.copy_compiler_with_vstd(cwd)
            (cwd / "payload.bin").write_bytes(b"Q" * 4096 + b"!")

            # Leave the real type and mask intact, but report a stale stx_size
            # (offset 40). The extra byte is only discovered by read(2).
            legacy = cwd / "vstd/fs_legacy.volt"
            text = legacy.read_text(encoding="utf-8")
            statx = "    mov rax, 332\n    syscall\n"
            self.assertEqual(text.count(statx), 1)
            legacy.write_text(text.replace(statx, statx + "    mov qword ptr [r8 + 40], 4096\n"),
                              encoding="utf-8")
            self.run_read_all_at_capacity(cwd, compiler, f"err {errno.EFBIG}")

    def test_read_all_fifo_never_blocks_even_without_a_writer(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-all-fifo-") as tmp:
            cwd = Path(tmp)
            os.mkfifo(cwd / "pipe")
            started = time.monotonic()
            self.run_fixture("vstd_fs_fifo", cwd, f"err {errno.ESPIPE}")
            self.assertLess(time.monotonic() - started, 4, "read_all blocked on a FIFO")

    def test_read_all_closes_without_reading_when_statx_omits_required_fields(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="statx-mask-") as tmp:
            cwd = Path(tmp)
            compiler = self.copy_compiler_with_vstd(cwd)
            (cwd / "payload.bin").write_bytes(PAYLOAD)

            fs = cwd / "vstd/fs.volt"
            text = fs.read_text(encoding="utf-8")
            read = "            let n: i64 = read(fd, dst, room)"
            self.assertEqual(text.count(read), 1)
            fs.write_text(text.replace(read, '            panic("unexpected read\\n")\n' + read),
                          encoding="utf-8")
            legacy = cwd / "vstd/fs_legacy.volt"
            text = legacy.read_text(encoding="utf-8")
            statx = "    mov rax, 332\n    syscall\n"
            self.assertEqual(text.count(statx), 1)
            for mask in (0x001, 0x200):
                with self.subTest(mask=mask):
                    # Keep the real type and size in the response, but omit
                    # confirmation of one field. Neither raw value is enough.
                    legacy.write_text(text.replace(statx, statx + f"    mov dword ptr [r8], {mask}\n"),
                                      encoding="utf-8")
                    self.run_fixture("vstd_fs_statx_mask", cwd,
                                     f"err {errno.EOPNOTSUPP}\nfd {-errno.EBADF}", compiler=compiler)

    def test_wait_readable_borrows_a_live_owned_fd(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="fd-ready-") as tmp:
            cwd = Path(tmp)
            os.mkfifo(cwd / "pipe")
            # Keep a writer open so the reader sees a timeout rather than HUP
            # after consuming the one byte. Linux permits opening a FIFO RDWR.
            writer = os.open(cwd / "pipe", os.O_RDWR | os.O_NONBLOCK)
            try:
                os.write(writer, b"Q")
                self.run_fixture("vstd_fs_wait_readable", cwd, f"1 1 81 0\nerr {errno.EINVAL}")
            finally:
                os.close(writer)

    def test_read_into_reads_binary_through_owned_fd(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="read-into-") as tmp:
            cwd = Path(tmp)
            (cwd / "payload.bin").write_bytes(PAYLOAD)
            (cwd / "adir").mkdir()
            expected = "\n".join([
                f"first {len(PAYLOAD)} {sum(PAYLOAD)}",
                "eof 0",
                f"empty {errno.EINVAL}",
                f"dir {errno.EISDIR}",
                "done",
            ])
            self.run_fixture("vstd_fs_read_into", cwd, expected)

    def test_try_new_reports_enomem_without_panicking(self):
        with tempfile.TemporaryDirectory(dir=self.build, prefix="try-new-") as tmp:
            expected = "\n".join([
                "small ok 3",
                "new 2",
                "rlimit 0",
                f"huge err {errno.ENOMEM}",
                "done",
            ])
            self.run_fixture("vstd_fs_try_new", Path(tmp), expected)


if __name__ == "__main__":
    unittest.main()
