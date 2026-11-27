# Optional SDL2 window/software-rendering bindings for Linux x86-64 SysV.
# Importing this module adds a link-time dependency on SDL2.
link "-lSDL2"

unsafe extern fn SDL_Init(flags: i32) -> i32
unsafe extern fn SDL_InitSubSystem(flags: u32) -> i32
unsafe extern fn SDL_QuitSubSystem(flags: u32)
unsafe extern fn SDL_Quit()
unsafe extern fn SDL_CreateThread(entry: fnptr<(ptr<char>) -> i32>, name: ptr<char>, data: ptr<char>) -> ptr<char>
unsafe extern fn SDL_DetachThread(thread: ptr<char>)
unsafe extern fn SDL_AtomicGet(state: ptr<i32>) -> i32
unsafe extern fn SDL_AtomicSet(state: ptr<i32>, value: i32) -> i32
unsafe extern fn SDL_AtomicCAS(state: ptr<i32>, old_value: i32, new_value: i32) -> i32
unsafe extern fn SDL_AtomicAdd(state: ptr<i32>, value: i32) -> i32
unsafe extern fn SDL_CreateWindow(title: ptr<char>, x: i32, y: i32, width: i32, height: i32, flags: i32) -> ptr<char>
unsafe extern fn SDL_DestroyWindow(window: ptr<char>)
unsafe extern fn SDL_GetWindowSize(window: ptr<char>, width: ptr<i32>, height: ptr<i32>)
unsafe extern fn SDL_SetWindowMinimumSize(window: ptr<char>, width: i32, height: i32)
unsafe extern fn SDL_SetWindowMaximumSize(window: ptr<char>, width: i32, height: i32)
unsafe extern fn SDL_SetWindowTitle(window: ptr<char>, title: ptr<char>)
unsafe extern fn SDL_CreateRenderer(window: ptr<char>, index: i32, flags: i32) -> ptr<char>
unsafe extern fn SDL_DestroyRenderer(renderer: ptr<char>)
unsafe extern fn SDL_SetRenderDrawColor(renderer: ptr<char>, r: i32, g: i32, b: i32, a: i32) -> i32
unsafe extern fn SDL_RenderClear(renderer: ptr<char>) -> i32
unsafe extern fn SDL_RenderFillRect(renderer: ptr<char>, rect: ptr<i32>) -> i32
unsafe extern fn SDL_RenderDrawPoint(renderer: ptr<char>, x: i32, y: i32) -> i32
unsafe extern fn SDL_CreateTexture(renderer: ptr<char>, format: u32, access: i32, width: i32, height: i32) -> ptr<char>
unsafe extern fn SDL_DestroyTexture(texture: ptr<char>)
unsafe extern fn SDL_UpdateTexture(texture: ptr<char>, rect: ptr<char>, pixels: ptr<char>, pitch: i32) -> i32
unsafe extern fn SDL_RenderCopy(renderer: ptr<char>, texture: ptr<char>, source: ptr<char>, destination: ptr<char>) -> i32
unsafe extern fn SDL_RenderPresent(renderer: ptr<char>)
unsafe extern fn SDL_PollEvent(event: ptr<char>) -> i32
unsafe extern fn SDL_PeepEvents(events: ptr<char>, numevents: i32, action: i32, min_type: u32, max_type: u32) -> i32
unsafe extern fn SDL_CreateSystemCursor(id: i32) -> ptr<char>
unsafe extern fn SDL_SetCursor(cursor: ptr<char>)
unsafe extern fn SDL_GetDefaultCursor() -> ptr<char>
unsafe extern fn SDL_FreeCursor(cursor: ptr<char>)
unsafe extern fn SDL_CaptureMouse(enabled: i32) -> i32

