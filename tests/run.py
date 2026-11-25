#!/usr/bin/env python3
"""Прогон тестов VOLT: компилирует tests/*.volt, сверяет вывод с эталоном.

Использование:
  python3 tests/run.py            # все тесты
  python3 tests/run.py strings    # только tests/strings.volt
  python3 tests/run.py --update   # переписать эталонные выводы
"""
import os, shutil, sys, subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
VCC = os.path.join(HERE, "..", "volt")
GOLD = os.path.join(HERE, "expected")
TEST_TIMEOUT = 10

# Golden tests that transitively link -lSDL2 (via browser_engine,
# browser_controller or sdl). On a headless runner without the SDL2
# development package they cannot build, so they are skipped up front
# instead of failing the core group (see tests/run_all.py groups).
SDL_TESTS = {"browser_controller_import", "browser_hit_test", "browser_links",
             "browser_navigation_state", "browser_scroll"}

def sdl2_available():
    pkg_config = shutil.which("pkg-config")
    if not pkg_config:
        return False
    return subprocess.run([pkg_config, "--exists", "sdl2"],
                          capture_output=True).returncode == 0

def main():
    args = [a for a in sys.argv[1:]]
    update = "--update" in args
    args = [a for a in args if not a.startswith("--")]
    os.makedirs(GOLD, exist_ok=True)
    tests = sorted(f for f in os.listdir(HERE) if f.endswith(".volt"))
    if args:
        tests = [t for t in tests if any(a in t for a in args)]
    if not tests:
        print("нет тестов"); return 1
    failed = []
    skipped = []
    have_sdl2 = sdl2_available()
    for t in tests:
        name = t[:-5]
        if name in SDL_TESTS and not have_sdl2:
            print(f"  skip {name} (нет SDL2)")
            skipped.append(name)
            continue
        src = os.path.join(HERE, t)
        try:
            r = subprocess.run([VCC, src, "--run"],
                               capture_output=True, text=True, timeout=TEST_TIMEOUT,
                               cwd=os.path.dirname(HERE))
        except subprocess.TimeoutExpired:
            print(f"  FAIL {name}: тайм-аут ({TEST_TIMEOUT} с), эталон не изменён")
            failed.append(name)
            continue
        if update and r.returncode != 0:
            print(f"  FAIL {name}: завершился с кодом {r.returncode}, эталон не изменён")
            for ln in (r.stdout + r.stderr).splitlines()[:12]: print("    " + ln)
            failed.append(name)
            continue
        stderr = r.stderr.replace(src + ":", t + ":")
        got = r.stdout + (("!!stderr: " + stderr) if r.returncode != 0 else "")
        gold = os.path.join(GOLD, name + ".txt")
        if update:
            with open(gold, "w", encoding="utf-8") as f:
                f.write(got)
            print(f"  обновлён {name}")
            continue
        if not os.path.exists(gold):
            print(f"  ?? {name}: нет эталона (python3 tests/run.py --update)")
            failed.append(name); continue
        want = open(gold, encoding="utf-8").read()
        if got == want:
            print(f"  ok {name}")
        else:
            print(f"  FAIL {name}")
            print("    --- ожидалось ---")
            for ln in want.splitlines()[:12]: print("    " + ln)
            print("    --- получено ---")
            for ln in got.splitlines()[:12]: print("    " + ln)
            failed.append(name)
    print(f"\n{len(tests) - len(failed) - len(skipped)}/{len(tests)} ok"
          + (f", пропущено без SDL2: {len(skipped)}" if skipped else ""))
    return 1 if failed else 0

if __name__ == "__main__":
    sys.exit(main())
