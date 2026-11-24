# Оконная Snake на VOLT и SDL2.
# Сборка: ./volt apps/snake.volt -o apps/bin/snake
# WASD/стрелки — движение, Space — старт/пауза, R — заново, Esc — выход.
use sdl

struct Game:
    x: [512]i64
    y: [512]i64
    length: i64
    dx: i64
    dy: i64
    food_x: i64
    food_y: i64
    score: i64
    best: i64
    rng: u64
    started: bool
    paused: bool
    over: bool
    quit: bool
    last_step: i64

unsafe fn random_next(g: ptr<Game>) -> u64:
    g.rng = g.rng ^ (g.rng << 13)
    g.rng = g.rng ^ (g.rng >> 7)
    g.rng = g.rng ^ (g.rng << 17)
    return g.rng

unsafe fn occupied(g: ptr<Game>, x: i64, y: i64) -> bool:
    let i: i64 = 0
    while i < g.length:
        if g.x[i] == x and g.y[i] == y:
            return true
        i = i + 1
    return false

unsafe fn place_food(g: ptr<Game>):
    let tries: i64 = 0
    while tries < 128:
        let x: i64 = random_next(g) % 24
        let y: i64 = random_next(g) % 18
        if not occupied(g, x, y):
            g.food_x = x
            g.food_y = y
            return
        tries = tries + 1
    let cell: i64 = 0
    while cell < 432:
        if not occupied(g, cell % 24, cell / 24):
            g.food_x = cell % 24
            g.food_y = cell / 24
            return
        cell = cell + 1
    g.over = true

unsafe fn reset(g: ptr<Game>, now: i64):
    g.length = 4
    g.x[0] = 10
    g.y[0] = 9
    g.x[1] = 11
    g.y[1] = 9
    g.x[2] = 12
    g.y[2] = 9
    g.x[3] = 13
    g.y[3] = 9
    g.dx = 1
    g.dy = 0
    g.score = 0
    g.started = false
    g.paused = false
    g.over = false
    g.last_step = now
    place_food(g)

unsafe fn turn(g: ptr<Game>, dx: i64, dy: i64):
    if dx != 0 and g.dx == 0:
        g.dx = dx
        g.dy = dy
    elif dy != 0 and g.dy == 0:
        g.dx = dx
        g.dy = dy

unsafe fn input(g: ptr<Game>, key: i64, now: i64):
    if key == 27:
        g.quit = true
    elif key == 114 or key == 82:
        reset(g, now)
    elif key == 32:
        if g.over:
            reset(g, now)
            g.started = true
        else:
            g.started = true
            g.paused = not g.paused
    elif key == 119 or key == 1073741906:
        turn(g, 0, -1)
    elif key == 115 or key == 1073741905:
        turn(g, 0, 1)
    elif key == 97 or key == 1073741904:
        turn(g, -1, 0)
    elif key == 100 or key == 1073741903:
        turn(g, 1, 0)

unsafe fn step(g: ptr<Game>) -> bool:
    let head: i64 = g.length - 1
    let nx: i64 = g.x[head] + g.dx
    let ny: i64 = g.y[head] + g.dy
    if nx < 0 or nx >= 24 or ny < 0 or ny >= 18:
        return false
    let growing: bool = nx == g.food_x and ny == g.food_y
    let limit: i64 = g.length
    if not growing:
        limit = g.length - 1
    let i: i64 = 0
    while i < limit:
        if g.x[i] == nx and g.y[i] == ny:
            return false
        i = i + 1
    if growing:
        g.x[g.length] = nx
        g.y[g.length] = ny
        g.length = g.length + 1
        g.score = g.score + 10
        if g.score > g.best:
            g.best = g.score
        if g.length == 432:
            g.over = true
        else:
            place_food(g)
    else:
        let k: i64 = 0
        while k < g.length - 1:
            g.x[k] = g.x[k + 1]
            g.y[k] = g.y[k + 1]
            k = k + 1
        g.x[g.length - 1] = nx
        g.y[g.length - 1] = ny
    return true

