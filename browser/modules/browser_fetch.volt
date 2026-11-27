# Same-origin fetch transport for page scripts. This is the browser's own
# bounded HTTP(S) stack, not a wrapper around a system browser: JavaScript never
# sees a socket, and every request is resolved, checked and budgeted here.
use bytes
use dns
use http
use http_frame
use tls

const BROWSER_FETCH_BODY_BYTES: i64 = 262144
const BROWSER_FETCH_URL_BYTES: i64 = 8192
const BROWSER_FETCH_TYPE_BYTES: i64 = 128
const BROWSER_FETCH_REDIRECTS: i64 = 3

unsafe fn browser_fetch_web_prefix(p: ptr<char>, n: i64) -> i64:
    if n >= 7 and p[0] == 'h' and p[1] == 't' and p[2] == 't' and p[3] == 'p' and p[4] == ':' and p[5] == '/' and p[6] == '/': return 7
    if n >= 8 and p[0] == 'h' and p[1] == 't' and p[2] == 't' and p[3] == 'p' and p[4] == 's' and p[5] == ':' and p[6] == '/' and p[7] == '/': return 8
    return 0

unsafe fn browser_fetch_fragment(url: string) -> i64:
    let p: ptr<char> = url as ptr<char>
    let n: i64 = __volt_strlen(url)
    let i: i64 = 0
    while i < n and p[i] != '#': i += 1
    return i

unsafe fn browser_fetch_copy_into(out: ptr<char>, used: i64, source: ptr<char>, length: i64, capacity: i64) -> i64:
    if length < 0 or used < 0 or used + length >= capacity: return -90
    let i: i64 = 0
    while i < length:
        out[used + i] = source[i]
        i += 1
    out[used + length] = 0 as char
    return used + length

unsafe fn browser_fetch_equal(a: ptr<char>, b: ptr<char>, length: i64) -> bool:
    let i: i64 = 0
    while i < length:
        let x: i64 = a[i] as i64
        let y: i64 = b[i] as i64
        if x >= 65 and x <= 90: x += 32
        if y >= 65 and y <= 90: y += 32
        if x != y: return false
        i += 1
    return true

unsafe fn browser_fetch_authority_end(p: ptr<char>, n: i64, scheme: i64) -> i64:
    let i: i64 = scheme
    while i < n and p[i] != '/' and p[i] != '?' and p[i] != '#': i += 1
    return i

unsafe fn browser_fetch_query_end(p: ptr<char>, n: i64, scheme: i64) -> i64:
    let i: i64 = scheme
    while i < n and p[i] != '?' and p[i] != '#': i += 1
    return i

unsafe fn browser_fetch_directory_end(p: ptr<char>, from: i64, n: i64) -> i64:
    let i: i64 = n
    while i > from and p[i - 1] != '/': i -= 1
    return i

unsafe fn browser_fetch_parse(url: string, host: ptr<char>, path: ptr<char>, port_out: ptr<i64>) -> i64:
    let p: ptr<char> = url as ptr<char>
    let n: i64 = __volt_strlen(url)
    if n < 8 or n > BROWSER_FETCH_URL_BYTES: return -22
    let scheme: i64 = browser_fetch_web_prefix(p, n)
    if scheme == 0: return -22
    let port: i64 = 80
    if scheme == 8: port = 443
    let authority: i64 = scheme
    let end: i64 = browser_fetch_authority_end(p, n, scheme)
    if end == authority: return -22
    let colon: i64 = -1
    let i: i64 = authority
    while i < end:
        let c: i64 = p[i] as i64
        if c == '@' or c == 92 or c <= 32 or c >= 127: return -22
        if c == ':':
            if colon >= 0: return -22
            colon = i
        i += 1
    let host_end: i64 = end
    if colon >= 0:
        host_end = colon
        if colon + 1 >= end: return -22
    let host_len: i64 = host_end - authority
    if host_len < 1 or host_len > 253: return -22
    if not http_host_valid(p + authority, host_len): return -22
    i = 0
    while i < host_len:
        let c: i64 = p[authority + i] as i64
        if c >= 65 and c <= 90: c += 32
        host[i] = c as char
        i += 1
    host[host_len] = 0 as char
    if colon >= 0:
        let value: i64 = 0
        let j: i64 = colon + 1
        while j < end:
            let digit: i64 = p[j] as i64 - 48
            if digit < 0 or digit > 9: return -22
            value = value * 10 + digit
            if value > 65535: return -22
            j += 1
        if value < 1: return -22
        port = value
    port_out[0] = port
    let frag: i64 = browser_fetch_fragment(url)
    if frag < end: frag = n
    let path_len: i64 = frag - end
    if path_len == 0:
        path[0] = '/'
        path[1] = 0 as char
        return 0
    if path_len >= BROWSER_FETCH_URL_BYTES: return -90
    i = 0
    while i < path_len:
        let c: i64 = p[end + i] as i64
        if c <= 32 or c >= 127 or c == 92: return -22
        path[i] = p[end + i]
        i += 1
    path[path_len] = 0 as char
    return 0