const SDL_EVENT_QUIT: i64 = 256
const SDL_EVENT_WINDOW: i64 = 512
const SDL_EVENT_KEYDOWN: i64 = 768
const SDL_EVENT_MOUSEWHEEL: i64 = 1027
const SDL_EVENT_MOUSEMOTION: i64 = 1024
const SDL_EVENT_MOUSEBUTTONDOWN: i64 = 1025
const SDL_EVENT_MOUSEBUTTONUP: i64 = 1026
const SDL_EVENT_TEXTINPUT: i64 = 771
const SDL_BUTTON_LEFT: i64 = 1
const SDL_WINDOW_SHOWN: i32 = 4
const SDL_WINDOW_RESIZABLE: i32 = 32
const SDL_SYSTEM_CURSOR_IBEAM: i32 = 1
const SDL_SYSTEM_CURSOR_HAND: i32 = 11
const SDL_WINDOWEVENT_EXPOSED: i64 = 3
const SDL_WINDOWEVENT_SIZE_CHANGED: i64 = 6
const SDL_WINDOWEVENT_LEAVE: i64 = 11
const SDL_WINDOWEVENT_FOCUS_LOST: i64 = 13
const SDL_WINDOWEVENT_CLOSE: i64 = 14
const SDL_KEY_LEFT: i64 = 1073741904
const SDL_KEY_RIGHT: i64 = 1073741903
const SDL_KEY_UP: i64 = 1073741906
const SDL_KEY_DOWN: i64 = 1073741905
const SDL_KEY_PAGEUP: i64 = 1073741899
const SDL_KEY_PAGEDOWN: i64 = 1073741902
const SDL_KEY_HOME: i64 = 1073741898
const SDL_KEY_END: i64 = 1073741901
const SDL_KEY_F5: i64 = 1073741886
const SDL_KEY_KP_ENTER: i64 = 1073741912
const SDL_KEY_ADDRESS: i64 = -1000
const SDL_KEY_SELECT_ALL: i64 = -1001
const SDL_KEY_PASTE: i64 = -1002
const SDL_KEY_COPY: i64 = -1003
const SDL_KEY_CUT: i64 = -1004
const SDL_KEY_HISTORY: i64 = -1005
const SDL_KEY_BACK: i64 = -1006
const SDL_KEY_FORWARD: i64 = -1007
const SDL_KEY_START: i64 = -1008
const SDL_KEY_RELOAD: i64 = -1009
const SDL_KEY_ZOOM_IN: i64 = -1010
const SDL_KEY_ZOOM_OUT: i64 = -1011
const SDL_KEY_ZOOM_RESET: i64 = -1012
const SDL_INPUT_EVENT_NONE: i64 = 0
const SDL_INPUT_EVENT_QUIT: i64 = 1
const SDL_INPUT_EVENT_KEY: i64 = 2
const SDL_INPUT_EVENT_WHEEL: i64 = 3
const SDL_INPUT_EVENT_BUTTON: i64 = 4
const SDL_INPUT_EVENT_TEXT: i64 = 5
const SDL_INPUT_EVENT_REDRAW: i64 = 6
const SDL_INPUT_EVENT_RESIZE: i64 = 7
const SDL_INPUT_EVENT_MOTION: i64 = 8
const SDL_INPUT_EVENT_RELEASE: i64 = 9
const SDL_INPUT_EVENT_LEAVE: i64 = 10
const SDL_INPUT_EVENT_BLUR: i64 = 11

struct SdlInputEvent:
    kind: i64
    key: i64
    wheel_y: i64
    button: i64  # Mouse button. Key events use this slot for Shift modifiers.
    mouse_x: i64
    mouse_y: i64

struct SdlInputSummary:
    quit: bool
    key: i64
    wheel_y: i64
    other_events: i64
    click_count: i64
    clicks: [64]SdlInputEvent
    event_count: i64
    overflow: bool
    events: [1024]SdlInputEvent
    text: [1024][32]char

unsafe extern fn SDL_Delay(ms: u32)
unsafe extern fn SDL_StartTextInput()
unsafe extern fn SDL_StopTextInput()
unsafe extern fn SDL_SetTextInputRect(rect: ptr<i32>)
unsafe extern fn SDL_GetClipboardText() -> ptr<char>
unsafe extern fn SDL_SetClipboardText(text: ptr<char>) -> i32
unsafe extern fn SDL_free(memory: ptr<char>)

# All returned pointers are opaque SDL-owned handles. Caller controls lifecycle.
unsafe fn sdl_init() -> i64:
    return SDL_Init(32) as i64

unsafe fn sdl_quit():
    SDL_Quit()

unsafe fn sdl_text_input_start():
    SDL_StartTextInput()

unsafe fn sdl_text_input_stop():
    SDL_StopTextInput()

