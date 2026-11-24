# Small SDL2 convenience API. Importing window links SDL2.
use sdl

struct Window:
    window: ptr<char>
    renderer: ptr<char>

unsafe fn window_create(title: string, width: i64, height: i64) -> Window:
    let result: Window = Window(0 as ptr<char>, 0 as ptr<char>)
    if sdl_init() != 0:
        return result
    result.window = sdl_window_create(title, width, height)
    if result.window == (0 as ptr<char>):
        sdl_quit()
        return result
    result.renderer = sdl_renderer_create(result.window)
    if result.renderer == (0 as ptr<char>):
        sdl_window_destroy(result.window)
        sdl_quit()
        return Window(0 as ptr<char>, 0 as ptr<char>)
    return result

unsafe fn window_poll(window: Window) -> bool:
    if window.window == (0 as ptr<char>) or window.renderer == (0 as ptr<char>):
        return false
    return not sdl_poll_quit()

unsafe fn window_clear(window: Window, r: i64, g: i64, b: i64, a: i64) -> i64:
    let status: i64 = sdl_set_draw_color(window.renderer, r, g, b, a)
    if status != 0:
        return status
    return sdl_clear(window.renderer)

unsafe fn window_fill_rect(window: Window, x: i64, y: i64, w: i64, h: i64) -> i64:
    return sdl_fill_rect(window.renderer, x, y, w, h)

unsafe fn window_present(window: Window):
    sdl_present(window.renderer)

unsafe fn window_close(window: Window):
    sdl_renderer_destroy(window.renderer)
    sdl_window_destroy(window.window)
    sdl_quit()
