use browser_window

unsafe fn verify_click_wire():
    let pair: [2]i32
    if __volt_js_socketpair(&pair[0]) != 0: panic("JS test socket")
    defer close(pair[0] as i64)
    defer close(pair[1] as i64)
    if __volt_js_nonblock(pair[0] as i64) != 0: panic("JS test nonblocking socket")
    let js: BrowserJs
    js.fd = pair[0] as i64
    js.target_count = 1
    js.targets[0] = 5
    let click: BrowserJsClick
    defer bytes_free(&click.frame)
    click.phase = 1
    click.deadline = http_deadline_after(3000)
    let frame: [6]i64 = [40, 0, 0, 1, 0, 0]
    let data: ptr<char> = (&frame[0]) as ptr<char>
    let reply: BrowserJsReply
    if write(pair[1] as i64, data, 1) != 1 or browser_js_poll_click(&js, &click, &reply) != 0:
        panic("JS split frame header was not retained")
    if write(pair[1] as i64, data + 1, 47) != 47 or browser_js_poll_click(&js, &click, &reply) != 1 or not reply.prevent_default:
        panic("JS split frame did not finish")
    let malformed: [6]i64 = [0, 0, 0, 1, 0, 5]
    # A legal first edit followed by a truncated record must not be applied.
    if browser_js_parse_reply(&js, (&malformed[0]) as ptr<char>, 48, &reply) >= 0 or reply.text != (0 as ptr<CssTextOverrides>):
        panic("JS accepted a malformed transaction")

unsafe fn expect_flow(page: ptr<BrowserPage>, expected: string):
    let i: i64 = 0
    let data: ptr<char> = expected as ptr<char>
    if page.text_length != __volt_strlen(expected): panic("unexpected JS text length")
    while i < page.text_length:
        if page.flow_text[i] != data[i]: panic("unexpected JS DOM text")
        i += 1

unsafe fn wait_click(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    if controls.script_click.pid <= 0: panic("click was not queued asynchronously")
    while controls.script_click.pid > 0:
        if not browser_poll_script_click(controls, controller): sdl_delay(1)

unsafe fn click_label(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>, label: string):
    let pane: BrowserRect = chrome_page(controls)
    let page: ptr<BrowserPage> = controller.active_page
    let text: ptr<char> = page.flow_text
    let i: i64 = 0
    while i < page.fragment_count:
        let fragment: CssFlowFragment = page.fragments[i]
        if fragment.byte_length == __volt_strlen(label) and html_match(text, fragment.byte_start, page.text_length, label):
            let event: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + fragment.x * controls.zoom + 1, pane.y + fragment.y * controls.zoom + 1)
            if not browser_handle_event(controls, controller, canvas, event, "" as ptr<char>): panic("JS click was not handled")
            wait_click(controls, controller)
            return
        i += 1
    panic("JS test link was not rendered")

unsafe fn click_button_background(controls: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>):
    let pane: BrowserRect = chrome_page(controls)
    let page: ptr<BrowserPage> = controller.active_page
    let i: i64 = 1
    while i < page.node_count:
        if page.nodes[i].kind == HTML_ELEMENT and html_name_equal(page.source, &page.nodes[i], "button"):
            let box: CssLayoutBox = page.boxes[i]
            let event: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + (box.x + box.width - 2) * controls.zoom, pane.y + (box.y + 3) * controls.zoom)
            if not browser_handle_event(controls, controller, canvas, event, "" as ptr<char>): panic("button background was not handled")
            wait_click(controls, controller)
            return
        i += 1
    panic("JS test button was not rendered")