unsafe fn sdl_window_create(title: string, width: i64, height: i64) -> ptr<char>:
    return sdl_window_with_flags(title, width, height, SDL_WINDOW_SHOWN)

unsafe fn sdl_window_with_flags(title: string, width: i64, height: i64, flags: i32) -> ptr<char>:
    if width <= 0 or height <= 0 or width > 2147483647 or height > 2147483647:
        return 0 as ptr<char>
    let title_ptr: ptr<char> = title as ptr<char>
    return SDL_CreateWindow(title_ptr, 805240832, 805240832, width as i32, height as i32, flags)

unsafe fn sdl_window_destroy(window: ptr<char>):
    if window != (0 as ptr<char>):
        SDL_DestroyWindow(window)

unsafe fn sdl_renderer_create(window: ptr<char>) -> ptr<char>:
    if window == (0 as ptr<char>):
        return 0 as ptr<char>
    return SDL_CreateRenderer(window, -1, 1)

unsafe fn sdl_renderer_destroy(renderer: ptr<char>):
    if renderer != (0 as ptr<char>):
        SDL_DestroyRenderer(renderer)

unsafe fn sdl_set_draw_color(renderer: ptr<char>, r: i64, g: i64, b: i64, a: i64) -> i64:
    if renderer == (0 as ptr<char>):
        return -22
    if r < 0 or r > 255 or g < 0 or g > 255 or b < 0 or b > 255 or a < 0 or a > 255:
        return -22
    return SDL_SetRenderDrawColor(renderer, r as u8, g as u8, b as u8, a as u8) as i64

unsafe fn sdl_clear(renderer: ptr<char>) -> i64:
    if renderer == (0 as ptr<char>):
        return -22
    return SDL_RenderClear(renderer) as i64

unsafe fn sdl_fill_rect(renderer: ptr<char>, x: i64, y: i64, w: i64, h: i64) -> i64:
    if renderer == (0 as ptr<char>):
        return -22
    if x < -2147483648 or x > 2147483647 or y < -2147483648 or y > 2147483647:
        return -22
    if w <= 0 or w > 2147483647 or h <= 0 or h > 2147483647:
        return -22
    # SDL_Rect is four C ints. Pass its address; never pass a C struct by value.
    let rect: [4]i32
    rect[0] = x as i32
    rect[1] = y as i32
    rect[2] = w as i32
    rect[3] = h as i32
    return SDL_RenderFillRect(renderer, &rect[0]) as i64

unsafe fn sdl_draw_point(renderer: ptr<char>, x: i64, y: i64) -> i64:
    if renderer == (0 as ptr<char>) or x < -2147483648 or x > 2147483647 or y < -2147483648 or y > 2147483647:
        return -22
    return SDL_RenderDrawPoint(renderer, x as i32, y as i32) as i64

# ARGB8888 packed words match VOLT's 0xAARRGGBB u32 framebuffer.
unsafe fn sdl_texture_create_argb8888(renderer: ptr<char>, width: i64, height: i64) -> ptr<char>:
    if renderer == (0 as ptr<char>) or width <= 0 or height <= 0 or width > 4096 or height > 4096:
        return 0 as ptr<char>
    return SDL_CreateTexture(renderer, 372645892 as u32, 1, width as i32, height as i32)

unsafe fn sdl_texture_destroy(texture: ptr<char>):
    if texture != (0 as ptr<char>): SDL_DestroyTexture(texture)

unsafe fn sdl_texture_update_argb8888(texture: ptr<char>, pixels: ptr<u32>, width: i64, height: i64, stride: i64, capacity: i64) -> i64:
    if texture == (0 as ptr<char>) or pixels == (0 as ptr<u32>) or width <= 0 or width > 4096 or height <= 0 or height > 4096:
        return -22
    if stride < width or stride > 4096 or capacity < 0 or stride > 536870911:
        return -22
    let total: i64 = stride * height
    if total <= 0 or capacity < total or stride * 4 > 2147483647:
        return -22
    return SDL_UpdateTexture(texture, 0 as ptr<char>, pixels as ptr<char>, (stride * 4) as i32) as i64

unsafe fn sdl_texture_copy(renderer: ptr<char>, texture: ptr<char>) -> i64:
    if renderer == (0 as ptr<char>) or texture == (0 as ptr<char>): return -22
    return SDL_RenderCopy(renderer, texture, 0 as ptr<char>, 0 as ptr<char>) as i64

