use browser_window

unsafe fn media_fixture(path: string, expect_playback: bool, screenshot: string) -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let page: BrowserPage
    let spare: BrowserPage
    let data: ByteBuffer
    defer bytes_free(&data)
    if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(page.storage)
    if browser_page_allocate(&spare) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(spare.storage)
    page.visual = true
    let deadline: i64 = http_deadline_after(6000)
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    if browser_load_candidate(&page, &data, path, -1, BrowserViewport(640, 480), &transfer) != 0: panic("media fixture document")
    let node: i64 = browser_video_hit(&page, 30, 35)
    if node < 1 or page.boxes[node].width != 320 or page.boxes[node].height != 180: panic("media fixture geometry")
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    if video.phase != 0 or video.worker.pid != 0: panic("media fixture played without a click")
    let scroll: PaintScrollState
    let controller: BrowserNavigationController
    controller.active_page = &page
    controller.candidate_page = &spare
    controller.scroll = &scroll
    let controls: BrowserControls
    browser_controls_init(&controls, &page, 696, 622)
    let canvas: BrowserCanvas
    let pane: BrowserRect = chrome_page(&controls)
    let event: SdlInputEvent = SdlInputEvent(SDL_INPUT_EVENT_BUTTON, 0, 0, SDL_BUTTON_LEFT, pane.x + 30, pane.y + 35)
    if not browser_handle_event(&controls, &controller, &canvas, event, "" as ptr<char>): panic("media fixture click")
    if not expect_playback:
        while video.phase != BROWSER_VIDEO_FAILED:
            if http_remaining_ms(deadline) < 0: panic("media fixture rejection deadline")
            browser_video_poll(video)
            sdl_delay(8)
        if video.image.surface != (0 as ptr<char>): panic("media fixture blocked frame")
        return 0
    while video.image.surface == (0 as ptr<char>) or video.audio == 0:
        if video.phase == BROWSER_VIDEO_FAILED or http_remaining_ms(deadline) < 0: panic("media fixture first frame and audio")
        browser_video_poll(video)
        sdl_delay(8)
    if video.image.width != 480 or video.image.height != 270 or video.duration_ms < 6000: panic("media fixture decoded size or duration")
    if not browser_handle_key(&controls, &controller, 32, false) or video.phase != BROWSER_VIDEO_PAUSED: panic("media fixture pause")
    if browser_video_poll(video): panic("media fixture paused update")
    if browser_reflow_page(&page, &spare, BrowserViewport(240, 300)) != 0: panic("media fixture reflow")
    if page.boxes[node].width != 208 or page.boxes[node].height != 117 or video.phase != BROWSER_VIDEO_PAUSED: panic("media fixture reflow dimensions")
    if not browser_handle_key(&controls, &controller, 32, false) or video.phase != BROWSER_VIDEO_PLAYING: panic("media fixture resume")
    let until: i64 = http_deadline_after(340)
    let changed: bool = false
    while http_remaining_ms(until) > 0:
        if browser_video_poll(video): changed = true
        sdl_delay(8)
    if not changed or video.phase != BROWSER_VIDEO_PLAYING or video.position_ms <= 0: panic("media fixture resume frames")
    let surface: ptr<char> = cairo_image_surface_create(CAIRO_ARGB32, 240, 300)
    defer cairo_surface_destroy(surface)
    if browser_draw_document(surface, &page, BrowserRect(0, 0, 240, 300), 1) != 0: panic("media fixture presentation")
    if cairo_surface_write_to_png(surface, screenshot as ptr<char>) != 0: panic("media fixture screenshot")
    if browser_web_prefix(path) == 0:
        let end_deadline: i64 = http_deadline_after(7500)
        while video.phase != BROWSER_VIDEO_ENDED:
            if video.phase == BROWSER_VIDEO_FAILED or http_remaining_ms(end_deadline) < 0: panic("media fixture end")
            browser_video_poll(video)
            sdl_delay(8)
        if video.audio != 0 or video.worker.pid != 0 or video.position_ms != video.duration_ms: panic("media fixture end state")
        if not browser_handle_event(&controls, &controller, &canvas, event, "" as ptr<char>) or video.phase != BROWSER_VIDEO_LOADING:
            panic("media fixture replay")
    browser_video_close(video)
    if video.worker.pid != 0 or video.audio != 0 or video.image.surface != (0 as ptr<char>): panic("media fixture cleanup")
    return 0

fn main() -> i64:
    match arg_at(1):
        Ok(path):
            match arg_at(2):
                Ok(screenshot):
                    unsafe: return media_fixture(path, screenshot != "blocked", screenshot)
                Err(error): return 2
        Err(error): return 2
