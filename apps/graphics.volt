# One-frame SDL2 software-rendering demo. Build with SDL2 development files installed.
use sdl

fn main() -> i64:
    unsafe:
        let init_status: i64 = sdl_init()
        if init_status != 0:
            print("SDL_Init failed", init_status)
            sdl_quit()
            return 1

        let window: ptr<char> = sdl_window_create("VOLT SDL2", 64, 64)
        if window == (0 as ptr<char>):
            print("SDL_CreateWindow failed")
            sdl_quit()
            return 1

        let renderer: ptr<char> = sdl_renderer_create(window)
        if renderer == (0 as ptr<char>):
            print("SDL_CreateRenderer failed")
            sdl_window_destroy(window)
            sdl_quit()
            return 1

        let status: i64 = sdl_set_draw_color(renderer, 20, 30, 40, 255)
        if status == 0:
            status = sdl_clear(renderer)
        if status == 0:
            status = sdl_set_draw_color(renderer, 240, 80, 30, 255)
        if status == 0:
            status = sdl_fill_rect(renderer, 8, 8, 48, 48)
        if status == 0:
            sdl_present(renderer)
        sdl_renderer_destroy(renderer)
        sdl_window_destroy(window)
        sdl_quit()
        if status != 0:
            print("SDL drawing failed", status)
            return 1
        print("SDL2 dummy software-renderer smoke test passed")
    return 0
