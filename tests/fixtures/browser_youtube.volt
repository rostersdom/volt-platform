use browser_window

unsafe fn youtube_wait_load(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    let end: i64 = http_deadline_after(3000)
    if c.job == (0 as ptr<BrowserLoadJob>): browser_start_load(c, controller)
    while c.pending:
        if http_remaining_ms(end) < 0: panic("YouTube fixture load timed out")
        if not browser_poll_load(c, controller): sdl_delay(5)
    if c.status != "": panic(c.status)

unsafe fn youtube_click(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, tag: string):
    let page: ptr<BrowserPage> = controller.active_page
    let pane: BrowserRect = chrome_page(c)
    let canvas: BrowserCanvas
    for i in 1..page.node_count:
        if html_name_equal(page.source, &page.nodes[i], tag):
            let box: CssLayoutBox = page.boxes[i]
            if box.hidden or box.width < 8 or box.height < 8: panic("YouTube fixture hidden action")
            let event: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + box.x + 6, pane.y + box.y + 6)
            if not browser_handle_event(c, controller, &canvas, event, "" as ptr<char>): panic("YouTube fixture missed click")
            return
    panic("YouTube fixture missing action")

unsafe fn youtube_assert_inert(page: ptr<BrowserPage>, c: ptr<BrowserControls>):
    if page.url != "about:youtube:AbC_123-xyz" or (&c.address[0]) as string != "https://www.youtube.com/watch?v=AbC_123-xyz":
        panic("YouTube fixture address")
    if page.storage.youtube_node != 0 or page.storage.visual.has_video or page.storage.js.pid != 0:
        panic("YouTube fixture activated by navigation")

