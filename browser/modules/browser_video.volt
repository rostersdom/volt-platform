use browser_js
use browser_graphics

const BROWSER_VIDEO_BYTES: i64 = 33554432
const BROWSER_VIDEO_APPEND_BYTES: i64 = 1048576
const BROWSER_VIDEO_STREAM_FRAMES: i64 = 33554432
const BROWSER_VIDEO_STREAM_PCM: i64 = 1048576
const BROWSER_VIDEO_SDL_PCM: i64 = 38400
const BROWSER_VIDEO_MAX_MS: i64 = 86400000
const BROWSER_VIDEO_NO_PTS: i64 = BROWSER_VIDEO_MAX_MS + 1
const BROWSER_VIDEO_STREAM_MUXED: i64 = 6
const BROWSER_VIDEO_WIDTH: i64 = 960
const BROWSER_VIDEO_HEIGHT: i64 = 540
const BROWSER_VIDEO_LOADING: i64 = 1
const BROWSER_VIDEO_PLAYING: i64 = 2
const BROWSER_VIDEO_PAUSED: i64 = 3
const BROWSER_VIDEO_ENDED: i64 = 4
const BROWSER_VIDEO_FAILED: i64 = 5
const BROWSER_VIDEO_AUDIO: u32 = 16
const BROWSER_MEDIA_READY: i32 = 1
const BROWSER_MEDIA_CANCELLED: i32 = 2

unsafe extern fn SDL_OpenAudioDevice(name: ptr<char>, capture: i32, desired: ptr<BrowserAudioSpec>, obtained: ptr<BrowserAudioSpec>, changes: i32) -> u32
unsafe extern fn SDL_PauseAudioDevice(device: u32, pause: i32)
unsafe extern fn SDL_QueueAudio(device: u32, data: ptr<char>, size: u32) -> i32
unsafe extern fn SDL_GetQueuedAudioSize(device: u32) -> u32
unsafe extern fn SDL_CloseAudioDevice(device: u32)

struct BrowserAudioSpec:
    rate: i32
    format: u16
    channels: u8
    silence: u8
    samples: u16
    padding: u16
    size: u32
    callback_addr: ptr<char>
    user: ptr<char>

struct BrowserVideoRequest:
    target: [8193]char
    address: [8193]char
    resource_length: i64
    deadline: i64
    state: i32
    youtube: bool
    fd: i64

struct BrowserVideoQueue:
    data: ByteBuffer
    head: i64

struct BrowserVideoStream:
    enabled: bool
    muxed: bool
    finish: bool
    queued: bool
    next_frame: bool
    wait_ms: i64
    origin_ms: i64
    total: i64
    sent: i64
    append: ByteBuffer
    frames: BrowserVideoQueue
    pcm: BrowserVideoQueue

struct BrowserVideo:
    node: i64
    phase: i64
    request: ptr<BrowserVideoRequest>
    worker: BrowserWorker
    stream: BrowserVideoStream
    image: BrowserVideoFrame
    header: [5]i64
    head: i64
    body: i64
    packet: ByteBuffer
    start_ms: i64
    pause_ms: i64
    received_ms: i64
    position_ms: i64
    duration_ms: i64
    audio_initialized: bool
    audio: u32
    muted: bool
    ended: bool
    message: string

struct BrowserVideoFrame:
    surface: ptr<char>
    width: i64
    height: i64

let browser_media_jobs: i32 = 0

unsafe fn browser_video_request_free(request: ptr<BrowserVideoRequest>):
    if request.fd >= 0: close(request.fd)
    munmap(request as ptr<char>, sizeof(BrowserVideoRequest))
    SDL_AtomicAdd(&browser_media_jobs, -1)

unsafe fn browser_video_request_abandon(request: ptr<BrowserVideoRequest>):
    if request != (0 as ptr<BrowserVideoRequest>) and SDL_AtomicSet(&request.state, BROWSER_MEDIA_CANCELLED) == BROWSER_MEDIA_READY:
        browser_video_request_free(request)

unsafe fn browser_video_audio_close(video: ptr<BrowserVideo>):
    if video.audio != 0:
        SDL_CloseAudioDevice(video.audio)
        video.audio = 0
    if video.audio_initialized:
        SDL_QuitSubSystem(BROWSER_VIDEO_AUDIO)
        video.audio_initialized = false

