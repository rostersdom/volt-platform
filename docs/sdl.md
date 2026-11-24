# SDL2 software-rendering module

VOLT provides an optional, narrow SDL2 binding for a single window and one frame
of software rendering. It targets the reference toolchain's Linux x86-64/System V
ABI and an installed SDL2 shared library. Importing `sdl` links `-lSDL2`; other
programs that do not import the module do not acquire this dependency.

On Debian/Ubuntu, install the development package with `sudo apt install libsdl2-dev`.
`pkg-config --modversion sdl2` should report an installed version. Build and run the
example from the repository root:

```bash
./volt apps/graphics.volt -o apps/bin/graphics
SDL_VIDEODRIVER=dummy apps/bin/graphics
```

For a visible window, omit `SDL_VIDEODRIVER=dummy` and run in a graphical session.
The demo creates a 64×64 window, clears it, draws a colored rectangle, presents one
frame, then destroys resources. The dummy backend verifies API/lifecycle success,
not visible pixels.

## API

All functions are `unsafe`: handles are raw opaque SDL pointers, and the caller
must manage lifecycle. Importing the module adds `link "-lSDL2"`.

```volt
unsafe fn sdl_init() -> i64
unsafe fn sdl_quit()
unsafe fn sdl_window_create(title: string, width: i64, height: i64) -> ptr<char>
unsafe fn sdl_window_destroy(window: ptr<char>)
unsafe fn sdl_renderer_create(window: ptr<char>) -> ptr<char>
unsafe fn sdl_renderer_destroy(renderer: ptr<char>)
unsafe fn sdl_set_draw_color(renderer: ptr<char>, r: i64, g: i64, b: i64, a: i64) -> i64
unsafe fn sdl_clear(renderer: ptr<char>) -> i64
unsafe fn sdl_fill_rect(renderer: ptr<char>, x: i64, y: i64, w: i64, h: i64) -> i64
unsafe fn sdl_present(renderer: ptr<char>)
unsafe fn sdl_poll_quit() -> bool
```

## Convenience window API

For the smallest complete application, import `window` instead of calling the
low-level SDL functions directly. It exposes the same `Window` value everywhere
in the flat import namespace:

```volt
struct Window:
    window: ptr<char>
    renderer: ptr<char>

unsafe fn window_create(title: string, width: i64, height: i64) -> Window
unsafe fn window_poll(window: Window) -> bool
unsafe fn window_clear(window: Window, r: i64, g: i64, b: i64, a: i64) -> i64
unsafe fn window_fill_rect(window: Window, x: i64, y: i64, w: i64, h: i64) -> i64
unsafe fn window_present(window: Window)
unsafe fn window_close(window: Window)
```

`window_create` returns both opaque handles directly; on SDL initialization or
resource-creation failure it returns a zeroed `Window` sentinel. Partial resources
are released before failure returns. Structures are supported as ordinary function
results via sret, but remain unsupported as `Result` payloads, so callers check both
handles for null. All SDL handles are raw pointers; all convenience functions are
therefore `unsafe`. Call
`window_close` exactly once for a successfully created window. `window_poll`
drains pending SDL events and returns `false` for `SDL_QUIT` or
`SDL_WINDOWEVENT_CLOSE`, otherwise `true`.

SDL status-returning calls use zero for success and a negative SDL error status for
failure. Window/renderer creation returns a null pointer on failure. Invalid sizes,
coordinates, or color components return a nonzero status without calling the SDL
operation. `sdl_fill_rect` passes an address to four local `i32` values for SDL's
rectangle; it does not rely on passing a C struct by value.

Call `sdl_init` before creating resources. Destroy renderer before its window, then
call `sdl_quit` exactly once after all resources are released. Do not reuse handles
after destruction or quit. Check each status/handle and clean up every successfully
created object on all failure paths. This wrapper does not panic or fetch SDL error
strings.

`sdl_poll_events` exposes ordered key, text input, mouse button, wheel, redraw
and quit events. The browser uploads its own pixels to an ARGB8888 texture.
The bindings target Linux x86-64 and the SDL2 event ABI. If SDL2 development files are missing, only a program importing `sdl`
fails to link. If the runtime SDL2 shared library is missing, normal dynamic-loader
failure occurs at launch.

The `apps/snake.volt` demo does not depend on SDL_ttf: it draws its score,
state messages, and controls with a small built-in bitmap font and SDL rectangles.

Run the bounded headless smoke test with:

```bash
python3 tests/sdl_integration.py
```

It skips with an explicit reason only if `pkg-config` or the SDL2 development package
is unavailable; if SDL2 is detected, compile/link/runtime failures fail the test.
