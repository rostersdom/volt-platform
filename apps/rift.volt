# VOLT: Rift Delver — пошаговый ASCII-рогалик для Linux x86-64.
# ./volt apps/rift.volt --run
# WASD/стрелки — ходить, Space — удар, P — зелье, Q — выход.
# Клавиши Q/Space/P сделаны одиночными, чтобы не повторять действие на каждый кадр удержания.

native fn ioctl(fd: i64, cmd: i64, arg: i64) -> i64:
{
    mov rax, 16
    syscall
}

native fn sleep_ms(ms: i64) -> i64:
{
    mov rax, rdi
    imul rax, rax, 1000000
    sub rsp, 16
    mov qword ptr [rsp], 0
    mov qword ptr [rsp + 8], rax
    mov rdi, rsp
    xor rsi, rsi
    mov rax, 35
    syscall
    add rsp, 16
}

struct Rift:
    px: i64
    py: i64
    ex: [6]i64
    ey: [6]i64
    ehp: [6]i64
    alive: [6]bool
    hp: i64
    max_hp: i64
    mana: i64
    potions: i64
    xp: i64
    level: i64
    floor: i64
    gold: i64
    turns: i64
    rng: u64
    won: bool
    dead: bool
    quit: bool
    escape: i64
    message: i64

fn choose<T>(preferred: T, fallback: T, condition: bool) -> T:
    if condition:
        return preferred
    return fallback

unsafe fn frame_char(buf: ptr<char>, pos: ptr<i64>, c: char):
    buf[pos[0]] = c
    pos[0] = pos[0] + 1

unsafe fn frame_text(buf: ptr<char>, pos: ptr<i64>, text: string):
    let chars: ptr<char> = text as ptr<char>
    let i: i64 = 0
    while chars[i] != 0:
        frame_char(buf, pos, chars[i])
        i += 1

unsafe fn frame_int(buf: ptr<char>, pos: ptr<i64>, value: i64):
    let digits: [20]char
    let count: i64 = 0
    let n: u64 = 0
    if value < 0:
        frame_char(buf, pos, '-')
        n = (0 - (value + 1)) as u64
        n += 1
    else:
        n = value as u64
    if n == 0:
        frame_char(buf, pos, '0')
        return
    while n > 0:
        digits[count] = '0' + ((n % 10) as char)
        n = n / 10
        count += 1
    while count > 0:
        count -= 1
        frame_char(buf, pos, digits[count])

unsafe fn rnd(g: ptr<Rift>) -> u64:
    g.rng = g.rng ^ (g.rng << 13)
    g.rng = g.rng ^ (g.rng >> 7)
    g.rng = g.rng ^ (g.rng << 17)
    return g.rng

unsafe fn enemy_at(g: ptr<Rift>, x: i64, y: i64) -> i64:
    let i: i64 = 0
    while i < 6:
        if g.alive[i] and g.ex[i] == x and g.ey[i] == y:
            return i
        i += 1
    return -1

unsafe fn adjacent_enemy(g: ptr<Rift>) -> Option<i64>:
    let i: i64 = enemy_at(g, g.px + 1, g.py)
    if i < 0: i = enemy_at(g, g.px - 1, g.py)
    if i < 0: i = enemy_at(g, g.px, g.py + 1)
    if i < 0: i = enemy_at(g, g.px, g.py - 1)
    if i < 0:
        return None
    return Some(i)

unsafe fn wall_at(map: ptr<i64>, x: i64, y: i64) -> bool:
    if x < 0 or x >= 30 or y < 0 or y >= 12:
        return true
    return map[y * 30 + x] == 1