unsafe fn browser_video_stream_free(stream: ptr<BrowserVideoStream>):
    bytes_free(&stream.append)
    bytes_free(&stream.frames.data)
    bytes_free(&stream.pcm.data)

unsafe fn browser_video_close(video: ptr<BrowserVideo>):
    browser_video_request_abandon(video.request)
    browser_worker_stop(&video.worker)
    if video.image.surface != (0 as ptr<char>): cairo_surface_destroy(video.image.surface)
    browser_video_audio_close(video)
    bytes_free(&video.packet)
    browser_video_stream_free(&video.stream)
    let empty: BrowserVideo
    video[0] = empty

unsafe fn browser_video_audio(video: ptr<BrowserVideo>):
    if video.audio_initialized or video.muted: return
    if SDL_InitSubSystem(BROWSER_VIDEO_AUDIO) != 0:
        video.muted = true
        return
    video.audio_initialized = true
    let spec: BrowserAudioSpec
    spec.rate = 48000
    spec.format = 0x8010
    spec.channels = 2
    spec.samples = 1024
    video.audio = SDL_OpenAudioDevice(0 as ptr<char>, 0, &spec, 0 as ptr<BrowserAudioSpec>, 0)
    if video.audio == 0: video.muted = true
    else: SDL_PauseAudioDevice(video.audio, 0)

unsafe fn browser_video_packet_valid(header: ptr<i64>, muxed: bool) -> bool:
    let kind: i64 = header[0]
    let n: i64 = header[1]
    let width: i64 = header[2]
    let height: i64 = header[3]
    if header[4] > BROWSER_VIDEO_MAX_MS or header[4] < -BROWSER_VIDEO_MAX_MS: return false
    if header[4] < 0 and (not muxed or (kind != 1 and kind != 2)): return false
    if kind == 1: return width >= 1 and width <= BROWSER_VIDEO_WIDTH and height >= 1 and height <= BROWSER_VIDEO_HEIGHT and n == width * height * 4
    if kind == 2: return n > 0 and n <= 32768 and n % 4 == 0 and width == 0 and height == 0
    return (kind == 3 or kind == 4) and n == 0 and width == 0 and height == 0

unsafe native fn browser_video_copy(out: ptr<u8>, input: ptr<u8>, size: i64):
{
    mov rcx, rdx
    cld
    rep movsb
}

unsafe fn browser_video_present(video: ptr<BrowserVideo>, width: i64, height: i64, data: ptr<u8>) -> bool:
    let frame: ptr<BrowserVideoFrame> = &video.image
    if frame.surface == (0 as ptr<char>) or frame.width != width or frame.height != height:
        let surface: ptr<char> = cairo_image_surface_create(CAIRO_RGB24, width as i32, height as i32)
        if cairo_surface_status(surface) != 0:
            cairo_surface_destroy(surface)
            return false
        if frame.surface != (0 as ptr<char>): cairo_surface_destroy(frame.surface)
        frame[0] = BrowserVideoFrame(surface, width, height)
    cairo_surface_flush(frame.surface)
    let stride: i64 = cairo_image_surface_get_stride(frame.surface) as i64
    let out: ptr<u8> = cairo_image_surface_get_data(frame.surface) as ptr<u8>
    let row: i64 = width * 4
    if stride == row: browser_video_copy(out, data, row * height)
    else:
        let y: i64 = 0
        while y < height:
            browser_video_copy(out + y * stride, data + y * row, row)
            y += 1
    cairo_surface_mark_dirty(frame.surface)
    return true

unsafe fn browser_video_fail(video: ptr<BrowserVideo>) -> bool:
    browser_worker_stop(&video.worker)
    browser_video_audio_close(video)
    bytes_free(&video.packet)
    browser_video_stream_free(&video.stream)
    video.phase = BROWSER_VIDEO_FAILED
    return true

unsafe fn browser_video_stream_start(video: ptr<BrowserVideo>, node: i64) -> i64:
    if node <= 0: return -22
    browser_video_close(video)
    video.node = node
    let now: i64 = http_now_ms()
    if now < 0: return now
    let status: i64 = browser_worker_spawn("volt-media", -1, "--stream-fmp4", &video.worker)
    if status < 0:
        video.phase = BROWSER_VIDEO_FAILED
        return status
    video.stream.enabled = true
    video.received_ms = now
    video.phase = BROWSER_VIDEO_PLAYING
    return 0