unsafe fn sdl_texture_copy_at(renderer: ptr<char>, texture: ptr<char>, rect: ptr<i32>) -> i64:
    if renderer == (0 as ptr<char>) or texture == (0 as ptr<char>) or rect == (0 as ptr<i32>): return -22
    return SDL_RenderCopy(renderer, texture, 0 as ptr<char>, rect as ptr<char>) as i64

unsafe fn sdl_present(renderer: ptr<char>):
    if renderer != (0 as ptr<char>):
        SDL_RenderPresent(renderer)

# SDL_Event occupies 56 bytes on the supported SDL2 ABI.
unsafe fn sdl_decode_event(event_ptr: ptr<char>) -> SdlInputEvent:
    if event_ptr == (0 as ptr<char>): return SdlInputEvent(SDL_INPUT_EVENT_NONE, 0, 0, 0, 0, 0)
    let event_type: u32 = *(event_ptr as ptr<u32>)
    if event_type == SDL_EVENT_QUIT as u32: return SdlInputEvent(SDL_INPUT_EVENT_QUIT, 0, 0, 0, 0, 0)
    if event_type == SDL_EVENT_TEXTINPUT as u32: return SdlInputEvent(SDL_INPUT_EVENT_TEXT, 0, 0, 0, 0, 0)
    if event_type == SDL_EVENT_WINDOW as u32:
        let event_code: u8 = *((event_ptr as ptr<u8>) + 12)
        if event_code == SDL_WINDOWEVENT_CLOSE as u8: return SdlInputEvent(SDL_INPUT_EVENT_QUIT, 0, 0, 0, 0, 0)
        if event_code == SDL_WINDOWEVENT_EXPOSED as u8: return SdlInputEvent(SDL_INPUT_EVENT_REDRAW, 0, 0, 0, 0, 0)
        if event_code == SDL_WINDOWEVENT_SIZE_CHANGED as u8: return SdlInputEvent(SDL_INPUT_EVENT_RESIZE, 0, 0, 0, 0, 0)
        if event_code == SDL_WINDOWEVENT_LEAVE as u8: return SdlInputEvent(SDL_INPUT_EVENT_LEAVE, 0, 0, 0, 0, 0)
        if event_code == SDL_WINDOWEVENT_FOCUS_LOST as u8: return SdlInputEvent(SDL_INPUT_EVENT_BLUR, 0, 0, 0, 0, 0)
        return SdlInputEvent(SDL_INPUT_EVENT_NONE, 0, 0, 0, 0, 0)
    if event_type == SDL_EVENT_KEYDOWN as u32:
        let key: ptr<i32> = (event_ptr + 20) as ptr<i32>
        let modifiers: ptr<u16> = (event_ptr + 24) as ptr<u16>
        let code: i64 = key[0] as i64
        if (modifiers[0] & 0x00c0) != 0:
            if code == 108: code = SDL_KEY_ADDRESS
            elif code == 97: code = SDL_KEY_SELECT_ALL
            elif code == 118: code = SDL_KEY_PASTE
            elif code == 99: code = SDL_KEY_COPY
            elif code == 120: code = SDL_KEY_CUT
            elif code == 104: code = SDL_KEY_HISTORY
            elif code == 114: code = SDL_KEY_RELOAD
            elif code == 43 or code == 61: code = SDL_KEY_ZOOM_IN
            elif code == 45: code = SDL_KEY_ZOOM_OUT
            elif code == 48: code = SDL_KEY_ZOOM_RESET
        elif (modifiers[0] & 0x0300) != 0:
            if code == SDL_KEY_LEFT: code = SDL_KEY_BACK
            elif code == SDL_KEY_RIGHT: code = SDL_KEY_FORWARD
            elif code == SDL_KEY_HOME: code = SDL_KEY_START
        return SdlInputEvent(SDL_INPUT_EVENT_KEY, code, 0, (modifiers[0] & 3) as i64, 0, 0)
    if event_type == SDL_EVENT_MOUSEWHEEL as u32:
        let wheel: ptr<i32> = (event_ptr + 20) as ptr<i32>
        let vertical: i64 = wheel[0] as i64
        if wheel[1] == 1: vertical = -vertical
        return SdlInputEvent(SDL_INPUT_EVENT_WHEEL, 0, vertical, 0, 0, 0)
    if event_type == SDL_EVENT_MOUSEMOTION as u32:
        let coords: ptr<i32> = (event_ptr + 20) as ptr<i32>
        return SdlInputEvent(SDL_INPUT_EVENT_MOTION, 0, 0, 0, coords[0] as i64, coords[1] as i64)
    if event_type == SDL_EVENT_MOUSEBUTTONDOWN as u32 or event_type == SDL_EVENT_MOUSEBUTTONUP as u32:
        let bytes: ptr<u8> = event_ptr as ptr<u8>
        let button: i64 = bytes[16] as i64
        let x: ptr<i32> = (event_ptr + 20) as ptr<i32>
        let kind: i64 = SDL_INPUT_EVENT_BUTTON
        if event_type == SDL_EVENT_MOUSEBUTTONUP as u32: kind = SDL_INPUT_EVENT_RELEASE
        return SdlInputEvent(kind, 0, 0, button, x[0] as i64, x[1] as i64)
    return SdlInputEvent(SDL_INPUT_EVENT_NONE, 0, 0, 0, 0, 0)

