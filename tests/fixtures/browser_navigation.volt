use browser_window
use process
use fs

unsafe fn wait_for_file(path: string) -> bool:
    let deadline: i64 = http_deadline_after(3000)
    while true:
        match file_size(path):
            Ok(size): return true
            Err(error):
                if http_remaining_ms(deadline) < 0: return false
                sdl_delay(1)
    return false

unsafe extern fn SDL_PushEvent(event: ptr<char>) -> i32
unsafe extern fn SDL_GetWindowID(window: ptr<char>) -> u32
unsafe extern fn SDL_SetWindowSize(window: ptr<char>, width: i32, height: i32)

const TEST_WIDTH: i64 = 696
const TEST_HEIGHT: i64 = 566

unsafe fn wait_load(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    if controls.pending and controls.job == (0 as ptr<BrowserLoadJob>): browser_start_load(controls, controller)
    while controls.job != (0 as ptr<BrowserLoadJob>):
        if browser_poll_load(controls, controller): return
        sdl_delay(1)

unsafe fn handle(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>, event: SdlInputEvent, text: ptr<char>) -> bool:
    let handled: bool = browser_handle_event(controls, controller, canvas, event, text)
    wait_load(controls, controller)
    return handled

fn click(rect: BrowserRect) -> SdlInputEvent:
    return SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, rect.x + rect.w / 2, rect.y + rect.h / 2)

fn key(code: i64) -> SdlInputEvent:
    return SdlInputEvent(SDL_INPUT_EVENT_KEY, code, 0, 0, 0, 0)

unsafe fn dispatch_queued(window: ptr<char>, renderer: ptr<char>, canvas: ptr<BrowserCanvas>, controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>) -> bool:
    let events: SdlInputSummary = sdl_poll_events()
    let handled: i64 = browser_dispatch_batch(window, renderer, canvas, controls, controller, &events)
    wait_load(controls, controller)
    return handled > 0