# Resolve a script-supplied URL against the document URL and strip the fragment.
unsafe fn browser_fetch_resolve(base: string, input: string, out: ptr<char>, capacity: i64) -> i64:
    let p: ptr<char> = input as ptr<char>
    let n: i64 = __volt_strlen(input)
    if n == 0 or n > BROWSER_FETCH_URL_BYTES - 1: return -22
    let base_ptr: ptr<char> = base as ptr<char>
    let bn: i64 = __volt_strlen(base)
    let scheme: i64 = browser_fetch_web_prefix(base_ptr, bn)
    if scheme == 0: return -22
    let frag: i64 = browser_fetch_fragment(input)
    if browser_fetch_web_prefix(p, n) > 0:
        return browser_fetch_copy_into(out, 0, p, frag, capacity)
    if n >= 2 and p[0] == '/' and p[1] == '/':
        let used: i64 = 0
        if scheme == 7: used = browser_fetch_copy_into(out, 0, "http:" as ptr<char>, 5, capacity)
        else: used = browser_fetch_copy_into(out, 0, "https:" as ptr<char>, 6, capacity)
        if used < 0: return used
        return browser_fetch_copy_into(out, used, p, frag, capacity)
    let authority_end: i64 = browser_fetch_authority_end(base_ptr, bn, scheme)
    if p[0] == '/':
        let used: i64 = browser_fetch_copy_into(out, 0, base_ptr, authority_end, capacity)
        if used < 0: return used
        return browser_fetch_copy_into(out, used, p, frag, capacity)
    if p[0] == '?':
        let path_end: i64 = browser_fetch_query_end(base_ptr, bn, scheme)
        let used: i64 = browser_fetch_copy_into(out, 0, base_ptr, path_end, capacity)
        if used < 0: return used
        return browser_fetch_copy_into(out, used, p, frag, capacity)
    if p[0] == '#':
        return browser_fetch_copy_into(out, 0, base_ptr, browser_fetch_fragment(base), capacity)
    let used: i64 = browser_fetch_copy_into(out, 0, base_ptr, authority_end, capacity)
    if used < 0: return used
    let directory_end: i64 = browser_fetch_directory_end(base_ptr, authority_end, bn)
    let used_path: i64 = 0
    if directory_end == authority_end:
        used_path = browser_fetch_copy_into(out, used, "/" as ptr<char>, 1, capacity)
    else:
        used_path = browser_fetch_copy_into(out, used, base_ptr + authority_end, directory_end - authority_end, capacity)
    if used_path < 0: return used_path
    return browser_fetch_copy_into(out, used_path, p, frag, capacity)

unsafe fn browser_fetch_same_origin(a: string, b: string) -> bool:
    if browser_fetch_web_prefix(a as ptr<char>, __volt_strlen(a)) != browser_fetch_web_prefix(b as ptr<char>, __volt_strlen(b)): return false
    let ha: [254]char
    let hb: [254]char
    let pa: [8193]char
    let pb: [8193]char
    let porta: [1]i64
    let portb: [1]i64
    if browser_fetch_parse(a, &ha[0], &pa[0], &porta[0]) < 0: return false
    if browser_fetch_parse(b, &hb[0], &pb[0], &portb[0]) < 0: return false
    if porta[0] != portb[0]: return false
    let length: i64 = __volt_strlen((&ha[0]) as string)
    if length != __volt_strlen((&hb[0]) as string): return false
    return browser_fetch_equal(&ha[0], &hb[0], length)

unsafe fn browser_fetch_is_redirect(status: i64) -> bool:
    return status == 301 or status == 302 or status == 303 or status == 307 or status == 308

