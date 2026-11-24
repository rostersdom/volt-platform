use browser_window

unsafe extern fn SDL_GetAudioDeviceStatus(device: u32) -> i32

unsafe fn wait_for_append(video: ptr<BrowserVideo>, position: i64):
    let deadline: i64 = http_deadline_after(3500)
    while video.stream.wait_ms == 0 or video.stream.queued or video.position_ms < position or video.stream.pcm.data.len != 0:
        if http_remaining_ms(deadline) < 0 or video.phase != BROWSER_VIDEO_PLAYING: panic("stream fixture never requested input")
        browser_video_poll(video)
        sdl_delay(5)

unsafe fn wait_for_pcm(video: ptr<BrowserVideo>, position: i64):
    let deadline: i64 = http_deadline_after(2000)
    while video.audio == 0 or SDL_GetQueuedAudioSize(video.audio) == 0 or video.image.surface == (0 as ptr<char>) or video.position_ms < position:
        if http_remaining_ms(deadline) < 0 or video.phase != BROWSER_VIDEO_PLAYING: panic("stream fixture no scheduled A/V")
        browser_video_poll(video)
        sdl_delay(2)

unsafe fn assert_stream_released(video: ptr<BrowserVideo>):
    if video.worker.pid != 0 or video.audio != 0 or video.audio_initialized or video.stream.append.data != (0 as ptr<u8>) or video.packet.data != (0 as ptr<u8>):
        panic("stream fixture worker, device or buffer leaked")
    if video.stream.frames.data.data != (0 as ptr<u8>) or video.stream.pcm.data.data != (0 as ptr<u8>):
        panic("stream fixture decoded queue leaked")

unsafe fn stream_append(video: ptr<BrowserVideo>, path: string):
    let data: ByteBuffer
    defer bytes_free(&data)
    if bytes_read_file(&data, path) < 0 or browser_video_stream_append(video, data.data, data.len) != 0:
        panic("stream fixture append")

unsafe fn stream_fixture(muxed: bool) -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let page: BrowserPage
    let spare: BrowserPage
    let source: ByteBuffer
    let other: ByteBuffer
    defer bytes_free(&source)
    defer bytes_free(&other)
    if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(page.storage)
    if browser_page_allocate(&spare) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(spare.storage)
    let view: BrowserViewport = BrowserViewport(440, 300)
    page.visual = true
    let markup: string = "<style>body{margin:0} video{width:320px;aspect-ratio:16 / 9}</style><video controls></video>"
    if http_append_text(&source, markup) != 0 or bytes_push(&source, 0 as u8) != 0: return 1
    let policy: BrowserPolicy
    if browser_prepare_loaded_document(&source, "stream-example.html", &page, view, 0 as ptr<HttpTransfer>, &policy) != 0: return 1
    let node: i64 = browser_video_hit(&page, 20, 20)
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    if browser_video_stream_start(video, node) != 0: panic("stream fixture worker start")
    let pid: i64 = video.worker.pid
    if browser_video_stream_append(video, 0 as ptr<u8>, BROWSER_VIDEO_APPEND_BYTES + 1) != -90: panic("stream fixture size budget")
    video.stream.total = BROWSER_VIDEO_BYTES
    if browser_video_stream_append(video, 0 as ptr<u8>, 1) != -90: panic("stream fixture cumulative budget")
    video.stream.total = 0
    stream_append(video, "init.bin")
    if browser_video_stream_append(video, 0 as ptr<u8>, 0) != -11: panic("stream fixture backpressure")
    wait_for_append(video, 0)
    if video.image.surface != (0 as ptr<char>): panic("stream fixture presented without media")
    let first_end: i64 = 900
    let second_end: i64 = 1900
    if muxed:
        first_end = 943
        second_end = 1943
    stream_append(video, "media-1.bin")
    if muxed:
        wait_for_pcm(video, 0)
        if video.position_ms > 150 or not browser_video_pause(video): panic("stream fixture AAC did not start alongside video")
        let buffered: u32 = SDL_GetQueuedAudioSize(video.audio)
        let position: i64 = video.position_ms
        sdl_delay(100)
        if buffered == 0 or (buffered as i64) > BROWSER_VIDEO_SDL_PCM or SDL_GetAudioDeviceStatus(video.audio) != 2 or SDL_GetQueuedAudioSize(video.audio) != buffered or browser_video_poll(video) or video.position_ms != position:
            panic("stream fixture PCM/clock drift during pause")
        if not browser_video_pause(video) or SDL_GetAudioDeviceStatus(video.audio) != 1: panic("stream fixture AAC resume")
    wait_for_append(video, first_end)
    if video.image.surface == (0 as ptr<char>) or video.position_ms != first_end or video.worker.pid != pid:
        panic("stream fixture did not present first segment before next append")
    let surface: ptr<char> = cairo_image_surface_create(CAIRO_ARGB32, view.width as i32, view.height as i32)
    defer cairo_surface_destroy(surface)
    if browser_draw_document(surface, &page, BrowserRect(0, 0, view.width, view.height), 1) != 0:
        panic("stream fixture native rendering before the next append")
    if cairo_surface_write_to_png(surface, "stream-frame.png" as ptr<char>) != 0: return 1
    let frame: ptr<char> = video.image.surface
    let frozen: i64 = video.start_ms
    sdl_delay(280)
    if browser_video_poll(video) or video.image.surface != frame or video.position_ms != first_end or video.start_ms != frozen or video.ended:
        panic("stream fixture lost frame while waiting")
    if muxed and SDL_GetQueuedAudioSize(video.audio) != 0: panic("stream fixture PCM did not drain during starvation")
    if not browser_video_pause(video): panic("stream fixture pause")
    stream_append(video, "media-2.bin")
    if browser_video_poll(video) or not video.stream.queued: panic("stream fixture sent while paused")
    if not browser_video_pause(video): panic("stream fixture resume")
    if muxed: wait_for_pcm(video, 1043)
    wait_for_append(video, second_end)
    if video.position_ms != second_end or video.start_ms - frozen < 160 or video.worker.pid != pid:
        panic("stream fixture did not resume from the next segment")
    if browser_video_stream_append(video, 0 as ptr<u8>, 0) != 0 or browser_video_stream_append(video, 0 as ptr<u8>, 0) != -22:
        panic("stream fixture finish")
    let deadline: i64 = http_deadline_after(2000)
    while video.phase != BROWSER_VIDEO_ENDED:
        if http_remaining_ms(deadline) < 0 or video.phase == BROWSER_VIDEO_FAILED: panic("stream fixture exit")
        browser_video_poll(video)
        sdl_delay(5)
    assert_stream_released(video)

    if browser_video_stream_start(video, node) != 0: return 1
    wait_for_append(video, 0)
    if muxed:
        stream_append(video, "init.bin")
        wait_for_append(video, 0)
        stream_append(video, "media-1.bin")
        wait_for_pcm(video, 0)
    if __volt_js_kill(video.worker.child.pidfd as i64) != 0: panic("stream fixture stop worker")
    deadline = http_deadline_after(2000)
    while video.phase != BROWSER_VIDEO_FAILED:
        if http_remaining_ms(deadline) < 0: panic("stream fixture missed worker exit while waiting")
        browser_video_poll(video)
        sdl_delay(5)
    assert_stream_released(video)

    if browser_video_stream_start(video, node) != 0: return 1
    stream_append(video, "init.bin")
    wait_for_append(video, 0)
    if muxed:
        stream_append(video, "media-1.bin")
        wait_for_pcm(video, 0)
    let controller: BrowserNavigationController
    controller.active_page = &page
    controller.active_buffer = &source
    let child: ptr<BrowserJsChild> = video.worker.child
    browser_swap_page(&controller, &spare, &other)
    assert_stream_released(&spare.storage.visual.video)
    if spare.storage.visual.video.image.surface != (0 as ptr<char>): panic("stream fixture navigation frame leaked")
    deadline = http_deadline_after(2000)
    while http_load_state(&child.state) != JS_SLOT_FREE:
        if http_remaining_ms(deadline) < 0: panic("stream fixture navigation worker not reaped")
        browser_js_reap()
        sdl_delay(5)
    return 0

