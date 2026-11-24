use sdl

fn main() -> i64:
    unsafe:
        let raw: [7]i64 = [0, 0, 0, 0, 0, 0, 0]
        let event: ptr<char> = (&raw[0]) as ptr<char>
        *(event as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
        let key: ptr<i32> = (event + 20) as ptr<i32>
        key[0] = SDL_KEY_PAGEDOWN as i32
        let decoded_key: SdlInputEvent = sdl_decode_event(event)
        if decoded_key.kind != SDL_INPUT_EVENT_KEY or decoded_key.key != SDL_KEY_PAGEDOWN: return 1
        *(event as ptr<u32>) = SDL_EVENT_MOUSEWHEEL as u32
        let wheel: ptr<i32> = (event + 20) as ptr<i32>
        wheel[0] = -3
        let decoded_wheel: SdlInputEvent = sdl_decode_event(event)
        if decoded_wheel.kind != SDL_INPUT_EVENT_WHEEL or decoded_wheel.wheel_y != -3: return 2
        wheel[1] = 1
        if sdl_decode_event(event).wheel_y != 3: return 5
        *(event as ptr<u32>) = SDL_EVENT_QUIT as u32
        if sdl_decode_event(event).kind != SDL_INPUT_EVENT_QUIT: return 3
        *(event as ptr<u32>) = SDL_EVENT_WINDOW as u32
        let code: ptr<u8> = (event as ptr<u8>) + 12
        code[0] = SDL_WINDOWEVENT_CLOSE as u8
        if sdl_decode_event(event).kind != SDL_INPUT_EVENT_QUIT: return 4
    print("scroll event decoding ok")
    return 0