unsafe fn build_floor(g: ptr<Rift>, map: ptr<i64>):
    let i: i64 = 0
    while i < 360:
        map[i] = 0
        i += 1
    let x: i64 = 0
    while x < 30:
        map[x] = 1
        map[11 * 30 + x] = 1
        x += 1
    let y: i64 = 0
    while y < 12:
        map[y * 30] = 1
        map[y * 30 + 29] = 1
        y += 1
    # Комнаты, колонны и руины; стартовый коридор всегда остаётся открытым.
    let n: i64 = 0
    while n < 28:
        let wx: i64 = 3 + (rnd(g) % 24)
        let wy: i64 = 1 + (rnd(g) % 10)
        if (wx < 8 or wx > 11) and (wy < 4 or wy > 7):
            map[wy * 30 + wx] = 1
        n += 1
    g.px = 2
    g.py = 2
    let stairs: i64 = 0
    while stairs < 5:
        let sx: i64 = 23 + (rnd(g) % 5)
        let sy: i64 = 1 + (rnd(g) % 10)
        if map[sy * 30 + sx] == 0:
            map[sy * 30 + sx] = 3
            stairs = 5
    let e: i64 = 0
    while e < 6:
        g.alive[e] = false
        let attempts: i64 = 0
        while attempts < 80 and not g.alive[e]:
            let ex: i64 = 5 + (rnd(g) % 22)
            let ey: i64 = 1 + (rnd(g) % 10)
            if map[ey * 30 + ex] == 0 and (ex > 7 or ey > 5):
                g.ex[e] = ex
                g.ey[e] = ey
                g.ehp[e] = 2 + g.floor
                g.alive[e] = true
            attempts += 1
        e += 1
    # Guaranteed potion and gold cache.
    map[2 * 30 + 7] = 4
    map[8 * 30 + 5] = 5

unsafe fn attack(g: ptr<Rift>):
    let target: Option<i64> = adjacent_enemy(g)
    match target:
        None:
            g.message = 1
        Some(i):
            let level_bonus: i64 = choose(g.level / 2, 0, g.level > 1)
            let damage: i64 = 1 + (rnd(g) % 3) + level_bonus
            g.ehp[i] -= damage
            if g.ehp[i] <= 0:
                g.alive[i] = false
                g.xp += 10 + g.floor * 3
                g.gold += 2 + (rnd(g) % 6)
                g.message = 2
            else:
                g.message = 3

unsafe fn drink(g: ptr<Rift>):
    if g.potions <= 0:
        g.message = 4
        return
    if g.hp == g.max_hp:
        g.message = 5
        return
    g.potions -= 1
    g.hp += 8
    if g.hp > g.max_hp: g.hp = g.max_hp
    g.message = 6

unsafe fn enemy_turn(g: ptr<Rift>, map: ptr<i64>):
    let i: i64 = 0
    while i < 6:
        if g.alive[i]:
            let dx: i64 = 0
            let dy: i64 = 0
            if g.ex[i] < g.px: dx = 1
            elif g.ex[i] > g.px: dx = -1
            elif g.ey[i] < g.py: dy = 1
            elif g.ey[i] > g.py: dy = -1
            let nx: i64 = g.ex[i] + dx
            let ny: i64 = g.ey[i] + dy
            if nx == g.px and ny == g.py:
                let armor: i64 = rnd(g) % 4
                if armor == 0:
                    g.hp -= 1 + g.floor
                    g.message = 7
            elif not wall_at(map, nx, ny) and enemy_at(g, nx, ny) < 0:
                g.ex[i] = nx
                g.ey[i] = ny
        i += 1
    if g.hp <= 0:
        g.hp = 0
        g.dead = true

unsafe fn step(g: ptr<Rift>, map: ptr<i64>, dx: i64, dy: i64):
    let nx: i64 = g.px + dx
    let ny: i64 = g.py + dy
    if wall_at(map, nx, ny):
        g.message = 8
        return
    let foe: i64 = enemy_at(g, nx, ny)
    if foe >= 0:
        attack(g)
        enemy_turn(g, map)
        g.turns += 1
        return
    g.px = nx
    g.py = ny
    let tile: i64 = map[ny * 30 + nx]
    if tile == 4:
        g.potions += 1
        map[ny * 30 + nx] = 0
        g.message = 9
    elif tile == 5:
        g.gold += 15 + (rnd(g) % 11)
        map[ny * 30 + nx] = 0
        g.message = 10
    elif tile == 3:
        if g.floor == 3:
            g.won = true
        else:
            g.floor += 1
            build_floor(g, map)
            g.message = 11
    else:
        g.message = 0
    g.turns += 1
    if not g.won:
        enemy_turn(g, map)
    if g.xp >= g.level * 30:
        g.level += 1
        g.max_hp += 4
        g.hp = g.max_hp
        g.message = 12

