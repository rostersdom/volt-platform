use browser_window

unsafe fn click_label(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>, label: string) -> bool:
    let pane: BrowserRect = chrome_page(controls)
    let page: ptr<BrowserPage> = controller.active_page
    let text: ptr<char> = page.flow_text
    let i: i64 = 0
    while i < page.fragment_count:
        let fragment: CssFlowFragment = page.fragments[i]
        if fragment.byte_length == __volt_strlen(label) and html_match(text, fragment.byte_start, page.text_length, label):
            let event: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + fragment.x * controls.zoom + 1, pane.y + fragment.y * controls.zoom + 1)
            if not browser_handle_event(controls, controller, canvas, event, "" as ptr<char>): return false
            while controls.script_click.pid > 0:
                if not browser_poll_script_click(controls, controller): sdl_delay(1)
            return true
        i += 1
    return false

fn main() -> i64:
    let path: string = ""
    match arg_at(1):
        Ok(value): path = value
        Err(error): return 1
    unsafe:
        if sdl_init() != 0: return 1
        defer sdl_quit()
        let active: BrowserPage
        let candidate: BrowserPage
        let active_buffer: ByteBuffer
        let candidate_buffer: ByteBuffer
        defer bytes_free(&active_buffer)
        defer bytes_free(&candidate_buffer)
        if browser_page_allocate(&active) == (0 as ptr<BrowserPageStorage>): return 1
        defer browser_page_free(active.storage)
        if browser_page_allocate(&candidate) == (0 as ptr<BrowserPageStorage>): return 1
        defer browser_page_free(candidate.storage)
        active.scripts_enabled = true
        let pixels: i64 = BROWSER_CONTROLLER_WIDTH * BROWSER_CONTROLLER_HEIGHT
        let frame: ptr<u32> = mmap(pixels * 8) as ptr<u32>
        if (frame as i64) <= 0: return 1
        defer munmap(frame as ptr<char>, pixels * 8)
        let scroll: PaintScrollState
        let controller: BrowserNavigationController = BrowserNavigationController(&active, &candidate, &active_buffer, &candidate_buffer, frame, frame + pixels, &scroll, 0 as ptr<char>, 0, 0, false)
        let controls: BrowserControls
        defer bytes_free(&controls.script_click.frame)
        let canvas: BrowserCanvas
        if browser_controller_navigate_url(&controller, path) != 1: return 1
        browser_controls_init(&controls, &active, CHROME_START_WIDTH, CHROME_START_HEIGHT)
        if not click_label(&controls, &controller, &canvas, "Load"): return 1
        if controls.pending: return 1
        let i: i64 = 0
        while i < active.text_length:
            put_char(active.flow_text[i])
            i += 1
        nl()
    return 0
