use http

link "-lz"

# z_stream from zlib.h for the Linux x86-64 ABI.
struct BrowserZStream:
    next_in: ptr<u8>
    avail_in: u32
    total_in: u64
    next_out: ptr<u8>
    avail_out: u32
    total_out: u64
    message: ptr<char>
    state: ptr<char>
    allocate: ptr<char>
    release: ptr<char>
    opaque: ptr<char>
    data_type: i32
    adler: u64
    reserved: u64

unsafe extern fn zlibVersion() -> ptr<char>
unsafe extern fn inflateInit2_(stream: ptr<BrowserZStream>, window_bits: i32, version: ptr<char>, size: i32) -> i32
unsafe extern fn inflate(stream: ptr<BrowserZStream>, flush: i32) -> i32
unsafe extern fn inflateEnd(stream: ptr<BrowserZStream>) -> i32

# shortcut: accept single-member gzip while the HTTP loader buffers one response.
unsafe fn browser_gzip_expand(response: ptr<ByteBuffer>, offset: i64, transfer: ptr<HttpTransfer>) -> i64:
    let limit: i64 = transfer.body_bytes
    let length: i64 = response.len - offset
    if offset < 0 or length < 1 or length > limit or limit > 2097152: return -22
    let output: ByteBuffer
    defer bytes_free(&output)
    let allocated: i64 = bytes_reserve(&output, limit + 1)
    if allocated < 0: return allocated
    let stream: BrowserZStream
    stream.next_in = response.data + offset
    stream.avail_in = length as u32
    stream.next_out = output.data
    stream.avail_out = (limit + 1) as u32
    if inflateInit2_(&stream, 31 as i32, zlibVersion(), sizeof(BrowserZStream) as i32) != 0: return -5
    defer inflateEnd(&stream)
    let result: i32 = inflate(&stream, 4 as i32)  # Z_FINISH
    if stream.total_out > (limit as u64): return -90
    if result != 1 or stream.avail_in != 0 or stream.total_out == 0: return -22
    let remaining: i64 = http_transfer_remaining(transfer)
    if remaining < 0: return remaining
    output.len = stream.total_out as i64
    let input: ByteBuffer = response[0]
    response[0] = output
    output = input
    return 0