# A zero-length append explicitly finishes the stream; -11 means the previous append is pending.
unsafe fn browser_video_stream_append(video: ptr<BrowserVideo>, data: ptr<u8>, size: i64) -> i64:
    let stream: ptr<BrowserVideoStream> = &video.stream
    if not stream.enabled or stream.finish or video.worker.pid <= 0 or size < 0: return -22
    if size > BROWSER_VIDEO_APPEND_BYTES or size > BROWSER_VIDEO_BYTES - stream.total: return -90
    if stream.queued: return -11
    if size > 0:
        if data == (0 as ptr<u8>): return -22
        let status: i64 = bytes_reserve(&stream.append, size)
        if status < 0: return status
        browser_video_copy(stream.append.data, data, size)
    stream.append.len = size
    stream.total += size
    stream.finish = size == 0
    stream.queued = true
    return 0

unsafe fn browser_video_stream_send(video: ptr<BrowserVideo>, now: i64) -> i64:
    let stream: ptr<BrowserVideoStream> = &video.stream
    if not stream.queued: return 0
    let size: i64 = stream.append.len
    let budget: i64 = 262144
    while stream.sent < 8 + size and budget > 0:
        let data: ptr<u8> = (&stream.append.len) as ptr<u8> + min(8, stream.sent)
        let remain: i64 = 8 - stream.sent
        if stream.sent >= 8:
            data = stream.append.data + (stream.sent - 8)
            remain = 8 + size - stream.sent
        let written: i64 = __volt_http_send(video.worker.fd, data, min(budget, remain))
        if written == -4: continue
        if written == HTTP_EAGAIN:
            if now - video.received_ms > 5000: return HTTP_TIMEOUT
            return 0
        if written <= 0: return -5
        stream.sent += written
        budget -= written
        video.received_ms = now
    if stream.sent != 8 + size: return 0
    stream.sent = 0
    stream.queued = false
    stream.wait_ms = 0
    return 1

unsafe fn browser_video_pause(video: ptr<BrowserVideo>) -> bool:
    let now: i64 = http_now_ms()
    if now < 0: return false
    if video.phase == BROWSER_VIDEO_PLAYING:
        video.phase = BROWSER_VIDEO_PAUSED
        video.pause_ms = now
        if video.audio != 0: SDL_PauseAudioDevice(video.audio, 1)
        return true
    if video.phase == BROWSER_VIDEO_PAUSED:
        if video.start_ms > 0: video.start_ms += now - video.pause_ms
        video.received_ms = now
        video.phase = BROWSER_VIDEO_PLAYING
        if video.audio != 0: SDL_PauseAudioDevice(video.audio, 0)
        return true
    return false

# A partial frame never replaces the visible surface. The socket provides backpressure.
unsafe fn browser_video_read(video: ptr<BrowserVideo>, data: ptr<char>, have: ptr<i64>, size: i64, budget: ptr<i64>, now: i64) -> i64:
    while have[0] < size and budget[0] > 0:
        let count: i64 = read(video.worker.fd, data + have[0], min(budget[0], size - have[0]))
        if count == -4: continue
        if count == -11: return 0
        if count <= 0: return -5
        have[0] += count
        budget[0] -= count
        video.received_ms = now
    if have[0] == size: return 1
    return 0

# The producer may emit a whole video run before audio, so playback waits for a batch.
# shortcut: reject batches over the decoded-byte budgets until there is finer-grained flow control.
unsafe fn browser_video_stage(video: ptr<BrowserVideo>, size: i64) -> bool:
    let queue: ptr<BrowserVideoQueue> = &video.stream.frames
    let limit: i64 = BROWSER_VIDEO_STREAM_FRAMES
    if video.header[0] == 2:
        queue = &video.stream.pcm
        limit = BROWSER_VIDEO_STREAM_PCM
    let at: i64 = queue.data.len
    let padded: i64 = (size + 7) & -8
    if 40 + padded > limit - at or bytes_reserve(&queue.data, at + 40 + padded) < 0: return false
    browser_video_copy(queue.data.data + at, (&video.header[0]) as ptr<u8>, 40)
    browser_video_copy(queue.data.data + at + 40, video.packet.data, size)
    queue.data.len += 40 + padded
    return true