unsafe fn stream_budget_fixture() -> i64:
    let video: BrowserVideo
    defer browser_video_close(&video)
    if browser_video_stream_start(&video, 1) != 0: return 1
    stream_append(&video, "init.bin")
    wait_for_append(&video, 0)
    stream_append(&video, "media-1.bin")
    let deadline: i64 = http_deadline_after(3500)
    while video.phase != BROWSER_VIDEO_FAILED:
        if http_remaining_ms(deadline) < 0 or video.image.surface != (0 as ptr<char>): panic("stream fixture decoded budget not enforced")
        browser_video_poll(&video)
        sdl_delay(5)
    assert_stream_released(&video)
    return 0

unsafe fn direct_mp4_fixture() -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let page: BrowserPage
    let data: ByteBuffer
    defer bytes_free(&data)
    if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(page.storage)
    page.visual = true
    let deadline: i64 = http_deadline_after(5000)
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    if browser_load_candidate(&page, &data, "video-mp4.html", -1, BrowserViewport(440, 300), &transfer) != 0: return 1
    let node: i64 = browser_video_hit(&page, 30, 35)
    if node < 1 or not browser_video_click(&page, 30, 35): return 1
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    while video.phase == BROWSER_VIDEO_LOADING:
        if http_remaining_ms(deadline) < 0: panic("MP4 fixture loading")
        browser_video_poll(video)
        sdl_delay(5)
    wait_for_pcm(video, 0)
    if video.image.width != 320 or video.image.height != 180 or video.stream.enabled: panic("MP4 fixture direct video")
    while video.phase != BROWSER_VIDEO_ENDED:
        if http_remaining_ms(deadline) < 0 or video.phase == BROWSER_VIDEO_FAILED: panic("MP4 fixture end")
        browser_video_poll(video)
        sdl_delay(5)
    if video.position_ms < 1900: panic("MP4 fixture incomplete playback")
    assert_stream_released(video)
    return 0

fn main() -> i64:
    match arg_at(1):
        Ok(mode):
            unsafe:
                if mode == "budget": return stream_budget_fixture()
                if mode == "direct": return direct_mp4_fixture()
                return stream_fixture(mode == "audio")
        Err(error):
            unsafe: return stream_fixture(false)
