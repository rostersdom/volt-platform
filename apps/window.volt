# Minimal SDL2 loop using the convenience window module.
use window

fn main() -> i64:
    unsafe:
        let app: Window = window_create("VOLT window", 320, 240)
        if app.window == (0 as ptr<char>) or app.renderer == (0 as ptr<char>):
            print("Window creation failed")
            return 1
        let frames: i64 = 0
        while window_poll(app) and frames < 1:
            let status: i64 = window_clear(app, 25, 35, 50, 255)
            if status == 0:
                status = window_fill_rect(app, 40, 40, 120, 80)
            if status != 0:
                window_close(app)
                return 1
            window_present(app)
            frames = frames + 1
        window_close(app)
    return 0