unsafe fn browser_video_queue_time(queue: ptr<BrowserVideoQueue>) -> i64:
    if queue.head == queue.data.len: return BROWSER_VIDEO_NO_PTS
    let header: ptr<i64> = (queue.data.data + queue.head) as ptr<i64>
    return header[4]

unsafe fn browser_video_stream_ready(video: ptr<BrowserVideo>, now: i64) -> bool:
    let first: i64 = min(browser_video_queue_time(&video.stream.frames), browser_video_queue_time(&video.stream.pcm))
    if first == BROWSER_VIDEO_NO_PTS: return true
    if video.start_ms == 0:
        video.stream.origin_ms = first
        video.start_ms = now
        return true
    let due: i64 = video.start_ms + first - video.stream.origin_ms
    if due > now + 5000: return false
    # Credit is not starvation: keep the anchor while playing out existing PCM.
    if due < now and (video.audio == 0 or SDL_GetQueuedAudioSize(video.audio) == 0):
        video.start_ms += now - due
    return true

unsafe fn browser_video_queue_advance(queue: ptr<BrowserVideoQueue>, size: i64):
    queue.head += 40 + ((size + 7) & -8)
    if queue.head == queue.data.len:
        queue.head = 0
        queue.data.len = 0

unsafe fn browser_video_queue_pcm(video: ptr<BrowserVideo>, data: ptr<u8>, size: i64) -> bool:
    browser_video_audio(video)
    if video.audio != 0:
        let queued: i64 = SDL_GetQueuedAudioSize(video.audio) as i64
        if video.stream.muxed: queued += size
        if queued > BROWSER_VIDEO_SDL_PCM: return false
        if SDL_QueueAudio(video.audio, data as ptr<char>, size as u32) != 0:
            browser_video_audio_close(video)
            video.muted = true
    return true

unsafe fn browser_video_stream_play(video: ptr<BrowserVideo>, now: i64) -> i64:
    let dirty: i64 = 0
    let pcm: ptr<BrowserVideoQueue> = &video.stream.pcm
    let frames: ptr<BrowserVideoQueue> = &video.stream.frames
    let time: i64 = now - video.start_ms + video.stream.origin_ms
    for i in 0..32:
        if pcm.data.len == 0: break
        let due: i64 = browser_video_queue_time(pcm)
        if due > time + 5000: return -1
        if due > time + 65 or (due > time and (video.audio == 0 or SDL_GetQueuedAudioSize(video.audio) == 0)): break
        let p: ptr<u8> = pcm.data.data + pcm.head
        let header: ptr<i64> = p as ptr<i64>
        if not browser_video_queue_pcm(video, p + 40, header[1]): break
        browser_video_queue_advance(pcm, header[1])
        if video.ended: video.received_ms = now
    for i in 0..8:
        if frames.data.len == 0: break
        let due: i64 = browser_video_queue_time(frames)
        if due > time + 5000: return -1
        if due > time: break
        let p: ptr<u8> = frames.data.data + frames.head
        let header: ptr<i64> = p as ptr<i64>
        if not browser_video_present(video, header[2], header[3], p + 40): return -1
        video.position_ms = max(video.position_ms, header[4] - video.stream.origin_ms)
        browser_video_queue_advance(frames, header[1])
        dirty = 1
    return dirty