unsafe fn youtube_check(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    youtube_click(c, controller, "a")
    if not c.pending or not c.load.youtube_lookup: panic("YouTube fixture check not queued")
    youtube_wait_load(c, controller)

unsafe fn youtube_view_fixture() -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let page: BrowserPage
    let spare: BrowserPage
    let body: ByteBuffer
    let scratch: ByteBuffer
    defer bytes_free(&body)
    defer bytes_free(&scratch)
    if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(page.storage)
    if browser_page_allocate(&spare) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(spare.storage)
    page.visual = true
    page.scripts_enabled = true
    let transfer: HttpTransfer = HttpTransfer(http_deadline_after(3000), 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    if browser_load_candidate(&page, &body, "about:home", -1, BrowserViewport(640, 480), &transfer) != 0: return 1
    let scroll: PaintScrollState
    let controller: BrowserNavigationController
    controller.active_page = &page
    controller.active_buffer = &body
    controller.candidate_page = &spare
    controller.candidate_buffer = &scratch
    controller.scroll = &scroll
    let c: BrowserControls
    browser_controls_init(&c, &page, 696, 622)
    if not browser_queue_link(&c, &page, "https://www.youtube.com/watch?v=AbC_123-xyz") or c.load.youtube_lookup or (&c.load.target[0]) as string != "about:youtube:AbC_123-xyz":
        panic("YouTube fixture link bypassed the local view")
    browser_stop_load(&c, &controller)
    browser_focus_address(&c)
    browser_insert_address(&c, "https://youtu.be/AbC_123-xyz?si=discard&t=8" as ptr<char>)
    if not browser_handle_key(&c, &controller, 13, false): panic("YouTube fixture address not queued")
    youtube_wait_load(&c, &controller)
    youtube_assert_inert(&page, &c)
    if SDL_AtomicGet(&youtube_fixture_checks) != 0: panic("YouTube fixture opened network before opt-in")

    SDL_AtomicSet(&youtube_fixture_mode, 1)
    youtube_check(&c, &controller)
    youtube_assert_inert(&page, &c)
    if SDL_AtomicGet(&youtube_fixture_checks) != 1: panic("YouTube fixture metadata request count")
    SDL_AtomicSet(&youtube_fixture_mode, 2)
    youtube_click(&c, &controller, "a")
    browser_start_load(&c, &controller)
    let until: i64 = http_deadline_after(2000)
    while SDL_AtomicGet(&youtube_fixture_checks) != 2:
        if http_remaining_ms(until) < 0: panic("YouTube fixture pending lookup")
        sdl_delay(5)
    let canvas: BrowserCanvas
    let esc: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_KEY, 27, 0, 0, 0, 0)
    if not browser_handle_event(&c, &controller, &canvas, esc, "" as ptr<char>) or c.pending or c.job != (0 as ptr<BrowserLoadJob>):
        panic("YouTube fixture lookup cancellation")
    youtube_assert_inert(&page, &c)

    SDL_AtomicSet(&youtube_fixture_mode, 0)
    youtube_check(&c, &controller)
    let node: i64 = page.storage.youtube_node
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    if node <= 0 or video.phase != 0 or video.request != (0 as ptr<BrowserVideoRequest>) or SDL_AtomicGet(&youtube_fixture_plays) != 0:
        panic("YouTube fixture media requested without play")
    if (&c.title[0]) as string != "VOLT <img src='literal'> & \"clip\" 🎬" or page.storage.js.pid != 0:
        panic("YouTube fixture title or scripting")
    for i in 1..page.node_count:
        if html_name_equal(page.source, &page.nodes[i], "img") or html_name_equal(page.source, &page.nodes[i], "script"):
            panic("YouTube fixture remote markup entered the DOM")
    if css_find_html_attribute(page.source, &page.nodes[node], page.attributes, "src") >= 0:
        panic("YouTube fixture locator entered HTML")

    SDL_AtomicSet(&youtube_fixture_mode, 2)
    youtube_click(&c, &controller, "video")
    if video.phase != BROWSER_VIDEO_LOADING or not video.request.youtube: panic("YouTube fixture play did not queue native media")
    until = http_deadline_after(2000)
    while SDL_AtomicGet(&youtube_fixture_plays) != 1:
        if http_remaining_ms(until) < 0: panic("YouTube fixture pending media")
        sdl_delay(5)
    if not browser_go(&c, 0, false): panic("YouTube fixture back not queued")
    youtube_wait_load(&c, &controller)
    video = &page.storage.visual.video
    if page.url != "about:home" or video.phase != 0 or video.request != (0 as ptr<BrowserVideoRequest>): panic("YouTube fixture media survived navigation")
    until = http_deadline_after(2000)
    while SDL_AtomicGet(&browser_media_jobs) != 0:
        if http_remaining_ms(until) < 0: panic("YouTube fixture download not cancelled")
        sdl_delay(5)
    if not browser_go(&c, 1, false): panic("YouTube fixture forward not queued")
    youtube_wait_load(&c, &controller)
    youtube_assert_inert(&page, &c)
    if SDL_AtomicGet(&youtube_fixture_checks) != 3: panic("YouTube fixture history repeated opt-in")

    SDL_AtomicSet(&youtube_fixture_mode, 0)
    youtube_check(&c, &controller)
    video = &page.storage.visual.video
    SDL_AtomicSet(&youtube_fixture_mode, 1)
    youtube_click(&c, &controller, "video")
    until = http_deadline_after(3000)
    while video.phase != BROWSER_VIDEO_FAILED:
        if http_remaining_ms(until) < 0 or video.worker.pid != 0: panic("YouTube fixture media redirect")
        browser_video_poll(video)
        sdl_delay(5)
    if SDL_AtomicGet(&youtube_fixture_plays) != 2: panic("YouTube fixture retry request count")

    SDL_AtomicSet(&youtube_fixture_mode, 0)
    youtube_click(&c, &controller, "video")
    until = http_deadline_after(3000)
    while video.image.surface == (0 as ptr<char>) or video.audio == 0:
        if http_remaining_ms(until) < 0 or video.phase == BROWSER_VIDEO_FAILED: panic("YouTube fixture did not receive frames and sound")
        browser_video_poll(video)
        sdl_delay(5)
    if video.image.width != 480 or video.image.height != 270: panic("YouTube fixture decoded dimensions")
    if not browser_handle_key(&c, &controller, 32, false) or video.phase != BROWSER_VIDEO_PAUSED: panic("YouTube fixture pause")
    if not browser_go(&c, c.history.current, true): panic("YouTube fixture reload not queued")
    youtube_wait_load(&c, &controller)
    youtube_assert_inert(&page, &c)
    if SDL_AtomicGet(&youtube_fixture_checks) != 4 or SDL_AtomicGet(&youtube_fixture_plays) != 3 or SDL_AtomicGet(&youtube_fixture_unexpected) != 0:
        panic("YouTube fixture unexpected network activity")
    return 0

fn main() -> i64:
    unsafe: return youtube_view_fixture()
