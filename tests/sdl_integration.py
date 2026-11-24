#!/usr/bin/env python3
"""Optional SDL2 dummy-driver lifecycle and software-rendering smoke test."""
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VCC = os.path.join(ROOT, "volt")
DEMO = os.path.join(ROOT, "apps", "graphics.volt")
MARKER = "SDL2 dummy software-renderer smoke test passed\n"


class SdlIntegration(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        pkg_config = shutil.which("pkg-config")
        if pkg_config is None:
            raise unittest.SkipTest("SDL2 integration skipped: pkg-config unavailable")
        available = subprocess.run([pkg_config, "--exists", "sdl2"],
                                   capture_output=True, timeout=5)
        if available.returncode != 0:
            raise unittest.SkipTest(
                "SDL2 integration skipped: SDL2 development package not installed"
            )

    def run_source(self, source, tmp):
        src = os.path.join(tmp, "client.volt")
        exe = os.path.join(tmp, "client")
        with open(src, "w", encoding="utf-8") as f:
            f.write(source)
        built = subprocess.run([VCC, src, "-o", exe],
                               capture_output=True, text=True, timeout=20, cwd=ROOT)
        self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
        environment = os.environ.copy()
        environment["SDL_VIDEODRIVER"] = "dummy"
        return subprocess.run([exe], capture_output=True, text=True, timeout=10,
                              cwd=ROOT, env=environment)

    def test_dummy_driver_initializes_draws_and_cleans_up(self):
        with tempfile.TemporaryDirectory(prefix="volt-sdl-") as tmp:
            exe = os.path.join(tmp, "graphics")
            built = subprocess.run([VCC, DEMO, "-o", exe],
                                   capture_output=True, text=True, timeout=20, cwd=ROOT)
            self.assertEqual(built.returncode, 0, built.stdout + built.stderr)
            environment = os.environ.copy()
            environment["SDL_VIDEODRIVER"] = "dummy"
            result = subprocess.run([exe], capture_output=True, text=True, timeout=10,
                                    cwd=ROOT, env=environment)
            self.assertEqual((result.returncode, result.stdout, result.stderr),
                             (0, MARKER, ""))

    def test_invalid_dimensions_colors_and_rectangles_are_rejected(self):
        source = '''use sdl
fn main() -> i64:
    unsafe:
        let bad_window: ptr<char> = sdl_window_create("bad", 0, 1)
        print(bad_window == (0 as ptr<char>))
        let init_status: i64 = sdl_init()
        if init_status != 0:
            sdl_quit()
            return 1
        let window: ptr<char> = sdl_window_create("bounds", 8, 8)
        let renderer: ptr<char> = sdl_renderer_create(window)
        if window == (0 as ptr<char>) or renderer == (0 as ptr<char>):
            sdl_renderer_destroy(renderer)
            sdl_window_destroy(window)
            sdl_quit()
            return 1
        let texture: ptr<char> = sdl_texture_create_argb8888(renderer, 8, 8)
        let oversized: ptr<char> = sdl_texture_create_argb8888(renderer, 4097, 8)
        let pixels: [64]u32
        print(oversized == (0 as ptr<char>))
        print(sdl_texture_update_argb8888(texture, &pixels[0], 8, 8, 8, 64))
        print(sdl_texture_update_argb8888(texture, &pixels[0], 0, 8, 8, 64))
        print(sdl_texture_update_argb8888(texture, &pixels[0], 8, 4097, 8, 32776))
        print(sdl_texture_update_argb8888(texture, &pixels[0], 8, 8, 2147483647, 64))
        print(sdl_texture_update_argb8888(texture, &pixels[0], 8, 8, 8, 63))
        sdl_texture_destroy(texture)
        print(sdl_set_draw_color(renderer, 256, 0, 0, 255))
        print(sdl_fill_rect(renderer, 0, 0, 0, 1))
        print(sdl_fill_rect(renderer, 2147483648, 0, 1, 1))
        sdl_renderer_destroy(renderer)
        sdl_window_destroy(window)
        sdl_quit()
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-sdl-bounds-") as tmp:
            result = self.run_source(source, tmp)
            self.assertEqual((result.returncode, result.stdout, result.stderr),
                             (0, "true\ntrue\n0\n-22\n-22\n-22\n-22\n-22\n-22\n-22\n", ""))

    def test_window_convenience_create_draw_poll_and_close(self):
        source = '''use window
fn main() -> i64:
    unsafe:
        let app: Window = window_create("window test", 16, 16)
        if app.window == (0 as ptr<char>) or app.renderer == (0 as ptr<char>):
            return 1
        let status: i64 = window_clear(app, 0, 0, 0, 255)
        if status == 0:
            status = window_fill_rect(app, 1, 1, 4, 4)
        if status != 0:
            window_close(app)
            return 2
        window_present(app)
        print(window_poll(app))
        window_close(app)
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-window-") as tmp:
            result = self.run_source(source, tmp)
            self.assertEqual((result.returncode, result.stdout, result.stderr),
                             (0, "true\n", ""))

    def test_scroll_helpers_and_event_decoder(self):
        source = '''use paint
use sdl
fn main() -> i64:
    unsafe:
        if paint_scroll_max(1000, 0) != -22: return 1
        if paint_scroll_max(479, 480) != 0: return 2
        if paint_scroll_max(480, 480) != 0: return 3
        if paint_scroll_max(1000, 480) != 520: return 4
        let state: PaintScrollState = PaintScrollState(0, 520)
        if paint_scroll_update(&state, 32) != 32 or state.offset != 32: return 5
        if paint_scroll_update(&state, 0) != 0 or state.offset != 32: return 6
        if paint_scroll_update(&state, 9223372036854775807) != 488 or state.offset != 520: return 7
        if paint_scroll_update(&state, -9223372036854775807) != -520 or state.offset != 0: return 8
        if paint_scroll_key(&state, SCROLL_KEY_PAGEDOWN, 480) != 448 or state.offset != 448: return 9
        if paint_scroll_key(&state, SCROLL_KEY_PAGEUP, 480) != -448 or state.offset != 0: return 10
        if paint_scroll_key(&state, SCROLL_KEY_END, 480) != 520 or state.offset != 520: return 11
        if paint_scroll_key(&state, SCROLL_KEY_HOME, 480) != -520 or state.offset != 0: return 12
        let raw: [7]i64
        let event: ptr<char> = (&raw[0]) as ptr<char>
        *(event as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
        let key: ptr<i32> = (event + 20) as ptr<i32>
        key[0] = SDL_KEY_PAGEDOWN as i32
        let decoded_key: SdlInputEvent = sdl_decode_event(event)
        if decoded_key.kind != SDL_INPUT_EVENT_KEY or decoded_key.key != SDL_KEY_PAGEDOWN: return 13
        *(event as ptr<u32>) = SDL_EVENT_MOUSEWHEEL as u32
        let wheel: ptr<i32> = (event + 20) as ptr<i32>
        wheel[0] = -3
        wheel[1] = 0
        let decoded_wheel: SdlInputEvent = sdl_decode_event(event)
        if decoded_wheel.kind != SDL_INPUT_EVENT_WHEEL or decoded_wheel.wheel_y != -3: return 14
        *(event as ptr<u32>) = SDL_EVENT_MOUSEBUTTONDOWN as u32
        let button: ptr<u8> = (event as ptr<u8>) + 16
        button[0] = SDL_BUTTON_LEFT as u8
        let coords: ptr<i32> = (event + 20) as ptr<i32>
        coords[0] = 123
        coords[1] = 234
        let decoded_button: SdlInputEvent = sdl_decode_event(event)
        if decoded_button.kind != SDL_INPUT_EVENT_BUTTON or decoded_button.button != SDL_BUTTON_LEFT or decoded_button.mouse_x != 123 or decoded_button.mouse_y != 234: return 17
        button[0] = 3 as u8
        if sdl_decode_event(event).button != 3: return 18
        *(event as ptr<u32>) = SDL_EVENT_QUIT as u32
        if sdl_decode_event(event).kind != SDL_INPUT_EVENT_QUIT: return 15
        *(event as ptr<u32>) = SDL_EVENT_WINDOW as u32
        let code: ptr<u8> = (event as ptr<u8>) + 12
        code[0] = SDL_WINDOWEVENT_CLOSE as u8
        if sdl_decode_event(event).kind != SDL_INPUT_EVENT_QUIT: return 16
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-sdl-scroll-state-") as tmp:
            result = self.run_source(source, tmp)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_scroll_event_queue_drains_combined_inputs(self):
        source = '''use sdl
unsafe extern fn SDL_PushEvent(event: ptr<char>) -> i32
fn main() -> i64:
    unsafe:
        if sdl_init() != 0: return 1
        let event: [7]i64
        let raw: ptr<char> = (&event[0]) as ptr<char>
        let drained: i64 = 0
        while SDL_PollEvent(raw) != 0:
            drained += 1
        *(raw as ptr<u32>) = SDL_EVENT_WINDOW as u32
        let window_code: ptr<u8> = (raw as ptr<u8>) + 12
        window_code[0] = 99 as u8
        if SDL_PushEvent(raw) != 1: return 2
        *(raw as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
        let key: ptr<i32> = (raw + 20) as ptr<i32>
        key[0] = SDL_KEY_PAGEDOWN as i32
        if SDL_PushEvent(raw) != 1: return 3
        *(raw as ptr<u32>) = SDL_EVENT_MOUSEWHEEL as u32
        let wheel: ptr<i32> = (raw + 20) as ptr<i32>
        wheel[0] = -2
        wheel[1] = 0
        if SDL_PushEvent(raw) != 1: return 4
        *(raw as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
        key[0] = SDL_KEY_HOME as i32
        if SDL_PushEvent(raw) != 1: return 5
        let summary: SdlInputSummary = sdl_poll_events()
        # sdl2-compat may quantize injected wheel deltas. Test the raw ABI separately.
        if summary.quit or summary.key != SDL_KEY_HOME or summary.wheel_y != summary.events[2].wheel_y or summary.other_events != 1: return 6
        if summary.event_count != 4 or summary.events[0].kind != SDL_INPUT_EVENT_NONE or summary.events[1].kind != SDL_INPUT_EVENT_KEY or summary.events[2].kind != SDL_INPUT_EVENT_WHEEL or summary.events[3].key != SDL_KEY_HOME: return 8
        *(raw as ptr<u32>) = SDL_EVENT_QUIT as u32
        if SDL_PushEvent(raw) != 1: return 9
        *(raw as ptr<u32>) = SDL_EVENT_MOUSEBUTTONDOWN as u32
        let button: ptr<u8> = (raw as ptr<u8>) + 16
        button[0] = SDL_BUTTON_LEFT as u8
        let coords: ptr<i32> = (raw + 20) as ptr<i32>
        coords[0] = 5
        coords[1] = 6
        if SDL_PushEvent(raw) != 1: return 10
        let quit_batch: SdlInputSummary = sdl_poll_events()
        if not quit_batch.quit or quit_batch.event_count != 2 or quit_batch.events[0].kind != SDL_INPUT_EVENT_QUIT or quit_batch.events[1].kind != SDL_INPUT_EVENT_BUTTON: return 11
        if quit_batch.events[1].button != SDL_BUTTON_LEFT or quit_batch.events[1].mouse_x != 5 or quit_batch.events[1].mouse_y != 6: return 12
        if quit_batch.events[1].button != SDL_BUTTON_LEFT or quit_batch.events[1].mouse_x != 5 or quit_batch.events[1].mouse_y != 6: return 12
        let empty: SdlInputSummary = sdl_poll_events()
        if empty.quit or empty.key != 0 or empty.wheel_y != 0 or empty.other_events != 0: return 7
        sdl_quit()
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-sdl-scroll-queue-") as tmp:
            result = self.run_source(source, tmp)
            self.assertEqual((result.returncode, result.stdout, result.stderr), (0, "", ""))

    def test_window_create_failure_returns_zeroed_sentinel(self):
        source = '''use window
fn main() -> i64:
    unsafe:
        let app: Window = window_create("invalid", 0, 1)
        print(app.window == (0 as ptr<char>))
        print(app.renderer == (0 as ptr<char>))
    return 0
'''
        with tempfile.TemporaryDirectory(prefix="volt-window-failure-") as tmp:
            result = self.run_source(source, tmp)
            self.assertEqual((result.returncode, result.stdout, result.stderr),
                             (0, "true\ntrue\n", ""))


if __name__ == "__main__":
    unittest.main()