unsafe fn browser_fetch_dechunk(out: ptr<ByteBuffer>, start: i64, limit: i64) -> i64:
    let p: ptr<char> = out.data as ptr<char>
    let position: i64 = start
    let output: i64 = 0
    while position < out.len:
        let size: i64 = 0
        let digits: i64 = 0
        while position < out.len and p[position] != '\r':
            let c: i64 = p[position] as i64
            let digit: i64 = 0
            if c >= 48 and c <= 57: digit = c - 48
            elif c >= 65 and c <= 70: digit = c - 55
            elif c >= 97 and c <= 102: digit = c - 87
            else: return -22
            if digits >= 16 or size > (limit - digit) / 16: return -90
            size = size * 16 + digit
            digits += 1
            position += 1
        if digits == 0 or position + 1 >= out.len or p[position] != '\r' or p[position + 1] != '\n': return -22
        position += 2
        if size == 0:
            if position + 2 > out.len or p[position] != '\r' or p[position + 1] != '\n': return -22
            out.len = output
            return 0
        if size > limit - output or size > out.len - position - 2: return -22
        if p[position + size] != '\r' or p[position + size + 1] != '\n': return -22
        let i: i64 = 0
        while i < size:
            p[output + i] = p[position + i]
            i += 1
        output += size
        position += size + 2
    return -22

# Parse a complete raw response, move the body to offset 0 and return the status.
unsafe fn browser_fetch_response(out: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>, status_out: ptr<i64>, location: ptr<char>, content_type: ptr<char>) -> i64:
    let p: ptr<char> = out.data as ptr<char>
    let n: i64 = out.len
    if n < 12: return -22
    if not (p[0] == 'H' and p[1] == 'T' and p[2] == 'T' and p[3] == 'P' and p[4] == '/' and p[5] == '1' and (p[6] == '.' and (p[7] == '0' or p[7] == '1'))): return -22
    if p[8] != ' ': return -22
    if p[9] < '0' or p[9] > '9' or p[10] < '0' or p[10] > '9' or p[11] < '0' or p[11] > '9': return -22
    let status: i64 = ((p[9] as i64 - 48) * 100) + ((p[10] as i64 - 48) * 10) + (p[11] as i64 - 48)
    if status < 200 or status > 599: return -22
    status_out[0] = status
    location[0] = 0 as char
    content_type[0] = 0 as char
    let header_limit: i64 = min(n, HTTP_HEADER_LIMIT)
    let headers_end: i64 = -1
    let pos: i64 = 12
    while pos + 3 < header_limit:
        if p[pos] == '\r' and p[pos + 1] == '\n' and p[pos + 2] == '\r' and p[pos + 3] == '\n':
            headers_end = pos + 4
            break
        pos += 1
    if headers_end < 0: return -22
    let line_end: i64 = 12
    while line_end + 1 < header_limit and not (p[line_end] == '\r' and p[line_end + 1] == '\n'): line_end += 1
    if line_end + 1 >= header_limit: return -22
    let content_length: i64 = -1
    let chunked: bool = false
    let at: i64 = line_end + 2
    while at + 1 < headers_end - 2:
        let end: i64 = at
        while end + 1 < headers_end and not (p[end] == '\r' and p[end + 1] == '\n'): end += 1
        if end <= at: break
        let colon: i64 = at
        while colon < end and p[colon] != ':': colon += 1
        if colon == at or colon >= end: return -22
        let value: i64 = colon + 1
        while value < end and (p[value] == ' ' or p[value] == '\t'): value += 1
        let stop: i64 = end
        while stop > value and (p[stop - 1] == ' ' or p[stop - 1] == '\t'): stop -= 1
        if http_frame_equal(p, at, colon, "content-type"):
            if stop - value >= BROWSER_FETCH_TYPE_BYTES: return -90
            let i: i64 = 0
            while value + i < stop:
                content_type[i] = p[value + i]
                i += 1
            content_type[stop - value] = 0 as char
        elif http_frame_equal(p, at, colon, "content-length"):
            if content_length >= 0: return -22
            let size: i64 = 0
            let i: i64 = value
            while i < stop:
                let digit: i64 = p[i] as i64 - 48
                if digit < 0 or digit > 9: return -22
                if size > (BROWSER_FETCH_BODY_BYTES - digit) / 10: return -90
                size = size * 10 + digit
                i += 1
            content_length = size
        elif http_frame_equal(p, at, colon, "transfer-encoding"):
            if not http_frame_equal(p, value, stop, "chunked"): return -22
            chunked = true
        elif http_frame_equal(p, at, colon, "content-encoding"):
            if not http_frame_equal(p, value, stop, "identity"): return -1005
        elif http_frame_equal(p, at, colon, "location"):
            if stop - value >= BROWSER_FETCH_URL_BYTES: return -90
            let i: i64 = 0
            while value + i < stop:
                location[i] = p[value + i]
                i += 1
            location[stop - value] = 0 as char
        at = end + 2
    if status == 204 or status == 304:
        out.len = 0
        return 0
    if chunked:
        let status2: i64 = browser_fetch_dechunk(out, headers_end, BROWSER_FETCH_BODY_BYTES)
        if status2 < 0: return status2
        return 0
    let body: i64 = n - headers_end
    if body < 0 or body > BROWSER_FETCH_BODY_BYTES: return -90
    if content_length >= 0 and content_length != body: return -22
    if content_length < 0 and not transfer.clean_eof: return -22
    let i: i64 = 0
    while i < body:
        p[i] = p[headers_end + i]
        i += 1
    out.len = body
    return 0

