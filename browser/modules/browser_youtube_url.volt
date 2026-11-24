# VOLT strings end at NUL. Check counted input for embedded NUL before casting it to string.
use html
use http
use http_frame

const YOUTUBE_MEDIA_URL_LIMIT: i64 = 8192

# Reject raw whitespace, controls and backslashes.
unsafe fn youtube_url_length(p: ptr<char>, limit: i64) -> i64:
    if p == (0 as ptr<char>): return -1
    let n: i64 = 0
    while p[n] != (0 as char):
        let c: char = p[n]
        if n == limit or c <= ' ' or c == 127 or c == '\\': return -1
        n += 1
    return n

unsafe fn youtube_url_authority_end(p: ptr<char>, start: i64, n: i64) -> i64:
    let i: i64 = start
    while i < n and p[i] != '/' and p[i] != '?' and p[i] != '#': i += 1
    return i

unsafe fn youtube_id_valid(p: ptr<char>, n: i64) -> bool:
    if n != 11: return false
    for i in 0..11:
        let c: char = p[i]
        if not ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '_' or c == '-'): return false
    return true

# Extract only an ID for a canonical HTTPS URL. On failure, leave the caller's [12]char unchanged.
unsafe fn youtube_video_id(url: string, out: ptr<char>) -> bool:
    if out == (0 as ptr<char>): return false
    let p: ptr<char> = url as ptr<char>
    let n: i64 = youtube_url_length(p, YOUTUBE_MEDIA_URL_LIMIT)
    if n < 0: return false
    let host: i64 = 0
    let port: string = ":443"
    if n >= 8 and http_frame_equal(p, 0, 8, "https://"):
        host = 8
    elif n >= 7 and http_frame_equal(p, 0, 7, "http://"):
        host = 7
        port = ":80"

    let path: i64 = youtube_url_authority_end(p, host, n)
    if path >= n or p[path] != '/': return false
    let host_end: i64 = host
    while host_end < path and p[host_end] != ':': host_end += 1
    # Only explicit schemes may carry their default port; no other port syntax is accepted.
    if host_end < path and (host == 0 or not http_frame_equal(p, host_end, path, port)): return false
    let short_host: bool = http_frame_equal(p, host, host_end, "youtu.be")
    if not short_host and not http_frame_equal(p, host, host_end, "youtube.com") and not http_frame_equal(p, host, host_end, "www.youtube.com") and not http_frame_equal(p, host, host_end, "m.youtube.com"): return false

    let path_end: i64 = path
    while path_end < n and p[path_end] != '?' and p[path_end] != '#': path_end += 1
    let watch: bool = not short_host and path_end - path == 6 and html_match(p, path, path_end, "/watch")
    let id: i64 = -1
    let id_end: i64 = path_end
    if short_host: id = path + 1
    elif not watch:
        if html_match(p, path, path_end, "/shorts/"): id = path + 8
        elif html_match(p, path, path_end, "/live/"): id = path + 6
        elif html_match(p, path, path_end, "/embed/"): id = path + 7
        else: return false

    # Only /watch takes a literal v parameter in the &-separated query.
    if path_end < n and p[path_end] == '?':
        let term: i64 = path_end + 1
        while term < n and p[term] != '#':
            let end: i64 = term
            while end < n and p[end] != '&' and p[end] != '#': end += 1
            let key_end: i64 = term
            while key_end < end and p[key_end] != '=': key_end += 1
            # The encoded spelling of v could otherwise hide a second video ID.
            if key_end - term == 3 and html_match(p, term, key_end, "%76"): return false
            if key_end - term == 1 and p[term] == 'v':
                if not watch or id >= 0 or key_end == end: return false
                id = key_end + 1
                id_end = end
            term = end
            if term < n and p[term] == '&': term += 1

    if id < 0 or not youtube_id_valid(p + id, id_end - id): return false
    for i in 0..11: out[i] = p[id + i]
    out[11] = 0 as char
    return true

# Check only the URL syntax, not reachability. The signed query must be sent unchanged.
unsafe fn youtube_media_url(url: string) -> bool:
    let p: ptr<char> = url as ptr<char>
    let n: i64 = youtube_url_length(p, YOUTUBE_MEDIA_URL_LIMIT)
    if not html_match(p, 0, n, "https://"): return false
    let path: i64 = youtube_url_authority_end(p, 8, n)
    let domain: string = ".googlevideo.com"
    let suffix: i64 = path - __volt_strlen(domain)
    # A real subdomain is required. DNS label validation also rules out userinfo and ports.
    if suffix <= 8 or not http_frame_equal(p, suffix, path, domain) or not http_host_valid(p + 8, path - 8): return false

    let endpoint: string = "/videoplayback?"
    let i: i64 = path + __volt_strlen(endpoint)
    if i >= n or not html_match(p, path, n, endpoint): return false
    while i < n:
        let c: char = p[i]
        if c >= 127 or c == '#' or c == '"' or c == '<' or c == '>' or c == '{' or c == '}' or c == '|' or c == '^' or c == '`': return false
        if c == '%':
            if i + 2 >= n: return false
            let high: i64 = http_chunk_digit(p[i + 1] as i64)
            let low: i64 = http_chunk_digit(p[i + 2] as i64)
            if high < 0 or low < 0: return false
            let byte: i64 = high * 16 + low
            if byte < 32 or byte == 127 or byte == '\\': return false
            i += 2
        i += 1
    return true