unsafe fn render(g: ptr<Rift>, map: ptr<i64>, out: ptr<char>, pos: ptr<i64>):
    frame_char(out, pos, 27 as char)
    frame_text(out, pos, "[H")
    frame_char(out, pos, 27 as char)
    frame_text(out, pos, "[0J")
    frame_text(out, pos, "VOLT RIFT DELVER   Floor ")
    frame_int(out, pos, g.floor)
    frame_text(out, pos, "/3  Level ")
    frame_int(out, pos, g.level)
    frame_text(out, pos, "  XP ")
    frame_int(out, pos, g.xp)
    frame_text(out, pos, "/")
    frame_int(out, pos, g.level * 30)
    frame_text(out, pos, "\nHP ")
    frame_int(out, pos, g.hp)
    frame_char(out, pos, '/')
    frame_int(out, pos, g.max_hp)
    frame_text(out, pos, "  Potions ")
    frame_int(out, pos, g.potions)
    frame_text(out, pos, "  Gold ")
    frame_int(out, pos, g.gold)
    frame_text(out, pos, "  Turns ")
    frame_int(out, pos, g.turns)
    frame_text(out, pos, "\n+------------------------------+\n")
    let y: i64 = 0
    while y < 12:
        frame_char(out, pos, '|')
        let x: i64 = 0
        while x < 30:
            let c: char = ' '
            let d: i64 = (g.px - x) * (g.px - x) + (g.py - y) * (g.py - y)
            if d <= 36:
                let tile: i64 = map[y * 30 + x]
                if tile == 1: c = '#'
                elif tile == 3: c = '>'
                elif tile == 4: c = '!'
                elif tile == 5: c = '$'
                let foe: i64 = enemy_at(g, x, y)
                if foe >= 0: c = 'g'
                if x == g.px and y == g.py: c = '@'
            frame_char(out, pos, c)
            x += 1
        frame_text(out, pos, "|\n")
        y += 1
    frame_text(out, pos, "+------------------------------+\n")
    frame_text(out, pos, "WASD/arrows move  Space attack  P potion  Q quit\n")
    frame_text(out, pos, "# wall  g goblin  ! potion  $ gold  > rift stairs\n")
    if g.message == 1: frame_text(out, pos, "You swing at empty air.\n")
    elif g.message == 2: frame_text(out, pos, "Goblin defeated! XP and gold claimed.\n")
    elif g.message == 3: frame_text(out, pos, "Hit! The goblin is still standing.\n")
    elif g.message == 4: frame_text(out, pos, "No potions left.\n")
    elif g.message == 5: frame_text(out, pos, "Already at full health.\n")
    elif g.message == 6: frame_text(out, pos, "Potion restores your wounds.\n")
    elif g.message == 7: frame_text(out, pos, "A goblin hits you!\n")
    elif g.message == 8: frame_text(out, pos, "The ancient stone blocks your way.\n")
    elif g.message == 9: frame_text(out, pos, "Potion found.\n")
    elif g.message == 10: frame_text(out, pos, "Gold cache looted.\n")
    elif g.message == 11: frame_text(out, pos, "The rift pulls you deeper...\n")
    elif g.message == 12: frame_text(out, pos, "LEVEL UP! Restored to full health.\n")
    else: frame_char(out, pos, '\n')

unsafe fn handle_key(g: ptr<Rift>, map: ptr<i64>, c: char):
    if c == 'q' or c == 'Q' or c == 3:
        g.quit = true
    elif c == ' ':
        attack(g)
        enemy_turn(g, map)
        g.turns += 1
    elif c == 'p' or c == 'P':
        let result: Result<i64, i32> = potion_turn(g, map)
        match result:
            Ok(healed):
                if healed > 0:
                    enemy_turn(g, map)
                    g.turns += 1
            Err(code): g.message = 4
    elif c == 'w' or c == 'W': step(g, map, 0, -1)
    elif c == 's' or c == 'S': step(g, map, 0, 1)
    elif c == 'a' or c == 'A': step(g, map, -1, 0)
    elif c == 'd' or c == 'D': step(g, map, 1, 0)

