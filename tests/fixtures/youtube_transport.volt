# Staged in place of browser_youtube_transport only in a temporary test workspace.
use browser_youtube_view
use sdl

let youtube_fixture_checks: i32 = 0
let youtube_fixture_plays: i32 = 0
let youtube_fixture_unexpected: i32 = 0
let youtube_fixture_mode: i32 = 0    # 0 success, 1 redirect, 2 wait for cancellation

unsafe fn browser_youtube_get(host: string, path: string, out: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    let metadata: bool = host == "www.youtube.com" and path == "/watch?v=AbC_123-xyz"
    let video: bool = host == "r1.googlevideo.com" and path == "/videoplayback?id=mock&token=a%2Bb"
    if not metadata and not video:
        SDL_AtomicAdd(&youtube_fixture_unexpected, 1)
        return -22
    let mode: i32 = SDL_AtomicGet(&youtube_fixture_mode)
    if metadata: SDL_AtomicAdd(&youtube_fixture_checks, 1)
    else: SDL_AtomicAdd(&youtube_fixture_plays, 1)
    if mode == 2:
        while http_transfer_remaining(transfer) > 0: sdl_delay(5)
        return http_transfer_remaining(transfer)
    out.len = 0
    if mode == 1:
        return http_append_text(out, "HTTP/1.0 302 Found\r\nLocation: https://r2.googlevideo.com/videoplayback?id=redirect\r\nContent-Length: 0\r\n\r\n")
    transfer.clean_eof = true
    if metadata:
        return http_append_text(out, "HTTP/1.0 200 OK\r\nContent-Type: text/html\r\nSet-Cookie: ignored=1\r\n\r\n<img src=\"not-rendered\"><script>var ytInitialPlayerResponse = {\"playabilityStatus\":{\"status\":\"OK\"},\"videoDetails\":{\"videoId\":\"AbC_123-xyz\",\"title\":\"VOLT \\u003cimg src='literal'\\u003e & \\\"clip\\\" 🎬\"},\"streamingData\":{\"formats\":[{\"itag\":43,\"mimeType\":\"video/webm\",\"url\":\"https://r1.googlevideo.com/videoplayback?id=mock\\u0026token=a%2Bb\"}]}};</script>")
    let file: ByteBuffer
    defer bytes_free(&file)
    if bytes_read_file(&file, "examples/video-demo.webm") < 0: return -5
    let status: i64 = http_append_text(out, "HTTP/1.0 200 OK\r\nContent-Type: video/webm\r\n\r\n")
    if status < 0: return status
    for i in 0..file.len:
        status = bytes_push(out, file.data[i])
        if status < 0: return status
    return 0