unsafe fn browser_video_update(video: ptr<BrowserVideo>) -> bool:
    if video.phase != BROWSER_VIDEO_PLAYING: return false
    let now: i64 = http_now_ms()
    if now < 0: return browser_video_fail(video)
    let dirty: bool = false
    let stream: ptr<BrowserVideoStream> = &video.stream
    if stream.wait_ms > 0 and stream.sent == 0 and (stream.muxed or not stream.queued):
        # The decoder waiting for input must stay silent, but may have exited.
        let probe: char
        let count: i64 = read(video.worker.fd, &probe, 1)
        if count != HTTP_EAGAIN and count != -4: return browser_video_fail(video)
    if stream.muxed and (stream.wait_ms > 0 or video.ended) and (stream.frames.data.len != 0 or stream.pcm.data.len != 0):
        let played: i64 = browser_video_stream_play(video, now)
        if played < 0: return browser_video_fail(video)
        dirty = played > 0
        if stream.frames.data.len != 0 or stream.pcm.data.len != 0: return dirty
    if video.ended:
        if video.audio != 0 and SDL_GetQueuedAudioSize(video.audio) > 0 and now - video.received_ms < 750: return dirty
        if video.image.surface == (0 as ptr<char>): return browser_video_fail(video)
        browser_video_audio_close(video)
        browser_video_stream_free(stream)
        video.position_ms = max(video.position_ms, video.duration_ms)
        video.phase = BROWSER_VIDEO_ENDED
        return true
    if stream.wait_ms > 0:
        if not stream.queued: return dirty
        let sent: i64 = browser_video_stream_send(video, now)
        if sent < 0: return browser_video_fail(video)
        if sent == 0: return dirty
    let budget: i64 = 3145728
    let i: i64 = 0
    while i < 32 and budget > 0:
        let head: i64 = browser_video_read(video, (&video.header[0]) as ptr<char>, &video.head, 40, &budget, now)
        if head < 0: return browser_video_fail(video)
        if head == 0:
            if now - video.received_ms > 5000: return browser_video_fail(video)
            break
        let kind: i64 = video.header[0]
        if kind == 5 or kind == BROWSER_VIDEO_STREAM_MUXED:
            if not stream.enabled: return browser_video_fail(video)
            if video.header[1] != 0 or video.header[2] != 0 or video.header[3] != 0 or video.header[4] != 0: return browser_video_fail(video)
            video.head = 0
            if kind == BROWSER_VIDEO_STREAM_MUXED:
                if stream.muxed or video.start_ms != 0: return browser_video_fail(video)
                stream.muxed = true
                i += 1
                continue
            if stream.finish and not stream.queued: return browser_video_fail(video)
            stream.wait_ms = now
            if stream.muxed:
                if not browser_video_stream_ready(video, now): return browser_video_fail(video)
                break
            stream.next_frame = true
            let sent: i64 = browser_video_stream_send(video, now)
            if sent < 0: return browser_video_fail(video)
            if sent == 0: break
            i += 1
            continue
        if not browser_video_packet_valid(&video.header[0], stream.muxed): return browser_video_fail(video)
        if stream.enabled and not stream.muxed and kind == 2: return browser_video_fail(video)
        let size: i64 = video.header[1]
        if kind == 4:
            video.duration_ms = video.header[4]
            video.head = 0
            i += 1
            continue
        if kind == 3:
            if stream.enabled and (not stream.finish or stream.queued): return browser_video_fail(video)
            browser_worker_stop(&video.worker)
            bytes_free(&stream.append)
            bytes_free(&video.packet)
            video.ended = true
            if stream.muxed and not browser_video_stream_ready(video, now): return browser_video_fail(video)
            break
        if bytes_reserve(&video.packet, size) < 0: return browser_video_fail(video)
        let received: i64 = browser_video_read(video, video.packet.data as ptr<char>, &video.body, size, &budget, now)
        if received < 0: return browser_video_fail(video)
        if received == 0:
            if now - video.received_ms > 5000: return browser_video_fail(video)
            break
        if stream.muxed:
            if not browser_video_stage(video, size): return browser_video_fail(video)
        else:
            if video.start_ms == 0: video.start_ms = now
            let due: i64 = video.start_ms + video.header[4]
            # Input credit alone is not a stall. Rebase only when the next frame actually arrives late.
            if stream.next_frame:
                stream.next_frame = false
                if due < now:
                    video.start_ms += now - due
                    due = now
            if due > now + 5000: return browser_video_fail(video)
            if kind == 1:
                if due > now: break
                if not browser_video_present(video, video.header[2], video.header[3], video.packet.data): return browser_video_fail(video)
                video.position_ms = max(video.position_ms, video.header[4])
                dirty = true
            elif due > now + 65 or not browser_video_queue_pcm(video, video.packet.data, size): break
        video.head = 0
        video.body = 0
        i += 1
    return dirty