# Copies SDL_TextInputEvent.text into a caller-owned buffer of at least 32 bytes.
unsafe fn sdl_copy_text_event(event_ptr: ptr<char>, output: ptr<char>):
    let text: ptr<char> = event_ptr + 12
    let i: i64 = 0
    while i < 31 and text[i] != 0 as char:
        output[i] = text[i]
        i += 1
    output[i] = 0 as char

# Drains every queued event; last key and summed wheel delta preserve all scroll input.
unsafe fn sdl_poll_events() -> SdlInputSummary:
    let event: [7]i64
    let event_words: ptr<i64> = &event[0]
    let event_ptr: ptr<char> = event_words as ptr<char>
    let summary: SdlInputSummary
    summary.quit = false
    summary.key = 0
    summary.wheel_y = 0
    summary.other_events = 0
    summary.click_count = 0
    summary.event_count = 0
    summary.overflow = false
    while SDL_PollEvent(event_ptr) != 0:
        let decoded: SdlInputEvent = sdl_decode_event(event_ptr)
        if decoded.kind == SDL_INPUT_EVENT_QUIT: summary.quit = true
        if decoded.kind == SDL_INPUT_EVENT_MOTION and summary.event_count > 0:
            if summary.events[summary.event_count - 1].kind == SDL_INPUT_EVENT_MOTION:
                summary.events[summary.event_count - 1] = decoded
                continue
        if summary.event_count >= 1024:
            summary.overflow = true
            summary.other_events += 1
            continue
        summary.events[summary.event_count] = decoded
        if decoded.kind == SDL_INPUT_EVENT_TEXT:
            sdl_copy_text_event(event_ptr, &summary.text[summary.event_count][0])
        else:
            summary.text[summary.event_count][0] = 0 as char
        summary.event_count += 1
        if decoded.kind == SDL_INPUT_EVENT_KEY:
            summary.key = decoded.key
        elif decoded.kind == SDL_INPUT_EVENT_WHEEL:
            if decoded.wheel_y > 0 and summary.wheel_y > 9223372036854775807 - decoded.wheel_y:
                summary.wheel_y = 9223372036854775807
            elif decoded.wheel_y < 0 and summary.wheel_y < -9223372036854775807 - decoded.wheel_y:
                summary.wheel_y = -9223372036854775807
            else:
                summary.wheel_y += decoded.wheel_y
        elif decoded.kind == SDL_INPUT_EVENT_BUTTON and decoded.button == SDL_BUTTON_LEFT as i64:
            if summary.click_count < 64:
                summary.clicks[summary.click_count] = decoded
                summary.click_count += 1
        elif decoded.kind != SDL_INPUT_EVENT_QUIT:
            summary.other_events += 1
    return summary

unsafe fn sdl_poll_quit() -> bool:
    return sdl_poll_events().quit

# Returns one queued key, -1 on quit, or 0 when none; drains other queued events.
unsafe fn sdl_poll_input() -> i64:
    let events: SdlInputSummary = sdl_poll_events()
    if events.quit: return -1
    return events.key

unsafe fn sdl_delay(ms: i64):
    if ms > 0 and ms <= 1000:
        SDL_Delay(ms as u32)