unsafe fn color_draw(window: ptr<char>, rgb: i64, x: i64, y: i64, w: i64, h: i64) -> i64:
    let status: i64 = sdl_set_draw_color(window, (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255, 255)
    if status == 0:
        status = sdl_fill_rect(window, x, y, w, h)
    return status

# Five by seven bitmap font packed as seven five-bit rows.
unsafe fn glyph_code(c: char) -> i64:
    if c == 'A': return 0x0117D7F7
    if c == 'B': return 0x03D7D7DF
    if c == 'C': return 0x01C606C7
    if c == 'D': return 0x03D7D7DE
    if c == 'E': return 0x03F0C0FF
    if c == 'G': return 0x01D6D6CF
    if c == 'I': return 0x03E10847
    if c == 'K': return 0x03DCCCD7
    if c == 'M': return 0x03D7FFD7
    if c == 'O': return 0x01D7D7D7
    if c == 'P': return 0x03D1D1DF
    if c == 'Q': return 0x01D7F7D7
    if c == 'R': return 0x03D9D5DF
    if c == 'S': return 0x01F07D87
    if c == 'T': return 0x0108421F
    if c == 'U': return 0x02D7D7D7
    if c == 'V': return 0x0115D6D6
    if c == 'Y': return 0x01097E42
    if c == ' ': return 0
    if c == '0': return 0x01D7D7D7
    if c == '1': return 0x03E1084F
    if c == '2': return 0x03E11C87
    if c == '3': return 0x01F01C87
    if c == '4': return 0x010F7C44
    if c == '5': return 0x01F07C0F
    if c == '6': return 0x01F67CD7
    if c == '7': return 0x0108421F
    if c == '8': return 0x01F67ED7
    if c == '9': return 0x01F07ED7
    return 0

unsafe fn draw_glyph(window: ptr<char>, c: char, x: i64, y: i64, scale: i64, rgb: i64):
    let bits: i64 = glyph_code(c)
    let row: i64 = 0
    while row < 7:
        let col: i64 = 0
        while col < 5:
            if ((bits >> (row * 5 + col)) & 1) != 0:
                color_draw(window, rgb, x + col * scale, y + row * scale, scale, scale)
            col = col + 1
        row = row + 1

unsafe fn draw_text(window: ptr<char>, text: string, x: i64, y: i64, scale: i64, rgb: i64):
    let i: i64 = 0
    while i < str_len(text):
        draw_glyph(window, text[i], x + i * 6 * scale, y, scale, rgb)
        i = i + 1

unsafe fn draw_number(window: ptr<char>, value: i64, x: i64, y: i64, scale: i64, rgb: i64):
    let digits: [20]char
    let count: i64 = 0
    let number: i64 = value
    if number == 0:
        draw_glyph(window, '0', x, y, scale, rgb)
        return
    while number > 0:
        digits[count] = ((number % 10) + 48) as char
        number = number / 10
        count = count + 1
    while count > 0:
        count = count - 1
        draw_glyph(window, digits[count], x, y, scale, rgb)
        x = x + 6 * scale

unsafe fn render(window: ptr<char>, g: ptr<Game>):
    sdl_set_draw_color(window, 15, 22, 31, 255)
    sdl_clear(window)
    draw_text(window, "SCORE", 24, 10, 2, 0xDCE8E6)
    draw_number(window, g.score, 96, 10, 2, 0x7DDC9E)
    draw_text(window, "BEST", 220, 10, 2, 0xDCE8E6)
    draw_number(window, g.best, 278, 10, 2, 0xF8C257)
    color_draw(window, 0x1C2832, 18, 54, 444, 348)
    color_draw(window, 0x405056, 20, 56, 440, 2)
    color_draw(window, 0x405056, 20, 398, 440, 2)
    color_draw(window, 0x405056, 20, 56, 2, 344)
    color_draw(window, 0x405056, 458, 56, 2, 344)
    let gy: i64 = 0
    while gy < 18:
        let gx: i64 = 0
        while gx < 24:
            let px: i64 = 24 + gx * 18
            let py: i64 = 60 + gy * 18
            if gx == g.food_x and gy == g.food_y:
                color_draw(window, 0xF06A56, px + 3, py + 3, 12, 12)
            let i: i64 = 0
            while i < g.length:
                if g.x[i] == gx and g.y[i] == gy:
                    if i == g.length - 1:
                        color_draw(window, 0x7DDC9E, px + 1, py + 1, 16, 16)
                    else:
                        color_draw(window, 0x46A67E, px + 2, py + 2, 14, 14)
                i = i + 1
            gx = gx + 1
        gy = gy + 1
    if not g.started or g.paused or g.over:
        color_draw(window, 0x0F161F, 165, 204, 150, 32)
        if g.over:
            draw_text(window, "GAME OVER", 190, 214, 2, 0xF06A56)
        elif g.paused:
            draw_text(window, "PAUSED", 210, 214, 2, 0xF8C257)
        else:
            draw_text(window, "SPACE START", 186, 214, 2, 0x7DDC9E)
    draw_text(window, "SPACE PAUSE  R RESET  ESC QUIT", 24, 414, 1, 0xDCE8E6)
    sdl_present(window)

fn main() -> i64:
    unsafe:
        if sdl_init() != 0:
            return 1
        let window: ptr<char> = sdl_window_create("VOLT Snake", 480, 440)
        if window == (0 as ptr<char>):
            sdl_quit()
            return 1
        let renderer: ptr<char> = sdl_renderer_create(window)
        if renderer == (0 as ptr<char>):
            sdl_window_destroy(window)
            sdl_quit()
            return 1
        let g: Game
        g.rng = 0xA0761D6478BD642F
        g.best = 0
        reset(&g, 0)
        let now: i64 = 0
        let key: i64 = 0
        let delay: i64 = 140
        let status: i64 = 0
        while not g.quit:
            key = sdl_poll_input()
            while key != 0:
                if key < 0:
                    g.quit = true
                else:
                    input(&g, key, now)
                key = sdl_poll_input()
            if g.quit:
                break
            now = now + 16
            if g.started and not g.paused and not g.over:
                delay = 140 - (g.score / 50) * 10
                if delay < 55:
                    delay = 55
                if now - g.last_step >= delay:
                    g.last_step = now
                    if not step(&g):
                        g.over = true
            render(renderer, &g)
            sdl_delay(16)
            status = sdl_set_draw_color(renderer, 0, 0, 0, 255)
            if status != 0:
                g.quit = true
        sdl_renderer_destroy(renderer)
        sdl_window_destroy(window)
        sdl_quit()
    return 0