unsafe fn exercise_js(path: string, other: string, visual: bool) -> i64:
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
    active.visual = visual
    let pixels: i64 = BROWSER_CONTROLLER_WIDTH * BROWSER_CONTROLLER_HEIGHT
    let frame: ptr<u32> = mmap(pixels * 8) as ptr<u32>
    if (frame as i64) <= 0: return 1
    defer munmap(frame as ptr<char>, pixels * 8)
    let scroll: PaintScrollState
    let controller: BrowserNavigationController = BrowserNavigationController(&active, &candidate, &active_buffer, &candidate_buffer, frame, frame + pixels, &scroll, 0 as ptr<char>, 0, 0, false)
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let controls: BrowserControls
    defer bytes_free(&controls.script_click.frame)
    let canvas: BrowserCanvas
    if browser_controller_navigate_url(&controller, other) != 1: panic("static initial page failed")
    browser_controls_init(&controls, &active, CHROME_START_WIDTH, CHROME_START_HEIGHT)
    if not browser_queue(&controls, path, -1, -1, false): panic("could not queue JS page")
    browser_start_load(&controls, &controller)
    while controls.pending:
        if not browser_poll_load(&controls, &controller): sdl_delay(1)
    if active.storage.js.pid <= 0: panic("JS session missing")
    expect_flow(&active, "Ready🙂RunHangNext")
    click_label(&controls, &controller, &canvas, "Run")
    if controls.pending: panic("preventDefault did not stop navigation")
    expect_flow(&active, "Нажатий: 1🙂RunHangNext")
    if active.storage.js.notice != 1: panic("listener exception was not reported")
    if browser_reflow_page(&active, &candidate, BrowserViewport(620, 480)) != 0: panic("JS reflow failed")
    expect_flow(&active, "Нажатий: 1🙂RunHangNext")
    click_label(&controls, &controller, &canvas, "Run")
    expect_flow(&active, "Нажатий: 2🙂RunHangNext")
    click_button_background(&controls, &controller, &canvas)
    if active.storage.js.pid != 0 or active.storage.js.notice != 2: panic("looping click was not stopped")
    expect_flow(&active, "Нажатий: 2🙂RunHangNext")
    if browser_controller_navigate_url(&controller, other) != 1: panic("second page failed")
    if active.storage.js.pid != 0 or candidate.storage.js.pid != 0: panic("old JS session remained alive")
    expect_flow(&active, "Plain")
    if browser_controller_navigate_url(&controller, path) != 1: panic("JS revisit failed")
    browser_controls_init(&controls, &active, CHROME_START_WIDTH, CHROME_START_HEIGHT)
    click_label(&controls, &controller, &canvas, "Run")
    expect_flow(&active, "Нажатий: 1🙂RunHangNext")
    click_label(&controls, &controller, &canvas, "Next")
    if not controls.pending or (&controls.load.target[0]) as string != other: panic("link default action was not queued")
    browser_start_load(&controls, &controller)
    while controls.pending:
        if not browser_poll_load(&controls, &controller): sdl_delay(1)
    if active.url != other or active.storage.js.pid != 0: panic("navigation did not drop the live JS session")
    if browser_controller_navigate_url(&controller, path) != 1: panic("JS another revisit failed")
    browser_controls_init(&controls, &active, CHROME_START_WIDTH, CHROME_START_HEIGHT)
    let pane: BrowserRect = chrome_page(&controls)
    if not browser_script_click(&controls, &controller, pane.w / controls.zoom - 1, 0, "#obsolete"):
        panic("could not queue the stale click")
    let reply: BrowserJsReply
    browser_js_poll_click(&active.storage.js, &controls.script_click, &reply)
    browser_js_text_free(reply.text)
    if browser_controller_navigate_url(&controller, other) != 1: panic("replacement page failed")
    if browser_poll_script_click(&controls, &controller) or controls.script_click.pid != 0 or controls.pending:
        panic("stale JS response affected the replacement")
    expect_flow(&active, "Plain")
    return 0

unsafe fn cancel_script_load(path: string) -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let load: BrowserLoad
    load.resource_length = -1
    if browser_copy_address(&load.target[0], path) < 0: return 1
    let options: BrowserPage
    options.scripts_enabled = true
    let job: ptr<BrowserLoadJob>
    if browser_load_job_start(&load, BrowserViewport(640, 480), &options, &job) != 0: return 1
    # The loopback server signals Python after receiving the script request; its reply stays blocked.
    let signal: char = '\0'
    let requested: i64 = read(0, &signal, 1)
    let state: i32 = http_load_state(&job.state)
    browser_load_job_abandon(job)
    if requested != 1 or state != BROWSER_LOAD_RUNNING: panic("script load was not pending at cancellation")
    let deadline: i64 = http_deadline_after(400)
    while http_load_state(&browser_load_workers) != 0:
        if http_remaining_ms(deadline) < 0: panic("script load did not release its navigation worker on cancellation")
        sdl_delay(1)
    return 0

fn main() -> i64:
    let path: string = ""
    let other: string = ""
    match arg_at(1):
        Ok(value): path = value
        Err(error): return 1
    match arg_at(2):
        Ok(value): other = value
        Err(error): return 1
    unsafe:
        if other == "cancel": return cancel_script_load(path)
        verify_click_wire()
        return exercise_js(path, other, argc() > 3)