unsafe fn verify_navigation(base: string, directory: string, window: ptr<char>, renderer: ptr<char>) -> i64:
    let active: BrowserPage
    let candidate: BrowserPage
    let active_buffer: ByteBuffer
    let candidate_buffer: ByteBuffer
    bytes_init(&active_buffer)
    bytes_init(&candidate_buffer)
    defer bytes_free(&active_buffer)
    defer bytes_free(&candidate_buffer)
    let active_storage: ptr<BrowserPageStorage> = browser_page_allocate(&active)
    if active_storage == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(active.storage)
    let candidate_storage: ptr<BrowserPageStorage> = browser_page_allocate(&candidate)
    if candidate_storage == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(candidate.storage)
    let pixels_a: [307200]u32
    let pixels_b: [307200]u32
    let scroll: PaintScrollState = PaintScrollState(0, 0)
    let controller: BrowserNavigationController = BrowserNavigationController(&active, &candidate, &active_buffer, &candidate_buffer, &pixels_a[0], &pixels_b[0], &scroll, 0 as ptr<char>, 0, 0, false)
    let controls: BrowserControls
    defer browser_load_job_abandon(controls.job)
    let canvas: BrowserCanvas
    defer browser_canvas_free(&canvas)
    let empty: ptr<char> = "" as ptr<char>
    if browser_controller_navigate_url(&controller, str_concat(base, "/start")) != 1: return 2
    let start: string = str_concat(base, "/docs/section/index?q=/search/path")
    if active.url != start: return 3
    browser_controls_init(&controls, &active, TEST_WIDTH, TEST_HEIGHT)
    controls.zoom = 1
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 4
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 4
    if pixels_a[320] != 0xffffffff as u32 or active.document_height != 976: return 5
    let back: SdlInputEvent = click(chrome_nav(CHROME_BACK))
    let forward: SdlInputEvent = click(chrome_nav(CHROME_FORWARD))
    let pane: BrowserRect = chrome_page(&controls)
    let jump: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + 1, pane.y)
    let anchored: string = str_concat(start, "#%D1%8F")
    if not handle(&controls, &controller, &canvas, jump, empty) or active.url != anchored or scroll.offset != 552: return 30
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != start or scroll.offset != 0: return 31
    if not handle(&controls, &controller, &canvas, forward, empty) or active.url != anchored or scroll.offset != 552: return 32
    if not handle(&controls, &controller, &canvas, back, empty) or scroll.offset != 0 or controller.request_count != 1: return 33
    let raw: [7]i64 = [0, 0, 0, 0, 0, 0, 0]
    let event: ptr<char> = (&raw[0]) as ptr<char>
    *((event + 8) as ptr<u32>) = SDL_GetWindowID(window)
    *(event as ptr<u32>) = SDL_EVENT_MOUSEWHEEL as u32
    let wheel: ptr<i32> = (event + 20) as ptr<i32>
    wheel[0] = -1
    if not handle(&controls, &controller, &canvas, sdl_decode_event(event), empty) or scroll.offset != 32: return 6
    let track: BrowserRect = chrome_scroll_track(&controls)
    let grab: SdlInputEvent = click(chrome_scroll_thumb(&controls, &scroll))
    if not handle(&controls, &controller, &canvas, grab, empty) or controls.scroll_grab < 0: return 51
    let drag: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_MOTION, 0, 0, 0, grab.mouse_x, track.y + track.h)
    if not handle(&controls, &controller, &canvas, drag, empty) or scroll.offset != scroll.max_offset: return 51
    let release: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_RELEASE, 0, 0, SDL_BUTTON_LEFT, drag.mouse_x, drag.mouse_y)
    if not handle(&controls, &controller, &canvas, release, empty) or controls.scroll_grab != -1: return 51
    if not handle(&controls, &controller, &canvas, key(SDL_KEY_HOME), empty) or scroll.offset != 0: return 51
    let end: SdlInputEvent = key(SDL_KEY_END)
    if not handle(&controls, &controller, &canvas, end, empty) or scroll.offset != 552: return 7
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 8
    let x: i64 = pane.x + 1
    let y: i64 = pane.y + 408
    cairo_surface_flush(canvas.document_surface)
    let stride: i64 = (cairo_image_surface_get_stride(canvas.document_surface) as i64) / 4
    let visible: ptr<u32> = cairo_image_surface_get_data(canvas.document_surface) as ptr<u32>
    let link_ink: bool = false
    let plain_ink: bool = false
    let row: i64 = 408
    while row < 424:
        let column: i64 = 0
        while column < 12:
            let color: i64 = visible[row * stride + column] as i64
            let red: i64 = (color >> 16) & 255
            let blue: i64 = color & 255
            if column < 6 and blue > red + 16: link_ink = true
            if column >= 6 and red == blue and red < 192: plain_ink = true
            column += 1
        row += 1
    if not link_ink or not plain_ink: return 9
    let right_click: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, 3, x, y)
    if handle(&controls, &controller, &canvas, right_click, empty): return 10
    let miss: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, 500, 400)
    if handle(&controls, &controller, &canvas, miss, empty): return 11
    let next_glyph: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + 7, y)
    if handle(&controls, &controller, &canvas, next_glyph, empty): return 13
    let motion: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_MOTION, 0, 0, 0, x, y)
    if not handle(&controls, &controller, &canvas, motion, empty): return 45
    if (&controls.hover_url[0]) as string != str_concat(base, "/docs/next?x=1&y=2"): return 45
    *(event as ptr<u32>) = SDL_EVENT_MOUSEBUTTONDOWN as u32
    *((event as ptr<u8>) + 16) = SDL_BUTTON_LEFT as u8
    let coords: ptr<i32> = (event + 20) as ptr<i32>
    coords[0] = x as i32
    coords[1] = y as i32
    if SDL_PushEvent(event) != 1: return 12
    if not dispatch_queued(window, renderer, &canvas, &controls, &controller): return 14
    let destination: string = str_concat(base, "/docs/next?x=1&y=2")
    if active.url != destination or active.layout_width != pane.w: return 15
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 15
    cairo_surface_flush(canvas.document_surface)
    if *((cairo_image_surface_get_data(canvas.document_surface)) as ptr<u32>) != 0xff33aa55 as u32: return 15
    let first: ptr<CssFlowFragment> = &active.fragments[0]
    if first.color_rgb != 0x112244: return 25
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != start: return 16
    if not handle(&controls, &controller, &canvas, click(chrome_history_button(&controls)), empty) or not controls.history_open: return 17
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 17
    if not handle(&controls, &controller, &canvas, key(SDL_KEY_UP), empty): return 17
    if not handle(&controls, &controller, &canvas, key(13), empty) or active.url != destination or controls.history_open: return 17
    let reload: SdlInputEvent = key(SDL_KEY_F5)
    if not handle(&controls, &controller, &canvas, reload, empty) or active.url != destination: return 18
    *(event as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
    coords[0] = 108
    coords[1] = 0x0040
    if SDL_PushEvent(event) != 1 or not dispatch_queued(window, renderer, &canvas, &controls, &controller) or not controls.focused: return 19
    # sdl2-compat cannot queue fabricated text events through SDL_PushEvent.
    *(event as ptr<u32>) = SDL_EVENT_TEXTINPUT as u32
    let broken: string = str_concat(base, "/broken")
    event[12] = 'a'
    event[13] = 0 as char
    let input: [32]char
    sdl_copy_text_event(event, &input[0])
    if not handle(&controls, &controller, &canvas, sdl_decode_event(event), &input[0]): return 20
    if (&controls.address[0]) as string != "a": return 21
    if SDL_SetClipboardText(broken as ptr<char>) != 0: return 26
    let select_all: SdlInputEvent = key(SDL_KEY_SELECT_ALL)
    if not handle(&controls, &controller, &canvas, select_all, empty): return 27
    *(event as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
    *((event + 12) as ptr<u32>) = 1 as u32
    coords[0] = 118
    coords[1] = 0x0040
    if SDL_PushEvent(event) != 1 or not dispatch_queued(window, renderer, &canvas, &controls, &controller): return 28
    if (&controls.address[0]) as string != broken: return 29
    let enter: SdlInputEvent = key(13)
    if not handle(&controls, &controller, &canvas, enter, empty): return 22
    if active.url != destination or (&controls.address[0]) as string != destination or controls.status == "" or not controls.retry: return 23
    if scroll.offset != 0 or controller.request_count != 6: return 24
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 24
    cairo_surface_flush(canvas.document_surface)
    if *(cairo_image_surface_get_data(canvas.document_surface) as ptr<u32>) != 0xff33aa55 as u32: return 24
    if not handle(&controls, &controller, &canvas, click(chrome_retry_button(&controls)), empty): return 46
    if controls.retry or controls.status != "" or active.url != broken or controller.request_count != 7: return 46
    if (&controls.title[0]) as string != "Recovered" or browser_history_at(&controls.history, controls.history.current) != broken: return 46

    if browser_controller_navigate_url(&controller, base) != 1: return 34
    browser_controls_init(&controls, &active, TEST_WIDTH, TEST_HEIGHT)
    controls.zoom = 1
    browser_fit_page(&controls, &controller, 1, true)
    let topic: string = str_concat(base, "/#topic")
    if not handle(&controls, &controller, &canvas, jump, empty) or active.url != topic or scroll.offset != 552: return 35
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != base or scroll.offset != 0: return 36
    if not handle(&controls, &controller, &canvas, forward, empty) or scroll.offset != 552 or controller.request_count != 8: return 37

    let index: string = str_concat(directory, "/index.html")
    let chapter: string = str_concat(directory, "/chapter 2#draft.html#end")
    if browser_controller_navigate_url(&controller, index) != 1: return 38
    browser_controls_init(&controls, &active, TEST_WIDTH, TEST_HEIGHT)
    controls.zoom = 1
    browser_fit_page(&controls, &controller, 1, true)
    if not handle(&controls, &controller, &canvas, jump, empty) or active.url != chapter or scroll.offset != 552: return 39
    if not handle(&controls, &controller, &canvas, reload, empty) or active.url != chapter or controls.status != "" or scroll.offset != 552: return 40
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != index: return 41
    if not handle(&controls, &controller, &canvas, forward, empty) or active.url != chapter or scroll.offset != 552: return 42
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != index: return 43
    let draft: string = str_concat(index, "#draft")
    browser_focus_address(&controls)
    browser_insert_address(&controls, draft as ptr<char>)
    if not handle(&controls, &controller, &canvas, enter, empty) or active.url != draft or active.styles[1].background_rgb != 0x224466: return 44
    if not handle(&controls, &controller, &canvas, click(chrome_nav(CHROME_HOME)), empty) or not chrome_is_home(&active): return 47
    SDL_SetWindowSize(window, CHROME_MIN_WIDTH as i32, CHROME_MIN_HEIGHT as i32)
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 47
    if canvas.width != CHROME_MIN_WIDTH or canvas.height != CHROME_MIN_HEIGHT: return 47
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 47
    let compact_pixels: ptr<u32> = cairo_image_surface_get_data(canvas.surface) as ptr<u32>
    if compact_pixels[0] != (0xff000000 | CHROME_BAR) as u32: return 47
    if chrome_history_button(&controls).w != 36 or chrome_address_text(&controls).w < 140: return 47
    let home: ChromeHome = chrome_home_layout(&controls)
    if not handle(&controls, &controller, &canvas, click(chrome_home_address(home)), empty) or not controls.focused: return 48
    browser_insert_address(&controls, "abяz" as ptr<char>)
    if not handle(&controls, &controller, &canvas, key(SDL_KEY_LEFT), empty): return 48
    if not handle(&controls, &controller, &canvas, key(8), empty): return 48
    browser_insert_address(&controls, "ю" as ptr<char>)
    if (&controls.address[0]) as string != "abюz" or controls.caret != 4: return 48
    if not handle(&controls, &controller, &canvas, key(27), empty) or controls.focused: return 48
    let wide: string = str_concat(directory, "/wide.html")
    let bridge: string = str_concat(directory, "/bridge.html")
    if not browser_queue(&controls, bridge, -1, -1, false): return 49
    wait_load(&controls, &controller)
    if active.url != bridge or browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 49
    *(event as ptr<u32>) = SDL_EVENT_MOUSEBUTTONDOWN as u32
    *((event as ptr<u8>) + 16) = SDL_BUTTON_LEFT as u8
    coords[0] = (chrome_page(&controls).x + 1) as i32
    coords[1] = chrome_page(&controls).y as i32
    if SDL_PushEvent(event) != 1 or SDL_PushEvent(event) != 1: return 53
    if not dispatch_queued(window, renderer, &canvas, &controls, &controller) or active.url != wide: return 53
    let narrow_height: i64 = active.document_height
    if active.layout_width != chrome_page(&controls).w or (&controls.title[0]) as string != "Wide test" or narrow_height <= 16: return 49
    SDL_SetWindowSize(window, CHROME_START_WIDTH as i32, CHROME_START_HEIGHT as i32)
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 50
    if active.layout_width != chrome_page(&controls).w or active.document_height >= narrow_height: return 50
    if not handle(&controls, &controller, &canvas, key(SDL_KEY_ZOOM_IN), empty): return 50
    if controls.zoom != 2 or active.layout_width != chrome_page(&controls).w / 2: return 50
    if browser_draw_frame(renderer, &canvas, &controller, &controls) != 0: return 50
    let zoomed_pane: BrowserRect = chrome_page(&controls)
    # The first glyph's link is six document pixels wide, including the spacing.
    let zoomed_jump: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, zoomed_pane.x + 8, zoomed_pane.y + 10)
    let details: string = str_concat(wide, "#details")
    if not handle(&controls, &controller, &canvas, zoomed_jump, empty) or active.url != details: return 52
    if scroll.offset != browser_fragment_y(&active) or scroll.offset <= 0: return 54
    let old_offset: i64 = scroll.offset
    SDL_SetWindowSize(window, CHROME_MIN_WIDTH as i32, CHROME_MIN_HEIGHT as i32)
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 54
    if scroll.offset != browser_fragment_y(&active) or scroll.offset <= old_offset: return 54
    if not handle(&controls, &controller, &canvas, key(SDL_KEY_ZOOM_RESET), empty): return 54
    if controls.zoom != 1 or scroll.offset != browser_fragment_y(&active): return 54

    let overflow: string = str_concat(directory, "/overflow.html")
    let history_size: i64 = controls.history.count
    if not browser_queue(&controls, overflow, -1, -1, false): return 55
    browser_start_load(&controls, &controller)
    if controls.job == (0 as ptr<BrowserLoadJob>): return 55
    SDL_SetWindowSize(window, CHROME_START_WIDTH as i32, CHROME_START_HEIGHT as i32)
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 55
    wait_load(&controls, &controller)
    if active.url != details or not controls.retry or controls.status != browser_error(-7): return 55
    if controls.history.count != history_size or scroll.offset != browser_fragment_y(&active): return 55
    SDL_SetWindowSize(window, CHROME_MIN_WIDTH as i32, CHROME_MIN_HEIGHT as i32)
    if browser_resize(window, renderer, &canvas, &controls, &controller) != 0: return 55
    if not handle(&controls, &controller, &canvas, click(chrome_retry_button(&controls)), empty): return 55
    if active.url != overflow or controls.retry or controls.history.count != history_size + 1: return 55
    history_size = controls.history.count
    let slow: string = str_concat(base, "/slow")
    let cancel: i64 = 0
    while cancel < 2:
        if not browser_queue(&controls, slow, -1, -1, false): return 56
        browser_start_load(&controls, &controller)
        if controls.job == (0 as ptr<BrowserLoadJob>): return 56
        # The loopback handler sends one marker before stalling. Wait for it before issuing Stop.
        let marker: string = str_concat(directory, "/slow-key")
        if cancel == 1: marker = str_concat(directory, "/slow-click")
        if not wait_for_file(marker): return 56
        if cancel == 0:
            *(event as ptr<u32>) = SDL_EVENT_KEYDOWN as u32
            *((event + 12) as ptr<u32>) = 1 as u32
            coords[0] = 27
            coords[1] = 0
        else:
            let stop: SdlInputEvent = click(chrome_nav(CHROME_RELOAD))
            *(event as ptr<u32>) = SDL_EVENT_MOUSEBUTTONDOWN as u32
            *((event as ptr<u8>) + 16) = SDL_BUTTON_LEFT as u8
            coords[0] = stop.mouse_x as i32
            coords[1] = stop.mouse_y as i32
        if SDL_PushEvent(event) != 1: return 56
        if cancel == 1 and SDL_PushEvent(event) != 1: return 56
        let requests_before_stop: i64 = controller.request_count
        if not dispatch_queued(window, renderer, &canvas, &controls, &controller): return 56
        if controller.request_count != requests_before_stop: return 56
        if controls.pending or controls.job != (0 as ptr<BrowserLoadJob>) or controls.retry: return 56
        if active.url != overflow or controls.history.count != history_size: return 56
        if not wait_for_file(str_concat(marker, "-closed")): return 56
        cancel += 1
    if not handle(&controls, &controller, &canvas, back, empty) or active.url != details: return 56
    let response: ByteBuffer
    defer bytes_free(&response)
    let redirected: [8193]char
    let deadline: i64 = http_deadline_after(1500)
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    if browser_load_http(str_concat(base, "/budget-start"), &response, &redirected[0], &transfer) != HTTP_TIMEOUT: return 57
    return 0

fn main() -> i64:
    let base: string = ""
    match arg_at(1):
        Ok(argument): base = argument
        Err(error): return 1
    let directory: string = ""
    match arg_at(2):
        Ok(argument): directory = argument
        Err(error): return 1
    unsafe:
        if sdl_init() != 0: return 1
        defer sdl_quit()
        let window: ptr<char> = sdl_window_with_flags("VOLT navigation test", TEST_WIDTH, TEST_HEIGHT, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE)
        if window == (0 as ptr<char>): return 1
        defer sdl_window_destroy(window)
        let renderer: ptr<char> = sdl_renderer_create(window)
        if renderer == (0 as ptr<char>): return 1
        defer sdl_renderer_destroy(renderer)
        let status: i64 = verify_navigation(base, directory, window, renderer)
        if status != 0: print(status)
        return status
