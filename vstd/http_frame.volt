use bytes

const HTTP_HEADER_LIMIT: i64 = 65536

struct HttpFrame:
    scan: i64
    headers_end: i64
    length: i64
    chunked: bool
    chunk_size: i64
    chunk_total: i64

unsafe fn http_frame_equal(p: ptr<char>, start: i64, end: i64, word: string) -> bool:
    let n: i64 = end - start
    if n != __volt_strlen(word): return false
    let i: i64 = 0
    while i < n:
        let c: i64 = p[start + i] as i64
        if c >= 65 and c <= 90: c += 32
        if c != (word as ptr<char>)[i] as i64: return false
        i += 1
    return true

unsafe fn http_frame_headers(p: ptr<char>, state: ptr<HttpFrame>, wire_limit: i64, body_limit: i64) -> i64:
    let at: i64 = 0
    let first: bool = true
    let no_content: bool = false
    let not_modified: bool = false
    state.length = -1
    while at < state.headers_end - 2:
        let end: i64 = at
        while end < state.headers_end - 2 and not (p[end] == '\r' and p[end + 1] == '\n'): end += 1
        if first:
            first = false
            if end >= 12:
                no_content = p[9] == '2' and p[10] == '0' and p[11] == '4'
                not_modified = p[9] == '3' and p[10] == '0' and p[11] == '4'
        else:
            let colon: i64 = at
            while colon < end and p[colon] != ':': colon += 1
            if colon == at or colon == end: return -22
            let start: i64 = colon + 1
            let stop: i64 = end
            while start < stop and (p[start] == ' ' or p[start] == '\t'): start += 1
            while stop > start and (p[stop - 1] == ' ' or p[stop - 1] == '\t'): stop -= 1
            if http_frame_equal(p, at, colon, "content-length"):
                if no_content or state.length >= 0 or start == stop: return -22
                state.length = 0
                while start < stop:
                    let digit: i64 = p[start] as i64 - 48
                    if digit < 0 or digit > 9: return -22
                    if not not_modified:
                        if digit > body_limit or state.length > (body_limit - digit) / 10: return -90
                        state.length = state.length * 10 + digit
                    start += 1
            elif http_frame_equal(p, at, colon, "transfer-encoding"):
                if no_content or not_modified or state.chunked or not http_frame_equal(p, start, stop, "chunked"): return -22
                state.chunked = true
        at = end + 2
    if state.chunked and state.length >= 0: return -22
    if no_content or not_modified: state.length = 0
    if state.length > wire_limit - state.headers_end: return -90
    return 0

unsafe fn http_chunk_digit(c: i64) -> i64:
    if c >= 48 and c <= 57: return c - 48
    if c >= 65 and c <= 70: return c - 55
    if c >= 97 and c <= 102: return c - 87
    return -1

# Returns 1 and keeps the first complete response, or 0 when more bytes (or EOF) are needed.
unsafe fn http_frame_check(buffer: ptr<ByteBuffer>, state: ptr<HttpFrame>, wire_limit: i64, body_limit: i64) -> i64:
    let p: ptr<char> = buffer.data as ptr<char>
    let n: i64 = buffer.len
    if state.headers_end == 0:
        let bound: i64 = min(n, HTTP_HEADER_LIMIT)
        while state.scan + 3 < bound:
            let i: i64 = state.scan
            state.scan += 1
            if p[i] == '\r' and p[i + 1] == '\n' and p[i + 2] == '\r' and p[i + 3] == '\n':
                state.headers_end = i + 4
                let parsed: i64 = http_frame_headers(p, state, wire_limit, body_limit)
                if parsed < 0: return parsed
                state.scan = state.headers_end
                state.chunk_size = -1
                break
        if state.headers_end == 0:
            if n >= HTTP_HEADER_LIMIT: return -90
            return 0
    if not state.chunked:
        let body: i64 = n - state.headers_end
        if state.length < 0:
            if body > body_limit: return -90
            return 0
        if body < state.length: return 0
        buffer.len = state.headers_end + state.length
        return 1
    # The browser's chunk subset excludes extensions and trailers.
    while true:
        let at: i64 = state.scan
        if state.chunk_size < 0:
            let size: i64 = 0
            let remaining: i64 = body_limit - state.chunk_total
            while at < n and p[at] != '\r':
                let digit: i64 = http_chunk_digit(p[at] as i64)
                if digit < 0 or at - state.scan >= 16: return -22
                if digit > remaining or size > (remaining - digit) / 16: return -90
                size = size * 16 + digit
                at += 1
            if at + 1 >= n: return 0
            if at == state.scan or p[at + 1] != '\n': return -22
            state.chunk_size = size
            state.chunk_total += size
            state.scan = at + 2
            at = state.scan
        if state.chunk_size > n - at - 2: return 0
        at += state.chunk_size
        if p[at] != '\r' or p[at + 1] != '\n': return -22
        state.scan = at + 2
        if state.chunk_size == 0:
            buffer.len = state.scan
            return 1
        state.chunk_size = -1
    return -22