unsafe fn potion_turn(g: ptr<Rift>, map: ptr<i64>) -> Result<i64, i32>:
    if g.potions <= 0:
        return Err(1 as i32)
    if g.hp == g.max_hp:
        return Err(2 as i32)
    drink(g)
    return Ok(g.hp)

fn main() -> i64:
    unsafe:
        let term: [64]u8
        let saved: [64]u8
        let map: [360]i64
        let game: Rift
        let output: [2048]char
        let pos: i64 = 0
        let status: i64 = ioctl(0, 0x5401, (&term[0]) as i64)
        if status < 0:
            put_errnl("rift: run from a terminal")
            return 1
        let i: i64 = 0
        while i < 64:
            saved[i] = term[i]
            i += 1
        term[12] = (term[12] & 0xF4) as u8
        term[22] = 0
        term[23] = 0
        status = ioctl(0, 0x5402, (&term[0]) as i64)
        if status < 0:
            put_errnl("rift: cannot enable raw terminal")
            return 1
        game.hp = 18
        game.max_hp = 18
        game.potions = 2
        game.level = 1
        game.floor = 1
        game.rng = 0xD1B54A32D192ED03
        let map_ptr: ptr<i64> = &map[0]
        build_floor(&game, map_ptr)
        let running: bool = true
        let escape: i64 = 0
        let quit: bool = false
        let action_lock: bool = false
        while running and not game.dead and not game.won and not game.quit:
            pos = 0
            render(&game, map_ptr, &output[0], &pos)
            status = write_all(1, &output[0], pos)
            if status < 0:
                game.quit = true
            else:
                sleep_ms(60)
                let input: [32]char
                let count: i64 = read(0, &input[0], 32)
                if count > 0:
                    let j: i64 = 0
                    while j < count:
                        let c: char = input[j]
                        if escape == 0:
                            if c == 27: escape = 1
                            elif c == 'q' or c == 'Q' or c == 3:
                                if not action_lock: handle_key(&game, map_ptr, c)
                                action_lock = true
                            elif c == ' ' or c == 'p' or c == 'P':
                                if not action_lock: handle_key(&game, map_ptr, c)
                                action_lock = true
                            else:
                                action_lock = false
                                handle_key(&game, map_ptr, c)
                        elif escape == 1:
                            if c == '[': escape = 2
                            else: escape = 0
                        else:
                            if c == 'A': step(&game, map_ptr, 0, -1)
                            elif c == 'B': step(&game, map_ptr, 0, 1)
                            elif c == 'D': step(&game, map_ptr, -1, 0)
                            elif c == 'C': step(&game, map_ptr, 1, 0)
                            action_lock = false
                            escape = 0
                        j += 1
        pos = 0
        frame_char(&output[0], &pos, 27 as char)
        frame_text(&output[0], &pos, "[H")
        frame_char(&output[0], &pos, 27 as char)
        frame_text(&output[0], &pos, "[0J")
        frame_char(&output[0], &pos, 27 as char)
        frame_text(&output[0], &pos, "[?25h")
        if game.won:
            frame_text(&output[0], &pos, "THE RIFT IS SEALED — YOU WIN!\n")
        elif game.dead:
            frame_text(&output[0], &pos, "YOU FELL IN THE RIFT.\n")
        else:
            frame_text(&output[0], &pos, "You retreat from the rift.\n")
        frame_text(&output[0], &pos, "Final gold: ")
        frame_int(&output[0], &pos, game.gold)
        frame_text(&output[0], &pos, "  Turns: ")
        frame_int(&output[0], &pos, game.turns)
        frame_char(&output[0], &pos, '\n')
        write_all(1, &output[0], pos)
        status = ioctl(0, 0x5402, (&saved[0]) as i64)
        if status < 0:
            put_errnl("rift: cannot restore terminal")
            return 1
        return 0