# Returns the HTTP status on success or a negative errno. The body is left in
# `out` at offset 0. Redirects stay on the document origin.
unsafe fn browser_fetch_perform(base: string, method: string, input: string, body: ptr<u8>, body_len: i64, request_type: string, out: ptr<ByteBuffer>, content_type: ptr<char>, final_url: ptr<char>, transfer: ptr<HttpTransfer>) -> i64:
    let get: bool = method == "GET"
    let post: bool = method == "POST"
    if not get and not post: return -22
    if body_len < 0 or body_len > BROWSER_FETCH_BODY_BYTES: return -22
    if post and body_len > 0 and body == (0 as ptr<u8>): return -22
    let current: [8193]char
    if browser_fetch_resolve(base, input, &current[0], BROWSER_FETCH_URL_BYTES) <= 0: return -22
    if not browser_fetch_same_origin(base, (&current[0]) as string): return -13
    out.len = 0
    content_type[0] = 0 as char
    let current_method: string = method
    let current_body: ptr<u8> = body
    let current_len: i64 = body_len
    let hop: i64 = 0
    while true:
        let host: [254]char
        let path: [8193]char
        let port: [1]i64
        if browser_fetch_parse((&current[0]) as string, &host[0], &path[0], &port[0]) < 0: return -22
        let address: [4]u8
        let ip: ptr<u8> = &address[0]
        if http_parse_ipv4((&host[0]) as string, ip) < 0:
            let remaining: i64 = http_transfer_remaining(transfer)
            if remaining < 0: return remaining
            let resolved: i64 = dns_resolve_ipv4((&host[0]) as string, ip)
            if resolved < 0: return resolved
        transfer.body_bytes = BROWSER_FETCH_BODY_BYTES
        transfer.response_bytes = BROWSER_FETCH_BODY_BYTES + HTTP_HEADER_LIMIT
        transfer.accept_gzip = false
        let secure: bool = browser_fetch_web_prefix((&current[0]) as ptr<char>, __volt_strlen((&current[0]) as string)) == 8
        let fetched: i64
        if secure:
            fetched = tls_http_request_general((&host[0]) as string, port[0], (&path[0]) as string, current_method, request_type, current_body, current_len, ip, out, transfer)
        else:
            fetched = http_request_transfer((&host[0]) as string, port[0], (&path[0]) as string, current_method, request_type, current_body, current_len, ip, out, transfer)
        if fetched < 0: return fetched
        let status: [1]i64
        let location: [8193]char
        let parsed: i64 = browser_fetch_response(out, transfer, &status[0], &location[0], content_type)
        if parsed < 0: return parsed
        if browser_fetch_is_redirect(status[0]):
            if hop >= BROWSER_FETCH_REDIRECTS: return -1004
            let next: [8193]char
            if browser_fetch_resolve((&current[0]) as string, (&location[0]) as string, &next[0], BROWSER_FETCH_URL_BYTES) <= 0: return -22
            if not browser_fetch_same_origin(base, (&next[0]) as string): return -13
            browser_fetch_copy_into(&current[0], 0, &next[0], __volt_strlen((&next[0]) as string), BROWSER_FETCH_URL_BYTES)
            if status[0] == 303 or ((status[0] == 301 or status[0] == 302) and current_method == "POST"):
                current_method = "GET"
                current_body = 0 as ptr<u8>
                current_len = 0
            hop += 1
            continue
        if final_url != (0 as ptr<char>): browser_fetch_copy_into(final_url, 0, &current[0], __volt_strlen((&current[0]) as string), BROWSER_FETCH_URL_BYTES)
        return status[0]
    return -5
