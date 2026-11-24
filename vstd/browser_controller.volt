# Shared production operations for the VOLT-owned native browser.
use browser_engine
use bytes
use paint
use sdl
use http
use dns
use html
use css
use process
use tls
use browser_document
use browser_policy
use browser_gzip
use browser_youtube_transport
const BROWSER_CONTROLLER_WIDTH: i64 = BROWSER_ENGINE_VIEW_WIDTH
const BROWSER_CONTROLLER_HEIGHT: i64 = BROWSER_ENGINE_VIEW_HEIGHT
const BROWSER_HTTP_HEADER_LIMIT: i64 = HTTP_HEADER_LIMIT
const BROWSER_HTTP_RESPONSE_LIMIT: i64 = HTML_DOCUMENT_LIMIT + BROWSER_HTTP_HEADER_LIMIT
const BROWSER_HTTP_STATUS_BASE: i64 = 2000
const BROWSER_HTTP_SCRIPT: i64 = 4
const BROWSER_SCRIPT_BODY_LIMIT: i64 = 32768
const BROWSER_SCRIPT_REQUEST_LIMIT: i64 = 24

unsafe fn browser_paint_page(page: ptr<BrowserPage>, pixels: ptr<u32>, scroll_y: i64) -> i64:
    return browser_paint_view(page, pixels, scroll_y, BROWSER_CONTROLLER_HEIGHT)

unsafe fn browser_paint_view(page: ptr<BrowserPage>, pixels: ptr<u32>, scroll_y: i64, height: i64) -> i64:
    if height < 1 or height > BROWSER_CONTROLLER_HEIGHT: return -22
    let surface: PaintSurface = PaintSurface(pixels, BROWSER_CONTROLLER_WIDTH, height, BROWSER_CONTROLLER_WIDTH, BROWSER_CONTROLLER_WIDTH * height)
    return browser_paint_on(page, &surface, scroll_y)

unsafe fn browser_paint_on(page: ptr<BrowserPage>, surface: ptr<PaintSurface>, scroll_y: i64) -> i64:
    if page == (0 as ptr<BrowserPage>) or page.source_buffer == (0 as ptr<ByteBuffer>): return -22
    if page.visual:
        if not paint_surface_valid(surface): return -22
        let image: ptr<char> = cairo_image_surface_create_for_data(surface.pixels as ptr<char>, CAIRO_ARGB32, surface.width as i32, surface.height as i32, (surface.stride * 4) as i32)
        defer cairo_surface_destroy(image)
        if cairo_surface_status(image) != 0: return -12
        let result: i64 = browser_draw_document(image, page, BrowserRect(0, scroll_y, surface.width, surface.height), 1)
        cairo_surface_flush(image)
        return result
    let flow: PaintFlowContext = PaintFlowContext(page.fragments, page.fragment_count, page.flow_text, page.text_length)
    let context: PaintDocumentContext = PaintDocumentContext(page.source, page.nodes, page.styles, page.boxes, page.node_count, &flow, surface)
    return paint_document_fragments_on(&context, scroll_y, BROWSER_CANVAS_COLOR)

unsafe fn browser_request_target_byte_allowed(c: i64) -> bool:
    return c > 32 and c < 127 and c != 35 and c != 92 and c != 34 and c != 60 and c != 62 and c != 123 and c != 125 and c != 124 and c != 94 and c != 96

unsafe fn browser_hex_value(c: i64) -> i64:
    if c >= 48 and c <= 57: return c - 48
    if c >= 65 and c <= 70: return c - 55
    if c >= 97 and c <= 102: return c - 87
    return -1

unsafe fn browser_percent_decode(input: ptr<char>, length: i64, output: ptr<char>, capacity: i64) -> i64:
    let i: i64 = 0
    let written: i64 = 0
    while i < length:
        let byte: i64 = input[i] as i64
        if byte == 37 and length - i >= 3:
            let high: i64 = browser_hex_value(input[i + 1] as i64)
            let low: i64 = browser_hex_value(input[i + 2] as i64)
            if high >= 0 and low >= 0:
                byte = high * 16 + low
                i += 2
        if byte == 0: return -22
        if written >= capacity - 1: return -90
        output[written] = byte as char
        written += 1
        i += 1
    output[written] = 0 as char
    return written

unsafe fn browser_web_prefix(url: string) -> i64:
    let p: ptr<char> = url as ptr<char>
    let n: i64 = __volt_strlen(url)
    if n < 7 or p[0] != 'h' or p[1] != 't' or p[2] != 't' or p[3] != 'p': return 0
    if p[4] == ':' and p[5] == '/' and p[6] == '/': return 7
    if n >= 8 and p[4] == 's' and p[5] == ':' and p[6] == '/' and p[7] == '/': return 8
    return 0

unsafe fn browser_parse_url(url: string, host: ptr<char>, target: ptr<char>, port_out: ptr<i64>) -> i64:
    let p: ptr<char> = url as ptr<char>
    if __volt_strlen(url) > BROWSER_ADDRESS_LIMIT: return -22
    let n: i64 = browser_fragment_start(url)
    if n < 8: return -22
    let prefix_length: i64 = browser_web_prefix(url)
    if prefix_length == 0: return -22
    let i: i64 = 0
    let authority_start: i64 = prefix_length
    let authority_end: i64 = authority_start
    while authority_end < n and p[authority_end] != '/' and p[authority_end] != '?':
        if p[authority_end] == '#' or p[authority_end] == '@' or p[authority_end] == 92: return -22
        if p[authority_end] <= 32 or p[authority_end] >= 127: return -22
        authority_end += 1
    if authority_end == authority_start: return -22
    let colon: i64 = -1
    i = authority_start
    while i < authority_end:
        if p[i] == ':':
            if colon >= 0: return -22
            colon = i
        i += 1
    let host_end: i64 = authority_end
    let port: i64 = 80
    if prefix_length == 8: port = 443
    if colon >= 0:
        host_end = colon
        if colon + 1 >= authority_end: return -22
        port = 0
        i = colon + 1
        while i < authority_end:
            let digit: i64 = p[i] as i64 - 48
            if digit < 0 or digit > 9: return -22
            if port > (65535 - digit) / 10: return -22
            port = port * 10 + digit
            i += 1
        if port < 1: return -22
    let host_len: i64 = host_end - authority_start
    if not http_host_valid(p + authority_start, host_len): return -22
    let numeric: bool = true
    i = 0
    while i < host_len:
        let c: i64 = p[authority_start + i] as i64
        if (c < 48 or c > 57) and c != 46: numeric = false
        i += 1
    if numeric:
        let part_count: i64 = 0
        let value: i64 = 0
        let digits: i64 = 0
        let octet_start: i64 = authority_start
        i = authority_start
        while i <= host_end:
            if i == host_end or p[i] == '.':
                if digits == 0 or part_count >= 4: return -22
                if digits > 1 and p[octet_start] == '0': return -22
                part_count += 1
                value = 0
                digits = 0
                octet_start = i + 1
            else:
                let digit: i64 = p[i] as i64 - 48
                if digit < 0 or digit > 9 or digits >= 3: return -22
                value = value * 10 + digit
                if value > 255: return -22
                digits += 1
            i += 1
        if part_count != 4: return -22
    i = 0
    while i < host_len:
        host[i] = p[authority_start + i]
        i += 1
    host[host_len] = 0 as char
    let out: i64 = 0
    if authority_end == n or p[authority_end] == '?':
        target[out] = '/' as char
        out += 1
    i = authority_end
    if authority_end < n and p[authority_end] == '?':
        target[out] = '?'
        out += 1
        i += 1
    while i < n:
        if not browser_request_target_byte_allowed(p[i] as i64): return -22
        if p[i] == '%':
            if i + 2 >= n or browser_hex_value(p[i + 1] as i64) < 0 or browser_hex_value(p[i + 2] as i64) < 0: return -22
            if out > 8177: return -90
            target[out] = '%'
            target[out + 1] = p[i + 1]
            target[out + 2] = p[i + 2]
            out += 3
            i += 3
        else:
            if out >= 8192: return -90
            target[out] = p[i]
            out += 1
            i += 1
    target[out] = 0 as char
    port_out[0] = port
    return 0

unsafe fn browser_http_token_byte(c: i64) -> bool:
    return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 33 or c == 35 or c == 36 or c == 37 or c == 38 or c == 39 or c == 42 or c == 43 or c == 45 or c == 46 or c == 94 or c == 95 or c == 96 or c == 124 or c == 126

unsafe fn browser_http_is_type(p: ptr<char>, start: i64, end: i64, expected: string, utf8_only: bool) -> bool:
    let i: i64 = start
    while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
    let length: i64 = __volt_strlen(expected)
    if end - i < length or not http_frame_equal(p, i, i + length, expected): return false
    i += length
    while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
    if i == end: return true
    if p[i] != ';': return false
    i += 1
    let checked: i64 = 0
    let charset_seen: bool = false
    while i < end:
        if p[i] == ' ' or p[i] == '\t':
            i += 1
        else:
            let name: i64 = i
            while i < end and browser_http_token_byte(p[i] as i64): i += 1
            if i == name: return false
            let charset: bool = utf8_only and http_frame_equal(p, name, i, "charset")
            while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
            if i >= end or p[i] != '=': return false
            i += 1
            while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
            if i >= end: return false
            let quoted: bool = p[i] == '"'
            if quoted: i += 1
            let value: i64 = i
            if quoted:
                while i < end and p[i] != '"':
                    let c: i64 = p[i] as i64
                    if c < 32 or c == 127: return false
                    i += 1
                if i == end: return false
            else:
                while i < end and browser_http_token_byte(p[i] as i64): i += 1
                if i == value: return false
            if charset:
                if charset_seen or not http_frame_equal(p, value, i, "utf-8"): return false
                charset_seen = true
            if quoted: i += 1
            checked += 1
            if utf8_only:
                while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
                if i < end and (p[i] != ';' or i + 1 == end): return false
            elif i < end and p[i] != ';' and p[i] != ' ' and p[i] != '\t': return false
            if i < end and p[i] == ';': i += 1
    return checked > 0

unsafe fn browser_http_is_chunked(p: ptr<char>, start: i64, end: i64) -> bool:
    let i: i64 = start
    while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
    let expected: string = "chunked"
    let j: i64 = 0
    while j < 7 and i + j < end:
        let actual: i64 = p[i + j] as i64
        if actual >= 65 and actual <= 90: actual += 32
        if actual != (expected as ptr<char>)[j] as i64: return false
        j += 1
    i += 7
    while i < end and (p[i] == ' ' or p[i] == '\t'): i += 1
    return j == 7 and i == end

unsafe fn browser_http_decode_chunks(response: ptr<ByteBuffer>, p: ptr<char>, start: i64, n: i64, limit: i64) -> i64:
    if start < 0 or n < 0 or start > response.len or n > response.len - start: return -22
    let position: i64 = start
    let output: i64 = 0
    let done: bool = false
    while not done:
        if position >= response.len: return -22
        let size: i64 = 0
        let digits: i64 = 0
        while position < response.len and p[position] != '\r':
            let c: i64 = p[position] as i64
            let digit: i64 = browser_hex_value(c)
            if digit < 0 or digits >= 16: return -22
            if size > (limit - digit) / 16: return -90
            size = size * 16 + digit
            digits += 1
            position += 1
        if digits == 0 or position + 1 >= response.len or p[position] != '\r' or p[position + 1] != '\n': return -22
        position += 2
        if size > limit - output: return -90
        if size == 0:
            if position + 2 != response.len or p[position] != '\r' or p[position + 1] != '\n': return -22
            position += 2
            done = true
        else:
            if size > response.len - position - 2: return -22
            if p[position + size] != '\r' or p[position + size + 1] != '\n': return -22
            let i: i64 = 0
            while i < size:
                p[output + i] = p[position + i]
                i += 1
            output += size
            position += size + 2
    response.len = output
    response.data[output] = 0 as u8
    return 0

struct BrowserHttpMedia:
    kind: i64                # 1 stylesheet, 2 raster image, 3 direct video, 4 classic script
    mime: string

unsafe fn browser_http_media(p: ptr<char>, start: i64, end: i64, kind: i64) -> string:
    if kind == BROWSER_HTTP_SCRIPT:
        if browser_http_is_type(p, start, end, "text/javascript", true): return "text/javascript"
        if browser_http_is_type(p, start, end, "application/javascript", true): return "application/javascript"
        return ""
    let stop: i64 = start
    while stop < end and p[stop] != ';': stop += 1
    stop = css_trim_end(p, start, stop)
    if kind == 1:
        if http_frame_equal(p, start, stop, "text/css"): return "text/css"
    elif kind == 2:
        if http_frame_equal(p, start, stop, "image/png"): return "image/png"
        if http_frame_equal(p, start, stop, "image/jpeg"): return "image/jpeg"
        if http_frame_equal(p, start, stop, "image/webp"): return "image/webp"
    elif kind == 3:
        if http_frame_equal(p, start, stop, "video/webm"): return "video/webm"
        if http_frame_equal(p, start, stop, "video/mp4"): return "video/mp4"
        if http_frame_equal(p, start, stop, "video/ogg"): return "video/ogg"
    return ""

unsafe fn browser_http_response(response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>, status_out: ptr<i64>, location: ptr<char>, csp: ptr<BrowserPolicy>, media: ptr<BrowserHttpMedia>) -> i64:
    let p: ptr<char> = response.data as ptr<char>
    let n: i64 = response.len
    if n < 12 or n > transfer.response_bytes: return -22
    let limit: i64 = transfer.body_bytes
    let header_limit: i64 = min(n, BROWSER_HTTP_HEADER_LIMIT)
    let line_end: i64 = 0
    while line_end + 1 < header_limit and not (p[line_end] == '\r' and p[line_end + 1] == '\n'): line_end += 1
    if line_end + 1 >= header_limit or line_end < 12: return -22
    let http10: bool = p[0] == 'H' and p[1] == 'T' and p[2] == 'T' and p[3] == 'P' and p[4] == '/' and p[5] == '1' and p[6] == '.' and p[7] == '0'
    let http11: bool = p[0] == 'H' and p[1] == 'T' and p[2] == 'T' and p[3] == 'P' and p[4] == '/' and p[5] == '1' and p[6] == '.' and p[7] == '1'
    if not http10 and not http11: return -22
    if p[8] != ' ': return -22
    if p[9] < '0' or p[9] > '9' or p[10] < '0' or p[10] > '9' or p[11] < '0' or p[11] > '9': return -22
    if line_end == 12 or p[12] != ' ': return -22
    let phrase: i64 = 13
    while phrase < line_end:
        let c: i64 = p[phrase] as i64
        if c < 32 or c == 127: return -22
        phrase += 1
    status_out[0] = ((p[9] as i64 - 48) * 100) + ((p[10] as i64 - 48) * 10) + (p[11] as i64 - 48)
    if status_out[0] < 200 or status_out[0] > 599: return -22
    location[0] = 0 as char
    let headers_end: i64 = -1
    let content_length: i64 = -1
    let transfer_chunked: bool = false
    let content_type_html: bool = false
    let content_type_seen: bool = false
    let content_encoding_seen: bool = false
    let content_encoding_identity: bool = true
    let gzip: bool = false
    let location_seen: bool = false
    let pos: i64 = line_end + 2
    while pos < header_limit:
        let start: i64 = pos
        let end: i64 = start
        while end + 1 < header_limit and not (p[end] == '\r' and p[end + 1] == '\n'): end += 1
        if end + 1 >= header_limit or end - start > 8192 or end == start:
            if end + 1 < header_limit and end == start:
                headers_end = end + 2
                pos = end + 2
                break
            return -22
        let colon: i64 = start
        while colon < end and p[colon] != ':':
            let c: i64 = p[colon] as i64
            if not browser_http_token_byte(c): return -22
            colon += 1
        if colon == start or colon >= end: return -22
        let value_start: i64 = colon + 1
        while value_start < end and (p[value_start] == ' ' or p[value_start] == '\t'): value_start += 1
        let value_end: i64 = end
        while value_end > value_start and (p[value_end - 1] == ' ' or p[value_end - 1] == '\t'): value_end -= 1
        let name_length: i64 = colon - start
        let is_content_length: bool = name_length == 14
        let is_content_type: bool = name_length == 12
        let is_transfer_encoding: bool = name_length == 17
        let is_location: bool = name_length == 8
        let is_content_encoding: bool = name_length == 16
        let i: i64 = 0
        let name_cl: string = "content-length"
        let name_ct: string = "content-type"
        let name_te: string = "transfer-encoding"
        let name_loc: string = "location"
        let name_ce: string = "content-encoding"
        while i < name_length:
            let c: i64 = p[start + i] as i64
            if c >= 65 and c <= 90: c += 32
            if is_content_length and c != (name_cl as ptr<char>)[i] as i64: is_content_length = false
            if is_content_type and c != (name_ct as ptr<char>)[i] as i64: is_content_type = false
            if is_transfer_encoding and c != (name_te as ptr<char>)[i] as i64: is_transfer_encoding = false
            if is_location and c != (name_loc as ptr<char>)[i] as i64: is_location = false
            if is_content_encoding and c != (name_ce as ptr<char>)[i] as i64: is_content_encoding = false
            i += 1
        if is_content_length:
            if content_length >= 0: return -22
            if value_start == value_end: return -22
            let value: i64 = 0
            while value_start < value_end:
                let digit: i64 = p[value_start] as i64 - 48
                if digit < 0 or digit > 9: return -22
                if status_out[0] != 304:
                    if value > (limit - digit) / 10: return -90
                    value = value * 10 + digit
                value_start += 1
            content_length = value
        elif is_transfer_encoding:
            if transfer_chunked or not browser_http_is_chunked(p, value_start, end): return -22
            transfer_chunked = true
        elif is_content_type:
            if content_type_seen: return -22
            content_type_seen = true
            if status_out[0] == 200:
                if media == (0 as ptr<BrowserHttpMedia>): content_type_html = browser_http_is_type(p, value_start, end, "text/html", false)
                else:
                    media.mime = browser_http_media(p, value_start, value_end, media.kind)
                    content_type_html = media.mime != ""
        elif is_content_encoding:
            if content_encoding_seen or value_start == value_end: return -22
            content_encoding_seen = true
            content_encoding_identity = http_frame_equal(p, value_start, value_end, "identity")
            gzip = transfer.accept_gzip and http_frame_equal(p, value_start, value_end, "gzip")
        elif is_location:
            if location_seen: return -22
            location_seen = true
            let location_start: i64 = value_start
            let location_end: i64 = end
            while location_end > location_start and (p[location_end - 1] == ' ' or p[location_end - 1] == '\t'): location_end -= 1
            if location_end == location_start or location_end - location_start > 8192: return -22
            i = location_start
            while i < location_end:
                if p[i] <= 32 or p[i] >= 127: return -22
                location[i - location_start] = p[i]
                i += 1
            location[location_end - location_start] = 0 as char
        else:
            let i: i64 = value_start
            while i < end:
                let c: i64 = p[i] as i64
                if c < 32 and c != 9: return -22
                if c == 127: return -22
                i += 1
            if http_frame_equal(p, start, colon, "content-security-policy"): browser_policy_read(csp, p, value_start, value_end)
        pos = end + 2
    if headers_end < 0: return -22
    if browser_http_redirect(status_out[0]) and not location_seen: return -22
    if status_out[0] == 200 and not content_type_html: return -22
    if status_out[0] == 200 and not content_encoding_identity and not gzip: return -1005
    if status_out[0] == 200 and content_length == 0 and not transfer_chunked: return -22
    if transfer_chunked and content_length >= 0: return -22
    if status_out[0] == 204 or status_out[0] == 304:
        if transfer_chunked or n != headers_end or (status_out[0] == 204 and content_length >= 0): return -22
        return headers_end
    if transfer_chunked:
        let body_length: i64 = n - headers_end
        if body_length <= 0: return -22
        let decoded: i64 = browser_http_decode_chunks(response, p, headers_end, body_length, limit)
        if decoded < 0: return decoded
        if status_out[0] == 200 and response.len == 0: return -22
        headers_end = 0
    else:
        if content_length >= 0 and content_length != n - headers_end: return -22
        if content_length < 0 and not transfer.clean_eof: return -22
        if status_out[0] == 200 and headers_end == n: return -22
        if n - headers_end > limit: return -90
    if status_out[0] != 200: return headers_end
    if gzip: return browser_gzip_expand(response, headers_end, transfer)
    return headers_end

fn browser_http_redirect(status: i64) -> bool:
    return status == 301 or status == 302 or status == 303 or status == 307 or status == 308

fn browser_is_http_status(status: i64) -> bool:
    return status <= -BROWSER_HTTP_STATUS_BASE - 200 and status >= -BROWSER_HTTP_STATUS_BASE - 599

unsafe fn browser_http_status_digits(status: i64, out: ptr<char>):
    let code: i64 = -status - BROWSER_HTTP_STATUS_BASE
    out[0] = '0' + (code / 100) as char
    out[1] = '0' + ((code / 10) % 10) as char
    out[2] = '0' + (code % 10) as char

unsafe fn browser_resolve_location(current_url: string, location: string, output: ptr<char>) -> i64:
    let loc: ptr<char> = location as ptr<char>
    let length: i64 = __volt_strlen(location)
    if length == 0 or length > BROWSER_ADDRESS_LIMIT: return -22
    if browser_web_prefix(location) > 0:
        if browser_copy_address(output, location) < 0: return -90
        return 0
    let ln: i64 = browser_fragment_start(location)
    if ln == 0 or loc[0] == '?' or (ln >= 2 and loc[0] == '/' and loc[1] == '/'): return -22
    let host: [254]char
    let target: [8193]char
    let port: [1]i64
    if browser_parse_url(current_url, &host[0], &target[0], &port[0]) < 0: return -22
    let current: ptr<char> = current_url as ptr<char>
    let prefix: i64 = browser_web_prefix(current_url)
    while current[prefix] != 0 and current[prefix] != '/' and current[prefix] != '?' and current[prefix] != '#': prefix += 1
    let i: i64 = 0
    while i < prefix:
        output[i] = current[i]
        i += 1
    let joined: [8193]char
    let j: i64 = 0
    if loc[0] == '/':
        if ln > 8192: return -90
        while j < ln:
            joined[j] = loc[j]
            j += 1
    else:
        let dir_end: i64 = 0
        while target[dir_end] != 0 and target[dir_end] != '?': dir_end += 1
        while dir_end > 0 and target[dir_end - 1] != '/': dir_end -= 1
        if dir_end > 8192 or ln > 8192 - dir_end: return -90
        while j < dir_end:
            joined[j] = target[j]
            j += 1
        let k: i64 = 0
        while k < ln:
            joined[j] = loc[k]
            j += 1
            k += 1
    joined[j] = 0 as char
    let path_end: i64 = 0
    while path_end < j and joined[path_end] != '?': path_end += 1
    let normalized: [8193]char
    let segment_starts: [4096]i64
    let segments: i64 = 0
    let outpos: i64 = 0
    normalized[outpos] = '/' as char
    outpos += 1
    let pos: i64 = 1
    while pos <= path_end:
        let end: i64 = pos
        while end < path_end and joined[end] != '/': end += 1
        let len: i64 = end - pos
        if len == 2 and joined[pos] == '.' and joined[pos + 1] == '.':
            if segments > 0:
                outpos = segment_starts[segments - 1]
                segments -= 1
        elif not (len == 1 and joined[pos] == '.') and len > 0:
            if segments >= 4096: return -90
            segment_starts[segments] = outpos
            segments += 1
            let k: i64 = 0
            while k < len:
                if not browser_request_target_byte_allowed(joined[pos + k] as i64): return -22
                if joined[pos + k] == '%':
                    if k + 2 >= len or browser_hex_value(joined[pos + k + 1] as i64) < 0 or browser_hex_value(joined[pos + k + 2] as i64) < 0: return -22
                    if outpos > 8189: return -90
                    normalized[outpos] = '%'
                    normalized[outpos + 1] = joined[pos + k + 1]
                    normalized[outpos + 2] = joined[pos + k + 2]
                    outpos += 3
                    k += 3
                else:
                    if outpos >= 8192: return -90
                    normalized[outpos] = joined[pos + k]
                    outpos += 1
                    k += 1
            if end < path_end:
                if outpos >= 8192: return -90
                normalized[outpos] = '/' as char
                outpos += 1
        pos = end + 1
    if path_end < j:
        let k: i64 = path_end
        while k < j:
            if not browser_request_target_byte_allowed(joined[k] as i64): return -22
            if outpos >= 8192: return -90
            normalized[outpos] = joined[k]
            outpos += 1
            k += 1
    if prefix + outpos + length - ln > BROWSER_ADDRESS_LIMIT: return -90
    let copy_index: i64 = 0
    while copy_index < outpos:
        output[prefix + copy_index] = normalized[copy_index]
        copy_index += 1
    browser_copy_address(output + prefix + outpos, (loc + ln) as string)
    return 0

unsafe fn browser_resolve_local_href(page: ptr<BrowserPage>, href: string, output: ptr<char>, resource_length: ptr<i64>) -> i64:
    let reference: ptr<char> = href as ptr<char>
    let path_end: i64 = browser_fragment_start(href)
    let prefix: i64 = 0
    if reference[0] != '/':
        let base: ptr<char> = page.url as ptr<char>
        let directory_end: i64 = page.resource_length
        while directory_end > 0 and base[directory_end - 1] != '/': directory_end -= 1
        # Preserve a local relative path even if a decoded byte is a colon.
        if directory_end == 0:
            output[0] = '.'
            output[1] = '/'
            prefix = 2
        else:
            while prefix < directory_end:
                output[prefix] = base[prefix]
                prefix += 1
    let decoded: i64 = browser_percent_decode(reference, path_end, output + prefix, BROWSER_ADDRESS_LIMIT + 1 - prefix)
    if decoded < 0: return decoded
    let boundary: i64 = prefix + decoded
    let suffix: string = (reference + path_end) as string
    if __volt_strlen(suffix) > BROWSER_ADDRESS_LIMIT - boundary: return -90
    resource_length[0] = boundary
    return boundary + browser_copy_address(output + boundary, suffix)

unsafe fn browser_resolve_href(page: ptr<BrowserPage>, href: string, output: ptr<char>, resource_length: ptr<i64>) -> i64:
    let base: string = page.url
    let reference: ptr<char> = href as ptr<char>
    let length: i64 = __volt_strlen(href)
    if length == 0 or length > BROWSER_ADDRESS_LIMIT: return -22
    resource_length[0] = -1
    if browser_web_prefix(href) > 0: return browser_copy_address(output, href)
    let i: i64 = 0
    while i < length and reference[i] != '/' and reference[i] != '?' and reference[i] != '#':
        if reference[i] == ':': return -22
        i += 1
    let scheme: i64 = browser_web_prefix(base)
    let current: ptr<char> = base as ptr<char>
    let prefix: i64 = 0
    if reference[0] == '#':
        prefix = page.resource_length
        resource_length[0] = prefix
    elif scheme > 0:
        if length >= 2 and reference[0] == '/' and reference[1] == '/':
            prefix = scheme - 2
        elif reference[0] == '?':
            prefix = scheme
            while prefix < page.resource_length and current[prefix] != '?': prefix += 1
        else:
            let result: i64 = browser_resolve_location(base, href, output)
            if result < 0: return result
            return __volt_strlen(output as string)
    else:
        if reference[0] == '?' or (length >= 2 and reference[0] == '/' and reference[1] == '/'): return -22
        return browser_resolve_local_href(page, href, output, resource_length)
    if prefix > BROWSER_ADDRESS_LIMIT - length: return -90
    i = 0
    while i < prefix:
        output[i] = current[i]
        i += 1
    return prefix + browser_copy_address(output + prefix, href)

unsafe fn browser_same_origin(first: string, second: string) -> bool:
    let scheme: i64 = browser_web_prefix(first)
    if scheme == 0 or scheme != browser_web_prefix(second): return false
    let a: [254]char
    let b: [254]char
    let target: [8193]char
    let port_a: i64 = 0
    let port_b: i64 = 0
    if browser_parse_url(first, &a[0], &target[0], &port_a) < 0 or browser_parse_url(second, &b[0], &target[0], &port_b) < 0: return false
    let length: i64 = __volt_strlen((&a[0]) as string)
    return port_a == port_b and http_frame_equal(&a[0], 0, length, (&b[0]) as string)

unsafe native fn browser_open_asset(directory: i64, name: ptr<char>, how: ptr<i64>) -> i64:
{
    mov r10d, 24
    mov eax, 437              # openat2
    syscall
}

unsafe fn browser_local_asset(page: ptr<BrowserPage>, path: string) -> i64:
    let directory: [8193]char
    let base: ptr<char> = page.url as ptr<char>
    let length: i64 = page.resource_length
    while length > 0 and base[length - 1] != '/': length -= 1
    let i: i64 = 0
    while i < length:
        directory[i] = base[i]
        i += 1
    if length == 0: directory[0] = '.'
    let fd: i64 = open((&directory[0]) as string, 0x290000, 0)  # O_PATH | O_DIRECTORY | O_CLOEXEC
    if fd < 0: return fd
    defer close(fd)
    let how: [3]i64 = [0x280000, 0, 0x0f]  # O_PATH, beneath, no symlinks or mount crossings
    let asset: i64 = browser_open_asset(fd, path as ptr<char>, &how[0])
    if asset < 0: return asset
    defer close(asset)
    let metadata: [32]u64
    if __volt_fs_statx(asset, "" as ptr<char>, 0x1000, 1, &metadata[0]) != 0 or (metadata[0] & 1) == 0 or ((metadata[3] >> 32) & 0xf000) != 0x8000: return -22
    # Open the verified inode through its live descriptor so the pathname cannot race statx.
    let proc: [34]char
    let prefix: ptr<char> = "/proc/self/fd/" as ptr<char>
    i = 0
    while i < 14:
        proc[i] = prefix[i]
        i += 1
    let digits: [19]char
    let count: i64 = 0
    let number: i64 = asset
    while true:
        digits[count] = '0' + (number % 10) as char
        count += 1
        number /= 10
        if number == 0: break
    while count > 0:
        count -= 1
        proc[i] = digits[count]
        i += 1
    return open((&proc[0]) as string, 0x80800, 0)

struct BrowserAssets:
    transfer: HttpTransfer
    requests: i64
    bytes: i64

unsafe fn browser_asset_target(page: ptr<BrowserPage>, href: string, target: ptr<char>) -> bool:
    let path_length: i64 = -1
    if browser_web_prefix(page.url) > 0:
        if browser_resolve_href(page, href, target, &path_length) <= 0 or not browser_same_origin(page.url, target as string): return false
        target[browser_fragment_start(target as string)] = '\0'
        return true
    # Local documents resolve only paths relative to the document directory.
    let p: ptr<char> = href as ptr<char>
    let boundary: i64 = 0
    let scheme: bool = true
    while p[boundary] != '\0' and p[boundary] != '#' and p[boundary] != '?':
        if p[boundary] == ':' and scheme: return false
        if p[boundary] == '/': scheme = false
        boundary += 1
    if boundary == 0 or p[0] == '/': return false
    return browser_percent_decode(p, boundary, target, 8193) > 0 and target[0] != '/'

unsafe fn browser_fetch_asset(page: ptr<BrowserPage>, target: string, out: ptr<ByteBuffer>, assets: ptr<BrowserAssets>, media: ptr<BrowserHttpMedia>, limit: i64) -> i64:
    out.len = 0
    media.mime = ""
    if assets.requests >= 24 or assets.bytes >= 4194304 or http_transfer_remaining(&assets.transfer) < 0: return -7
    limit = min(limit, 4194304 - assets.bytes)
    if limit < 1: return -7
    assets.requests += 1
    let status: i64 = 0
    if browser_web_prefix(page.url) > 0:
        assets.transfer.body_bytes = limit
        assets.transfer.response_bytes = limit + BROWSER_HTTP_HEADER_LIMIT
        let policy: BrowserPolicy
        status = browser_load_http_policy(target, out, 0 as ptr<char>, &assets.transfer, &policy, media)
        if status == 0: out.len -= 1  # The shared loader appends a terminator to its body.
    else:
        let fd: i64 = browser_local_asset(page, target)
        if fd < 0: return fd
        defer close(fd)
        while true:
            status = min(0, http_transfer_remaining(&assets.transfer))
            if status < 0: break
            let room: i64 = bytes_read_room(out, limit)
            if room < 0:
                status = room
                break
            let count: i64 = read(fd, out.data + out.len, room)
            if count == -4: continue
            if count <= 0:
                status = count
                break
            if count > limit - out.len:
                status = -90
                break
            out.len += count
    if status == 0: assets.bytes += out.len
    return status

unsafe native fn browser_video_memfd() -> i64:
{
    lea rdi, [rip + .Lvolt_media_file_name]
    mov esi, 3
    mov eax, 319               # memfd_create(MFD_CLOEXEC | MFD_ALLOW_SEALING)
    syscall
    jmp .Lvolt_media_file_done
    .Lvolt_media_file_name: .string "volt-video"
    .Lvolt_media_file_done:
}

unsafe native fn browser_video_seal(fd: i64) -> i64:
{
    mov esi, 1033              # F_ADD_SEALS
    mov edx, 15                # Seal writes, growth, truncation and seal changes.
    mov eax, 72
    syscall
}

unsafe fn browser_video_request_open(request: ptr<BrowserVideoRequest>) -> i64:
    let url: string = (&request.address[0]) as string
    let target: string = (&request.target[0]) as string
    if not request.youtube and browser_web_prefix(url) == 0:
        let page: BrowserPage
        page.url = url
        page.resource_length = request.resource_length
        let input: i64 = browser_local_asset(&page, target)
        if input < 0: return input
        let metadata: [32]u64
        if __volt_fs_statx(input, "" as ptr<char>, 0x1000, 0x200, &metadata[0]) != 0 or (metadata[0] & 0x200) == 0 or metadata[5] > BROWSER_VIDEO_BYTES as u64:
            close(input)
            return -90
        return input
    let buffer: ByteBuffer
    defer bytes_free(&buffer)
    let transfer: HttpTransfer = HttpTransfer(request.deadline, &request.state, BROWSER_VIDEO_BYTES + BROWSER_HTTP_HEADER_LIMIT, BROWSER_VIDEO_BYTES, false, false)
    let policy: BrowserPolicy
    let media: BrowserHttpMedia = BrowserHttpMedia(3, "")
    let loaded: i64 = 0
    if request.youtube: loaded = browser_youtube_fetch(target, &buffer, &transfer, &media)
    else: loaded = browser_load_http_policy(target, &buffer, 0 as ptr<char>, &transfer, &policy, &media)
    if loaded < 0: return loaded
    let size: i64 = buffer.len - 1
    if size <= 0: return -5
    let fd: i64 = browser_video_memfd()
    if fd < 0: return fd
    let written: i64 = 0
    while written < size:
        let remaining: i64 = http_transfer_remaining(&transfer)
        if remaining < 0:
            close(fd)
            return remaining
        let count: i64 = min(262144, size - written)
        if write_all(fd, buffer.data as ptr<char> + written, count) != count:
            close(fd)
            return -5
        written += count
    if browser_video_seal(fd) != 0:
        close(fd)
        return -5
    return fd

unsafe fn browser_video_request_run(data: ptr<char>) -> i32:
    let request: ptr<BrowserVideoRequest> = data as ptr<BrowserVideoRequest>
    request.fd = browser_video_request_open(request)
    if SDL_AtomicSet(&request.state, BROWSER_MEDIA_READY) == BROWSER_MEDIA_CANCELLED: browser_video_request_free(request)
    return 0

unsafe fn browser_video_source(page: ptr<BrowserPage>, node: i64, target: ptr<char>) -> bool:
    let ancestor: i64 = page.nodes[node].parent
    while ancestor > 0:
        let token: ptr<HtmlNode> = &page.nodes[ancestor]
        if html_name_equal(page.source, token, "template") or html_name_equal(page.source, token, "svg") or html_name_equal(page.source, token, "math") or html_name_equal(page.source, token, "iframe"): return false
        ancestor = token.parent
    let candidate: i64 = node
    let source_length: i64 = __volt_strlen(page.source)
    let tries: i64 = 0
    while candidate >= 0 and tries < 32:
        let token: ptr<HtmlNode> = &page.nodes[candidate]
        if candidate == node or html_name_equal(page.source, token, "source"):
            let index: i64 = css_find_html_attribute(page.source, token, page.attributes, "src")
            if index >= 0 and page.attributes[index].has_value:
                let href: [8193]char
                let attr: ptr<HtmlAttribute> = &page.attributes[index]
                let length: i64 = html_decode_range(page.source as ptr<char>, source_length, attr.value_start, attr.value_length, &href[0], 8193)
                if length > 0:
                    let start: i64 = css_trim_start(&href[0], 0, length)
                    href[css_trim_end(&href[0], start, length)] = '\0'
                    if start < length and href[start] != '\0' and browser_asset_target(page, (&href[start]) as string, target): return true
                if candidate == node: return false
        if candidate == node: candidate = token.first_child
        else: candidate = token.next_sibling
        tries += 1
    return false

# Only the generated player gets the locator stored out of band.
unsafe fn browser_youtube_video_source(page: ptr<BrowserPage>, node: i64) -> string:
    if node <= 0 or node != page.storage.youtube_node or browser_youtube_view_id(page.url) == "": return ""
    let source: string = (&page.storage.youtube_media[0]) as string
    if youtube_media_url(source): return source
    return ""

unsafe fn browser_video_start(page: ptr<BrowserPage>, node: i64) -> bool:
    let visual: ptr<BrowserVisual> = &page.storage.visual
    let video: ptr<BrowserVideo> = &visual.video
    browser_video_close(video)
    video.node = node
    video.phase = BROWSER_VIDEO_FAILED
    if not visual.media_allowed:
        video.message = "Видео запрещено CSP"
        return true
    let target: [8193]char
    let source: string = browser_youtube_video_source(page, node)
    let youtube: bool = source != ""
    if youtube: browser_copy_address(&target[0], source)
    elif not browser_video_source(page, node, &target[0]): return true
    let helper: i64 = browser_worker_helper("volt-media")
    if helper < 0:
        video.message = "Нет декодера volt-media"
        return true
    close(helper)
    let deadline: i64 = http_deadline_after(12000)
    if deadline < 0: return true
    if SDL_AtomicAdd(&browser_media_jobs, 1) >= 2:
        SDL_AtomicAdd(&browser_media_jobs, -1)
        return true
    let request: ptr<BrowserVideoRequest> = mmap(sizeof(BrowserVideoRequest)) as ptr<BrowserVideoRequest>
    if (request as i64) <= 0:
        SDL_AtomicAdd(&browser_media_jobs, -1)
        return true
    request.fd = -1
    request.youtube = youtube
    request.resource_length = page.resource_length
    request.deadline = deadline
    browser_copy_address(&request.target[0], (&target[0]) as string)
    browser_copy_address(&request.address[0], page.url)
    let thread: ptr<char> = SDL_CreateThread(callback(browser_video_request_run), "volt-media-load" as ptr<char>, request as ptr<char>)
    if thread == (0 as ptr<char>):
        browser_video_request_free(request)
        return true
    SDL_DetachThread(thread)
    video.request = request
    video.phase = BROWSER_VIDEO_LOADING
    video.muted = css_find_html_attribute(page.source, &page.nodes[node], page.attributes, "muted") >= 0
    return true

unsafe fn browser_video_poll(video: ptr<BrowserVideo>) -> bool:
    if video.phase != BROWSER_VIDEO_LOADING: return browser_video_update(video)
    let request: ptr<BrowserVideoRequest> = video.request
    if http_remaining_ms(request.deadline) < 0:
        browser_video_request_abandon(request)
        video.request = 0 as ptr<BrowserVideoRequest>
        return browser_video_fail(video)
    if SDL_AtomicGet(&request.state) != BROWSER_MEDIA_READY: return false
    video.request = 0 as ptr<BrowserVideoRequest>
    let status: i64 = request.fd
    let mode: string = ""
    if request.youtube: mode = "--combined"
    if status >= 0: status = browser_worker_spawn("volt-media", request.fd, mode, &video.worker)
    browser_video_request_free(request)
    if status < 0: return browser_video_fail(video)
    video.received_ms = http_now_ms()
    video.phase = BROWSER_VIDEO_PLAYING
    return true

unsafe fn browser_video_hit(page: ptr<BrowserPage>, x: i64, y: i64) -> i64:
    if not page.visual or page.storage == (0 as ptr<BrowserPageStorage>) or not page.storage.visual.has_video: return -1
    let index: i64 = page.fragment_count - 1
    while index >= 0:
        let run: ptr<CssFlowFragment> = &page.fragments[index]
        let node: i64 = run.node_index
        if run.byte_length == 0 and not page.boxes[node].hidden and browser_rect_contains(BrowserRect(run.x, run.y, run.advance, run.line_height), x, y) and html_name_equal(page.source, &page.nodes[node], "video"): return node
        index -= 1
    return -1

unsafe fn browser_video_click(page: ptr<BrowserPage>, x: i64, y: i64) -> bool:
    let node: i64 = browser_video_hit(page, x, y)
    if node < 0: return false
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    if video.node == node:
        if video.phase == BROWSER_VIDEO_LOADING:
            browser_video_close(video)
            return true
        if browser_video_pause(video): return true
    return browser_video_start(page, node)

unsafe fn browser_media_attribute(page: ptr<BrowserPage>, node: i64, bounds: ptr<CssMediaRange>, size: i64) -> bool:
    let index: i64 = css_find_html_attribute(page.source, &page.nodes[node], page.attributes, "media")
    if index < 0 or not page.attributes[index].has_value: return true
    let media: [513]char
    let attr: ptr<HtmlAttribute> = &page.attributes[index]
    let n: i64 = html_decode_range(page.source as ptr<char>, size, attr.value_start, attr.value_length, &media[0], 513)
    if n < 0: return false
    let start: i64 = css_trim_start(&media[0], 0, n)
    return start == n or css_media_range(&media[0], start, n, bounds)

unsafe fn browser_collect_visual(page: ptr<BrowserPage>, transfer: ptr<HttpTransfer>, policy: BrowserPolicy) -> i64:
    let visual: ptr<BrowserVisual> = &page.storage.visual
    browser_video_close(&visual.video)
    visual.has_video = false
    visual.media_allowed = not policy.block_media and (not policy.present or browser_web_prefix(page.url) > 0)
    if browser_images_reset(&visual.images, page.node_count) < 0: return -12
    let sheet: ptr<BrowserStyleSheet> = &visual.sheet
    let reset: i64 = browser_sheet_reset(sheet)
    if reset < 0: return reset
    sheet.block_inline = policy.block_style_attributes
    let defaults: string = "head, title, style, script, link, meta, base, template { display:none } html, body, main, header, footer, section, article, nav, aside, div, h1, h2, h3, h4, h5, h6, p, ul, ol, li, blockquote, pre, hr, form, address, figure, figcaption, details, summary, caption, tbody, thead, tfoot, td, th, dl, dt, dd { display:block } body { margin:8px } p, ul, ol, blockquote, pre, dl { margin:1em 0 } h1, h2, h3, h4, h5, h6, b, strong, th { font-weight:bold } h1 { font-size:2em; margin:.67em 0 } h2 { font-size:1.5em; margin:.83em 0 } h3 { font-size:1.17em; margin:1em 0 } h4, h5, h6 { margin:1em 0 } small { font-size:.83em } i, em, address { font-style:italic } a { color:#0000ee; text-decoration:underline } pre, code, kbd, samp { font-family:monospace } pre { white-space:pre } table { display:table } tr { display:table-row } th { text-align:center } ul, ol { padding-left:40px } blockquote, figure { margin:1em 40px } hr { border:1px solid #808080; margin:.5em 0 } button { display:block; width:fit-content; background:#efefef; border:1px solid #767676; padding:4px 10px; font-family:sans-serif; font-size:14px }"
    let bounds: CssMediaRange = CssMediaRange(0, 100000)
    if browser_sheet_add(sheet, defaults as ptr<char>, __volt_strlen(defaults), true, bounds) < 0: return -22
    let media_defaults: string = "video {display:block;background:#101827;object-fit:contain} source, track {display:none}"
    if browser_sheet_add(sheet, media_defaults as ptr<char>, __volt_strlen(media_defaults), true, bounds) < 0: return -22
    if page.storage.js.pid > 0:
        let rule: string = "noscript { display:none }"
        browser_sheet_add(sheet, rule as ptr<char>, __volt_strlen(rule), true, bounds)
    sheet.defaults = sheet.counts.rule_count
    let assets: BrowserAssets
    if transfer != (0 as ptr<HttpTransfer>):
        let deadline: i64 = http_deadline_after(2500)
        if deadline > 0:
            assets.transfer = transfer[0]
            assets.transfer.deadline = min(deadline, transfer.deadline)
    let data: ByteBuffer
    defer bytes_free(&data)
    let source: ptr<char> = page.source as ptr<char>
    let size: i64 = __volt_strlen(page.source)
    let i: i64 = 1
    while i < page.node_count:
        let node: ptr<HtmlNode> = &page.nodes[i]
        let current: i64 = i
        i += 1
        if node.kind != HTML_ELEMENT: continue
        let css: bool = html_name_equal(page.source, node, "style")
        let link_tag: bool = html_name_equal(page.source, node, "link")
        let image: bool = html_name_equal(page.source, node, "img")
        let poster: bool = html_name_equal(page.source, node, "video")
        image = image or poster
        if not css and not link_tag and not image: continue
        let tag: i64 = node.parent
        let inert: bool = false
        while tag > 0 and not inert:
            let ancestor: ptr<HtmlNode> = &page.nodes[tag]
            inert = ancestor.name_start >= 0 and html_name_in(page.source, ancestor.name_start, ancestor.name_length, "template svg math")
            tag = ancestor.parent
        if inert: continue
        if poster: visual.has_video = true
        bounds = CssMediaRange(0, 100000)
        if (css or link_tag) and not browser_media_attribute(page, current, &bounds, size): continue
        if css:
            if node.first_child >= 0 and not policy.block_style_elements:
                let child: ptr<HtmlNode> = &page.nodes[node.first_child]
                if child.kind == HTML_TEXT_NODE: browser_sheet_add(sheet, source + child.text_start, child.text_length, true, bounds)
            continue
        if assets.transfer.deadline <= 0 or (policy.present and browser_web_prefix(page.url) == 0): continue
        if (link_tag and policy.block_styles) or (image and policy.block_images): continue
        let attribute: string = "src"
        if poster: attribute = "poster"
        let limit: i64 = BROWSER_IMAGE_BYTES
        let media: BrowserHttpMedia = BrowserHttpMedia(2, "")
        if link_tag:
            let rel: i64 = css_find_html_attribute(page.source, node, page.attributes, "rel")
            if rel < 0 or not css_range_equal(page.source, page.attributes[rel].value_start, page.attributes[rel].value_length, "stylesheet"): continue
            if css_find_html_attribute(page.source, node, page.attributes, "integrity") >= 0 or css_find_html_attribute(page.source, node, page.attributes, "disabled") >= 0: continue
            attribute = "href"
            limit = CSS_STYLESHEET_LIMIT - sheet.source.len
            media.kind = 1
        let index: i64 = css_find_html_attribute(page.source, node, page.attributes, attribute)
        if index < 0 or not page.attributes[index].has_value: continue
        let target: [8193]char
        let attr: ptr<HtmlAttribute> = &page.attributes[index]
        let n: i64 = html_decode_range(source, size, attr.value_start, attr.value_length, &target[0], 8193)
        if n <= 0: continue
        let start: i64 = css_trim_start(&target[0], 0, n)
        target[css_trim_end(&target[0], start, n)] = '\0'
        if start == n or target[start] == '#': continue
        let resolved: [8193]char
        if not browser_asset_target(page, (&target[start]) as string, &resolved[0]): continue
        let address: string = (&resolved[0]) as string
        if image:
            if browser_image_reuse(&visual.images, current, address): continue
            if visual.images.count >= BROWSER_IMAGE_LIMIT or visual.images.pixels >= BROWSER_IMAGE_PIXELS: continue
        if browser_fetch_asset(page, address, &data, &assets, &media, limit) < 0: continue
        if link_tag: browser_sheet_add(sheet, data.data as ptr<char>, data.len, true, bounds)
        else: browser_image_add(&visual.images, current, &data, media.mime, address)
    return 0

fn browser_shift_node(index: i64, insertion: i64) -> i64:
    if index >= insertion: return index + 1
    return index

# Insert an implicit element in preorder, keeping all DOM links and attribute owners valid.
unsafe fn browser_wrap_nodes(nodes: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>, count: i64, parent: i64, previous: i64, name: i64) -> i64:
    let first: i64 = nodes[parent].first_child
    if previous >= 0: first = nodes[previous].next_sibling
    let at: i64 = first
    if at < 0:
        let tail: i64 = parent
        while nodes[tail].last_child >= 0: tail = nodes[tail].last_child
        at = tail + 1
    let last: i64 = nodes[parent].last_child
    let i: i64 = count
    while i > at:
        nodes[i] = nodes[i - 1]
        i -= 1
    i = 0
    while i <= count:
        if i != at:
            let node: ptr<HtmlNode> = &nodes[i]
            node.parent = browser_shift_node(node.parent, at)
            node.first_child = browser_shift_node(node.first_child, at)
            node.last_child = browser_shift_node(node.last_child, at)
            node.next_sibling = browser_shift_node(node.next_sibling, at)
            node.previous_element = browser_shift_node(node.previous_element, at)
            let j: i64 = 0
            while j < node.attribute_count:
                attributes[node.attribute_start + j].owner = i
                j += 1
        i += 1
    let moved: i64 = -1
    let final_child: i64 = -1
    if first >= 0:
        moved = first + 1
        final_child = last + 1
    let before: i64 = previous
    if before >= 0 and nodes[before].kind != HTML_ELEMENT: before = nodes[before].previous_element
    nodes[at] = HtmlNode(HTML_ELEMENT, parent, moved, final_child, -1, name, 4, -1, 0, 0, 0, 0, 0, before)
    let child: i64 = moved
    let previous_child: i64 = -1
    while child >= 0:
        nodes[child].parent = at
        nodes[child].previous_element = previous_child
        if nodes[child].kind == HTML_ELEMENT: previous_child = child
        child = nodes[child].next_sibling
    if previous >= 0: nodes[previous].next_sibling = at
    else: nodes[parent].first_child = at
    nodes[parent].last_child = at
    return at

unsafe fn browser_implicit_elements(page: ptr<BrowserPage>, source: string, count: i64) -> i64:
    let nodes: ptr<HtmlNode> = page.nodes
    let document: i64 = nodes[0].first_child
    while document > 0 and not html_name_equal(source, &nodes[document], "html"):
        document = nodes[document].next_sibling
    if document < 0:
        document = browser_wrap_nodes(nodes, page.attributes, count, 0, -1, -1)
        count += 1
    let node: i64 = nodes[document].first_child
    while node > 0:
        if html_name_equal(source, &nodes[node], "body"): return count
        node = nodes[node].next_sibling
    let previous: i64 = -1
    node = nodes[document].first_child
    let text: ptr<char> = source as ptr<char>
    while node > 0:
        let current: ptr<HtmlNode> = &nodes[node]
        if current.kind == HTML_TEXT_NODE:
            let at: i64 = current.text_start
            let stop: i64 = at + current.text_length
            while at < stop and html_space(text[at]): at += 1
            if at < stop: break
        elif not html_name_in(source, current.name_start, current.name_length, "head base basefont bgsound link meta title style script template"):
            break
        previous = node
        node = current.next_sibling
    browser_wrap_nodes(nodes, page.attributes, count, document, previous, -2)
    return count + 1

unsafe fn browser_build_tree(page: ptr<BrowserPage>, source: string, scripting: bool) -> i64:
    let storage: ptr<BrowserPageStorage> = page.storage
    if storage == (0 as ptr<BrowserPageStorage>):
        return html_parse(source, page.nodes, 4096, page.attributes, 8192)
    let extra: i64 = 0
    if page.visual: extra = 2
    let node_limit: i64 = HTML_NODE_LIMIT - extra
    let nodes: i64 = max(1024, min(node_limit, buffer_capacity(&storage.nodes)))
    let attributes: i64 = max(2048, min(HTML_ATTRIBUTE_LIMIT, buffer_capacity(&storage.attributes)))
    while true:
        let status: i64 = buffer_reserve(&storage.nodes, nodes + extra)
        if status < 0: return status
        status = buffer_reserve(&storage.attributes, attributes)
        if status < 0: return status
        page.nodes = buffer_data(&storage.nodes)
        page.attributes = buffer_data(&storage.attributes)
        let count: i64 = html_parse_tree_mode(source, page.nodes, nodes, page.attributes, attributes, scripting)
        if count > 0 and page.visual: return browser_implicit_elements(page, source, count)
        if count == HTML_DEPTH_EXCEEDED: return -7
        if count != -7 or (nodes == node_limit and attributes == HTML_ATTRIBUTE_LIMIT): return count
        nodes = min(node_limit, nodes * 2)
        attributes = min(HTML_ATTRIBUTE_LIMIT, attributes * 2)
    return -7

unsafe fn browser_layout_page(page: ptr<BrowserPage>, document: ptr<CssDocumentContext>, text_capacity: i64) -> i64:
    let layout: ptr<CssLayoutContext> = document.layout
    let storage: ptr<BrowserPageStorage> = page.storage
    if storage == (0 as ptr<BrowserPageStorage>):
        match css_prepare_document_mode(document, true):
            Ok(count): return count
            Err(error): return 0 - (error as i64)
    let status: i64 = buffer_reserve(&storage.styles, page.node_count)
    if status < 0: return status
    status = buffer_reserve(&storage.boxes, page.node_count)
    if status < 0: return status
    status = buffer_reserve(&storage.text, text_capacity)
    if status < 0: return status
    page.styles = buffer_data(&storage.styles)
    page.boxes = buffer_data(&storage.boxes)
    page.flow_text = buffer_data(&storage.text)
    document.styles = page.styles
    document.style_capacity = page.node_count
    layout.boxes = page.boxes
    layout.box_capacity = page.node_count
    layout.text_bytes = page.flow_text
    layout.text_capacity = text_capacity
    match css_prepare_styles(document, true):
        Ok(count):
            if count != page.node_count: return -22
        Err(error): return 0 - (error as i64)
    return browser_layout_flow(storage, layout, storage.js.text)

unsafe fn browser_layout_flow(storage: ptr<BrowserPageStorage>, layout: ptr<CssLayoutContext>, overrides: ptr<CssTextOverrides>) -> i64:
    let capacity: i64 = max(1024, min(CSS_FRAGMENT_LIMIT, buffer_capacity(&storage.fragments)))
    while true:
        let status: i64 = buffer_reserve(&storage.fragments, capacity)
        if status < 0: return status
        layout.fragments = buffer_data(&storage.fragments)
        layout.fragment_capacity = capacity
        match css_layout_text(layout, overrides):
            Ok(count): return count
            Err(error):
                if error != 7 or capacity == CSS_FRAGMENT_LIMIT: return 0 - (error as i64)
        capacity = min(CSS_FRAGMENT_LIMIT, capacity * 2)
    return -7

unsafe fn browser_layout_visual(page: ptr<BrowserPage>, storage: ptr<BrowserPageStorage>, layout: ptr<CssLayoutContext>, overrides: ptr<CssTextOverrides>, transfer: ptr<HttpTransfer>, height: i64) -> i64:
    let visual: ptr<BrowserVisual> = &page.storage.visual
    let resized: bool = page.layout_width != layout.viewport_width or page.layout_height != height
    let recascade: bool = storage == page.storage or (resized and visual.sheet.viewport_units) or browser_media_changed(&visual.sheet, page.layout_width, layout.viewport_width)
    let styles: ptr<BrowserStyle> = 0 as ptr<BrowserStyle>
    if recascade:
        if buffer_reserve(&storage.visual.styles, page.node_count) < 0: return -12
        styles = buffer_data(&storage.visual.styles)
        let prepared: i64 = browser_visual_styles(&visual.sheet, layout, page.attributes, styles, height, transfer)
        if prepared < 0: return prepared
    else: styles = buffer_data(&visual.styles)
    let context: BrowserVisualLayout = BrowserVisualLayout(layout, visual, styles, page.attributes, overrides, transfer)
    let capacity: i64 = max(1024, min(CSS_FRAGMENT_LIMIT, buffer_capacity(&storage.fragments)))
    while true:
        let status: i64 = buffer_reserve(&storage.fragments, capacity)
        if status < 0: return status
        layout.fragments = buffer_data(&storage.fragments)
        layout.fragment_capacity = capacity
        status = browser_visual_flow(&context)
        if status >= 0 and recascade and storage != page.storage:
            let prior: Buffer<BrowserStyle> = visual.styles
            visual.styles = storage.visual.styles
            storage.visual.styles = prior
        if status != -7 or capacity == CSS_FRAGMENT_LIMIT: return status
        capacity = min(CSS_FRAGMENT_LIMIT, capacity * 2)
    return -7

unsafe fn browser_prepare_visual(page: ptr<BrowserPage>, view: BrowserViewport, overrides: ptr<CssTextOverrides>, transfer: ptr<HttpTransfer>) -> i64:
    let storage: ptr<BrowserPageStorage> = page.storage
    let text_capacity: i64 = browser_text_capacity(page.source_buffer.len - 1, overrides)
    if buffer_reserve(&storage.boxes, page.node_count) < 0 or buffer_reserve(&storage.text, text_capacity) < 0: return -12
    let layout: CssLayoutContext = CssLayoutContext(page.nodes, page.node_count, page.styles, page.node_count, view.width, buffer_data(&storage.boxes), page.node_count, buffer_data(&storage.fragments), 0, 0, buffer_data(&storage.text), text_capacity, 0, page.source, true)
    let status: i64 = browser_layout_visual(page, storage, &layout, overrides, transfer, view.height)
    if status < 0: return status
    browser_apply_layout(page, &layout)
    page.layout_height = view.height
    return 0

unsafe fn browser_apply_layout(page: ptr<BrowserPage>, layout: ptr<CssLayoutContext>):
    page.boxes = layout.boxes
    page.flow_text = layout.text_bytes
    page.fragments = layout.fragments
    page.fragment_count = layout.fragment_count
    page.text_length = layout.text_length
    page.document_height = page.boxes[0].height
    page.layout_width = layout.viewport_width

unsafe fn browser_reflow_needed(page: ptr<BrowserPage>, view: BrowserViewport) -> bool:
    if view.width != page.layout_width: return true
    return page.visual and page.storage != (0 as ptr<BrowserPageStorage>) and page.layout_height != view.height and page.storage.visual.sheet.viewport_units

unsafe fn browser_reflow_page(page: ptr<BrowserPage>, spare: ptr<BrowserPage>, view: BrowserViewport) -> i64:
    if not browser_reflow_needed(page, view): return 0
    if page.storage == (0 as ptr<BrowserPageStorage>): return -22
    return browser_relayout(page, spare, view, page.storage.js.text)

unsafe fn browser_text_capacity(source_bytes: i64, overrides: ptr<CssTextOverrides>) -> i64:
    let extra: i64 = 0
    if overrides != (0 as ptr<CssTextOverrides>): extra = overrides.total
    return max(1, min(HTML_DOCUMENT_LIMIT, source_bytes + extra))

unsafe fn browser_relayout(page: ptr<BrowserPage>, spare: ptr<BrowserPage>, view: BrowserViewport, overrides: ptr<CssTextOverrides>) -> i64:
    if view.width < 1 or view.width > 4096 or view.height < 1 or view.height > 4096 or page.storage == (0 as ptr<BrowserPageStorage>): return -22
    let scratch: ptr<BrowserPageStorage> = spare.storage
    if scratch == (0 as ptr<BrowserPageStorage>) or scratch == page.storage: return -22
    let text_capacity: i64 = browser_text_capacity(page.source_buffer.len - 1, overrides)
    let status: i64 = buffer_reserve(&scratch.boxes, page.node_count)
    if status < 0: return status
    status = buffer_reserve(&scratch.text, text_capacity)
    if status < 0: return status
    let layout: CssLayoutContext = CssLayoutContext(page.nodes, page.node_count, page.styles, page.node_count, view.width, buffer_data(&scratch.boxes), page.node_count, buffer_data(&scratch.fragments), 0, 0, buffer_data(&scratch.text), text_capacity, 0, page.source, true)
    if page.visual:
        status = browser_layout_visual(page, scratch, &layout, overrides, 0 as ptr<HttpTransfer>, view.height)
    else: status = browser_layout_flow(scratch, &layout, overrides)
    if status < 0: return status
    # Commit the new geometry only after layout succeeds. The spare buffers remain reusable.
    let boxes: Buffer<CssLayoutBox> = page.storage.boxes
    let fragments: Buffer<CssFlowFragment> = page.storage.fragments
    let text: Buffer<char> = page.storage.text
    page.storage.boxes = scratch.boxes
    page.storage.fragments = scratch.fragments
    page.storage.text = scratch.text
    scratch.boxes = boxes
    scratch.fragments = fragments
    scratch.text = text
    spare.boxes = buffer_data(&scratch.boxes)
    spare.fragments = buffer_data(&scratch.fragments)
    spare.flow_text = buffer_data(&scratch.text)
    browser_apply_layout(page, &layout)
    page.layout_height = view.height
    return 0

unsafe fn browser_prepare_page(source_buffer: ptr<ByteBuffer>, url: string, pixels: ptr<u32>, page: ptr<BrowserPage>) -> i64:
    if pixels == (0 as ptr<u32>): return -22
    let status: i64 = browser_prepare_document(source_buffer, url, page, BROWSER_CONTROLLER_WIDTH)
    if status < 0: return status
    return browser_paint_page(page, pixels, 0)

unsafe fn browser_prepare_document(source_buffer: ptr<ByteBuffer>, url: string, page: ptr<BrowserPage>, width: i64) -> i64:
    let policy: BrowserPolicy
    return browser_prepare_loaded_document(source_buffer, url, page, BrowserViewport(width, BROWSER_CONTROLLER_HEIGHT), 0 as ptr<HttpTransfer>, &policy)

struct BrowserScriptPeer:
    host: [254]char
    port: i64
    scheme: i64
    address: [4]u8
    requests: i64

struct BrowserLoadPolicy:
    csp: ptr<BrowserPolicy>
    script_peer: ptr<BrowserScriptPeer>

unsafe fn browser_js_fetch_script(page: ptr<BrowserPage>, attr: ptr<HtmlAttribute>, length: i64, peer: ptr<BrowserScriptPeer>, response: ptr<ByteBuffer>, time: ptr<HttpTransfer>) -> i64:
    if not attr.has_value: return 0
    let href: [8193]char
    let size: i64 = html_decode_range(page.source as ptr<char>, length, attr.value_start, attr.value_length, &href[0], 8193)
    if size <= 0: return 0
    let first: i64 = css_trim_start(&href[0], 0, size)
    let last: i64 = css_trim_end(&href[0], first, size)
    if first == last or href[first] == '#' or not browser_js_valid_text(&href[first], last - first): return 0
    href[last] = '\0'
    let target: [8193]char
    let path_length: i64 = -1
    if browser_resolve_href(page, (&href[first]) as string, &target[0], &path_length) <= 0: return 0
    target[browser_fragment_start((&target[0]) as string)] = '\0'
    let csp: BrowserPolicy
    let policy: BrowserLoadPolicy = BrowserLoadPolicy(&csp, peer)
    let media: BrowserHttpMedia = BrowserHttpMedia(BROWSER_HTTP_SCRIPT, "")
    let loaded: i64 = browser_load_http_peer((&target[0]) as string, response, 0 as ptr<char>, time, &policy, &media)
    if loaded == HTTP_CANCELLED or loaded == HTTP_TIMEOUT: return loaded
    if loaded != 0 or not browser_js_valid_text(response.data as ptr<char>, response.len - 1): return 0
    return response.len - 1  # The HTTP loader appends a terminator, not part of the script.

unsafe fn browser_js_prepare(page: ptr<BrowserPage>, doc: ptr<BrowserJsDocument>, navigation: ptr<HttpTransfer>, peer: ptr<BrowserScriptPeer>) -> i64:
    let deadline: i64 = http_deadline_after(BROWSER_JS_INIT_MS)
    if deadline < 0: return 2
    let time: HttpTransfer = navigation[0]
    time.deadline = min(deadline, navigation.deadline)
    time.accept_gzip = false
    let source_length: i64 = __volt_strlen(doc.source)
    let check_external: bool = true
    let external: bool = false
    let response: ByteBuffer
    defer bytes_free(&response)
    let scripts: BrowserJsScripts
    defer bytes_free(&scripts.frames)
    for i in 1..doc.node_count:
        if i % 256 == 0 and http_transfer_remaining(&time) < 0: return 2
        let node: ptr<HtmlNode> = &doc.nodes[i]
        if node.kind != HTML_ELEMENT or not browser_js_classic(doc, node, source_length) or browser_js_inert(doc, i) or not browser_js_closed(doc, node, source_length): continue
        let src: i64 = css_find_html_attribute(doc.source, node, doc.attributes, "src")
        if src >= 0:
            if peer == (0 as ptr<BrowserScriptPeer>) or not browser_js_external_tag(doc, node): continue
            if check_external:
                external = browser_js_external_allowed(doc, source_length, &time)
                check_external = false
            if not external: continue
            time.body_bytes = min(BROWSER_SCRIPT_BODY_LIMIT, BROWSER_JS_CODE_BYTES - scripts.source_bytes)
            if time.body_bytes == 0 or scripts.count == BROWSER_JS_SCRIPT_LIMIT or peer.requests >= BROWSER_SCRIPT_REQUEST_LIMIT: continue
            time.response_bytes = time.body_bytes + BROWSER_HTTP_HEADER_LIMIT
            let loaded: i64 = browser_js_fetch_script(page, &doc.attributes[src], source_length, peer, &response, &time)
            if loaded < 0: return 2
            if loaded > 0 and browser_js_add_script(&scripts, response.data as ptr<char>, loaded) < 0: return 2
        elif node.first_child >= 0:
            let child: ptr<HtmlNode> = &doc.nodes[node.first_child]
            if browser_js_add_script(&scripts, (doc.source as ptr<char>) + child.text_start, child.text_length) < 0: return 2
    return browser_js_begin(&page.storage.js, doc, &time, &scripts)

unsafe fn browser_prepare_loaded_document(source_buffer: ptr<ByteBuffer>, url: string, page: ptr<BrowserPage>, view: BrowserViewport, transfer: ptr<HttpTransfer>, csp: ptr<BrowserPolicy>) -> i64:
    let policy: BrowserLoadPolicy = BrowserLoadPolicy(csp, 0 as ptr<BrowserScriptPeer>)
    return browser_prepare_document_with_peer(source_buffer, url, page, view, transfer, &policy)

unsafe fn browser_prepare_document_with_peer(source_buffer: ptr<ByteBuffer>, url: string, page: ptr<BrowserPage>, view: BrowserViewport, transfer: ptr<HttpTransfer>, load: ptr<BrowserLoadPolicy>) -> i64:
    if source_buffer == (0 as ptr<ByteBuffer>) or page == (0 as ptr<BrowserPage>) or view.width < 1 or view.width > 4096 or view.height < 1 or view.height > 4096: return -22
    if page.storage == (0 as ptr<BrowserPageStorage>):
        if page.visual: return -22
        if page.nodes == (0 as ptr<HtmlNode>) or page.attributes == (0 as ptr<HtmlAttribute>) or page.styles == (0 as ptr<CssResolvedStyle>) or page.boxes == (0 as ptr<CssLayoutBox>) or page.fragments == (0 as ptr<CssFlowFragment>) or page.flow_text == (0 as ptr<char>): return -22
    if source_buffer.data == (0 as ptr<u8>) or source_buffer.len < 1 or source_buffer.len > HTML_DOCUMENT_LIMIT + 1 or source_buffer.len > source_buffer.cap: return -22
    if source_buffer.data[source_buffer.len - 1] != 0 as u8: return -22
    let source: string = source_buffer.data as ptr<char> as string
    if __volt_strlen(source) != source_buffer.len - 1: return -22
    if page.storage != (0 as ptr<BrowserPageStorage>):
        page.storage.youtube_node = 0
        page.storage.youtube_media[0] = '\0'
    let scripting: bool = page.scripts_enabled and transfer != (0 as ptr<HttpTransfer>) and not load.csp.present
    let node_count: i64 = browser_build_tree(page, source, scripting)
    if node_count < 1: return node_count
    page.source = source
    page.source_buffer = source_buffer
    page.node_count = node_count
    let address_length: i64 = browser_copy_address(&page.address[0], url)
    if address_length < 0: return address_length
    page.url = (&page.address[0]) as string
    if transfer == (0 as ptr<HttpTransfer>): page.resource_length = browser_fragment_start(url)
    let overrides: ptr<CssTextOverrides> = 0 as ptr<CssTextOverrides>
    let policy: BrowserPolicy = load.csp[0]
    if page.storage != (0 as ptr<BrowserPageStorage>):
        let js: ptr<BrowserJs> = &page.storage.js
        browser_js_close(js)
        let doc: BrowserJsDocument = BrowserJsDocument(source, page.nodes, page.attributes, node_count)
        if page.scripts_enabled or page.visual: browser_policy_meta(&policy, source, page.nodes, page.attributes, node_count)
        if page.scripts_enabled and transfer != (0 as ptr<HttpTransfer>):
            if policy.present: js.notice = BROWSER_JS_POLICY
            else: js.notice = browser_js_prepare(page, &doc, transfer, load.script_peer)
            let remaining: i64 = http_transfer_remaining(transfer)
            if remaining < 0: return remaining
            overrides = js.text
            if scripting and js.pid <= 0:
                node_count = browser_build_tree(page, source, false)
                if node_count < 1: return node_count
                page.node_count = node_count
    if page.visual and page.storage != (0 as ptr<BrowserPageStorage>):
        let collected: i64 = browser_collect_visual(page, transfer, policy)
        if collected < 0: return collected
        let prepared: i64 = browser_prepare_visual(page, view, overrides, transfer)
        if prepared == -7 and overrides != (0 as ptr<CssTextOverrides>):
            browser_js_close(&page.storage.js)
            page.storage.js.notice = 2
            prepared = browser_prepare_visual(page, view, 0 as ptr<CssTextOverrides>, transfer)
        return prepared
    let stylesheet_buffer: ByteBuffer
    bytes_init(&stylesheet_buffer)
    defer bytes_free(&stylesheet_buffer)
    if bytes_reserve(&stylesheet_buffer, CSS_STYLESHEET_LIMIT + 1) != 0: return -12
    let rules_buffer: Buffer<CssRule>
    let selectors_buffer: Buffer<CssSelector>
    let declarations_buffer: Buffer<CssDeclaration>
    defer buffer_free(&rules_buffer)
    defer buffer_free(&selectors_buffer)
    defer buffer_free(&declarations_buffer)
    if buffer_reserve(&rules_buffer, 1024) != 0 or buffer_reserve(&selectors_buffer, 4096) != 0 or buffer_reserve(&declarations_buffer, 8192) != 0:
        return -12
    let stylesheet: ptr<char> = stylesheet_buffer.data as ptr<char>
    let defaults: string = "head, title, style, script, link, meta, template { display: none; } html, body, main, header, footer, section, article, nav, div, h1, h2, h3, h4, h5, h6, p, ul, ol, li, blockquote, pre, br, hr { display: block; } a { color: #245db5; }"
    let default_length: i64 = __volt_strlen(defaults)
    let dp: ptr<char> = defaults as ptr<char>
    let i: i64 = 0
    while i < default_length:
        stylesheet[i] = dp[i]
        i += 1
    if page.storage != (0 as ptr<BrowserPageStorage>) and page.storage.js.pid > 0:
        let more: ptr<char> = " noscript { display:none !important; }" as ptr<char>
        i = 0
        while more[i] != '\0':
            stylesheet[default_length + i] = more[i]
            i += 1
        default_length += i
    let inline_length: i64 = css_collect_inline_styles(source, page.nodes, node_count, &stylesheet[default_length], CSS_STYLESHEET_LIMIT + 1 - default_length)
    if inline_length == -7: stylesheet[default_length] = 0 as char
    elif inline_length < 0: return inline_length
    let css_source: string = (&stylesheet[0]) as string
    let rules: ptr<CssRule> = buffer_data(&rules_buffer)
    let selectors: ptr<CssSelector> = buffer_data(&selectors_buffer)
    let declarations: ptr<CssDeclaration> = buffer_data(&declarations_buffer)
    let buffers: CssBuffers = CssBuffers(rules, 1024, selectors, 4096, declarations, 8192)
    let rule_count: i64 = css_parse(css_source, &buffers)
    if rule_count == -22 or rule_count == -7:
        # shortcut: keep default styles if the author stylesheet exceeds the CSS budget or fails to parse.
        stylesheet[default_length] = 0 as char
        rule_count = css_parse(css_source, &buffers)
    if rule_count < 0: return rule_count
    let selector_count: i64 = 0
    let declaration_count: i64 = 0
    i = 0
    while i < rule_count:
        selector_count += rules[i].selector_count
        declaration_count += rules[i].declaration_count
        i += 1
    let layout: CssLayoutContext = CssLayoutContext(page.nodes, node_count, page.styles, node_count, view.width, page.boxes, 4096, page.fragments, 16384, 0, page.flow_text, 65536, 0, source, true)
    let cascade: CssCascadeContext = CssCascadeContext(css_source, rules, rule_count, selectors, selector_count, declarations, declaration_count, source, page.nodes, page.attributes, node_count, 0)
    let document: CssDocumentContext = CssDocumentContext(&cascade, page.styles, 4096, &layout)
    let prepared: i64 = browser_layout_page(page, &document, browser_text_capacity(source_buffer.len - 1, overrides))
    if prepared < 0 and overrides != (0 as ptr<CssTextOverrides>):
        browser_js_close(&page.storage.js)
        page.storage.js.notice = 2
        prepared = browser_layout_page(page, &document, max(1, source_buffer.len - 1))
    if prepared < 0: return prepared
    if prepared != node_count: return -22
    browser_apply_layout(page, &layout)
    page.layout_height = view.height
    return 0


unsafe fn browser_load_http(url: string, buffer: ptr<ByteBuffer>, final_address: ptr<char>, transfer: ptr<HttpTransfer>) -> i64:
    let csp: BrowserPolicy
    return browser_load_http_policy(url, buffer, final_address, transfer, &csp, 0 as ptr<BrowserHttpMedia>)

unsafe fn browser_http_body(buffer: ptr<ByteBuffer>, offset: i64, limit: i64) -> i64:
    let length: i64 = buffer.len - offset
    if length < 0 or length > limit: return -90
    if offset > 0:
        for i in 0..length: buffer.data[i] = buffer.data[offset + i]
    buffer.len = length
    return bytes_push(buffer, 0 as u8)

# The native view uses a separate HTTPS request with no redirect handling or page credentials.
unsafe fn browser_youtube_fetch(input: string, buffer: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>, media: ptr<BrowserHttpMedia>) -> i64:
    let host: [254]char
    let path: [8193]char
    if media == (0 as ptr<BrowserHttpMedia>):
        if not youtube_id_valid(input as ptr<char>, __volt_strlen(input)): return -22
        browser_copy_address(&host[0], "www.youtube.com")
        let prefix: i64 = browser_copy_address(&path[0], "/watch?v=")
        browser_copy_address(&path[prefix], input)
    else:
        if not youtube_media_url(input): return -13
        let port: i64 = 0
        if browser_parse_url(input, &host[0], &path[0], &port) != 0 or port != 443: return -13
    let fetched: i64 = browser_youtube_get((&host[0]) as string, (&path[0]) as string, buffer, transfer)
    if fetched < 0: return fetched
    return browser_youtube_response(buffer, transfer, media)

unsafe fn browser_youtube_response(buffer: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>, media: ptr<BrowserHttpMedia>) -> i64:
    let status: i64 = 0
    let location: [8193]char
    let policy: BrowserPolicy
    let offset: i64 = browser_http_response(buffer, transfer, &status, &location[0], &policy, media)
    if offset < 0: return offset
    if status != 200: return -BROWSER_HTTP_STATUS_BASE - status
    if media != (0 as ptr<BrowserHttpMedia>) and media.mime != "video/mp4" and media.mime != "video/webm": return -22
    return browser_http_body(buffer, offset, transfer.body_bytes)

unsafe fn browser_load_http_policy(url: string, buffer: ptr<ByteBuffer>, final_address: ptr<char>, transfer: ptr<HttpTransfer>, csp: ptr<BrowserPolicy>, media: ptr<BrowserHttpMedia>) -> i64:
    let policy: BrowserLoadPolicy = BrowserLoadPolicy(csp, 0 as ptr<BrowserScriptPeer>)
    return browser_load_http_peer(url, buffer, final_address, transfer, &policy, media)

unsafe fn browser_load_http_peer(url: string, buffer: ptr<ByteBuffer>, final_address: ptr<char>, transfer: ptr<HttpTransfer>, policy: ptr<BrowserLoadPolicy>, media: ptr<BrowserHttpMedia>) -> i64:
    let script: bool = media != (0 as ptr<BrowserHttpMedia>) and media.kind == BROWSER_HTTP_SCRIPT
    let peer: ptr<BrowserScriptPeer> = policy.script_peer
    if script and (peer == (0 as ptr<BrowserScriptPeer>) or peer.port == 0): return -22
    let current_url: [8193]char
    let p: ptr<char> = url as ptr<char>
    let n: i64 = __volt_strlen(url)
    if n < 8 or n > 8192: return -22
    let i: i64 = 0
    while i <= n:
        current_url[i] = p[i]
        i += 1
    let visited: [6][8193]char
    let hop: i64 = 0
    let final_done: bool = false
    while not final_done:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        let host: [254]char
        let target: [8193]char
        let port: [1]i64
        if browser_parse_url((&current_url[0]) as string, &host[0], &target[0], &port[0]) < 0: return -22
        let host_len: i64 = __volt_strlen((&host[0]) as string)
        let target_len: i64 = __volt_strlen((&target[0]) as string)
        let canonical: [8193]char
        let scheme: string = "http://"
        let current_scheme: ptr<char> = (&current_url[0]) as ptr<char>
        if current_scheme[4] == 's': scheme = "https://"
        let scheme_len: i64 = __volt_strlen(scheme)
        let secure: bool = scheme_len == 8
        if script:
            if scheme_len != peer.scheme or port[0] != peer.port or host_len != __volt_strlen((&peer.host[0]) as string) or not css_bytes_equal(&host[0], &peer.host[0], host_len, true): return -13
        let cpos: i64 = 0
        while cpos < scheme_len:
            canonical[cpos] = (scheme as ptr<char>)[cpos]
            cpos += 1
        let k: i64 = 0
        while k < host_len:
            let c: i64 = host[k] as i64
            if c >= 65 and c <= 90: c += 32
            canonical[cpos] = c as char
            cpos += 1
            k += 1
        if (secure and port[0] != 443) or (not secure and port[0] != 80):
            canonical[cpos] = ':' as char
            cpos += 1
            let digits: [5]char
            let value: i64 = port[0]
            let digit_count: i64 = 0
            while value > 0:
                digits[digit_count] = '0' + (value % 10) as char
                digit_count += 1
                value /= 10
            while digit_count > 0:
                digit_count -= 1
                canonical[cpos] = digits[digit_count]
                cpos += 1
        if target_len > BROWSER_ADDRESS_LIMIT - cpos: return -90
        k = 0
        while k < target_len:
            canonical[cpos] = target[k]
            cpos += 1
            k += 1
        canonical[cpos] = 0 as char
        k = 0
        while k < hop:
            let q: i64 = 0
            let same: bool = true
            while q < 8192 and (canonical[q] != 0 or visited[k][q] != 0):
                if canonical[q] != visited[k][q]: same = false
                q += 1
            if q < 8192 and canonical[q] != visited[k][q]: same = false
            if same: return -1003
            k += 1
        k = 0
        while canonical[k] != 0:
            visited[hop][k] = canonical[k]
            k += 1
        visited[hop][k] = 0 as char
        let address: [4]u8
        let ip: ptr<u8> = &address[0]
        let fetched: i64
        if script:
            # Count every hop, including failures, to bound total wire bytes. Never repeat blocking DNS.
            if peer.requests >= BROWSER_SCRIPT_REQUEST_LIMIT: return -90
            peer.requests += 1
            ip = &peer.address[0]
        elif http_parse_ipv4((&host[0]) as string, ip) < 0:
            remaining = http_transfer_remaining(transfer)
            if remaining < 0: return remaining
            let resolved: i64 = dns_resolve_ipv4((&host[0]) as string, ip)
            remaining = http_transfer_remaining(transfer)
            if remaining < 0: return remaining
            if resolved < 0: return resolved
        if secure:
            fetched = tls_http_get_transfer((&host[0]) as string, port[0], (&target[0]) as string, ip, buffer, transfer)
        else:
            fetched = http_get_transfer((&host[0]) as string, port[0], (&target[0]) as string, ip, buffer, transfer)
        if fetched < 0: return fetched
        let status: [1]i64
        let location: [8193]char
        location[0] = 0 as char
        let empty_policy: BrowserPolicy
        policy.csp[0] = empty_policy
        let body_offset: i64 = browser_http_response(buffer, transfer, &status[0], &location[0], policy.csp, media)
        if body_offset < 0: return body_offset
        if browser_http_redirect(status[0]):
            if hop >= 5: return -1004
            let next_url: [8193]char
            let current_address: string = (&current_url[0]) as string
            if script:
                let base: BrowserPage
                base.url = current_address
                base.resource_length = browser_fragment_start(current_address)
                let path_length: i64 = -1
                if browser_resolve_href(&base, (&location[0]) as string, &next_url[0], &path_length) <= 0: return -22
            elif browser_resolve_location(current_address, (&location[0]) as string, &next_url[0]) < 0: return -22
            let next_address: string = (&next_url[0]) as string
            if not script and media != (0 as ptr<BrowserHttpMedia>) and not browser_same_origin(url, next_address): return -13
            let next_length: i64 = __volt_strlen(next_address)
            let fragment: i64 = browser_fragment_start(current_address)
            let suffix: string = (&current_url[fragment]) as string
            if browser_fragment_start(next_address) == next_length and suffix != "":
                if __volt_strlen(suffix) > BROWSER_ADDRESS_LIMIT - next_length: return -90
                browser_copy_address(&next_url[next_length], suffix)
            browser_copy_address(&current_url[0], next_address)
            hop += 1
        else:
            if status[0] != 200: return -BROWSER_HTTP_STATUS_BASE - status[0]
            let terminated: i64 = browser_http_body(buffer, body_offset, transfer.body_bytes)
            if terminated < 0: return terminated
            if not script and peer != (0 as ptr<BrowserScriptPeer>):
                browser_copy_address(&peer.host[0], (&host[0]) as string)
                peer.port = port[0]
                peer.scheme = scheme_len
                for byte in 0..4: peer.address[byte] = address[byte]
            final_done = true
    if final_address != (0 as ptr<char>): browser_copy_address(final_address, (&current_url[0]) as string)
    return 0

unsafe fn browser_open_local(path: string, file_length: i64, transfer: ptr<HttpTransfer>) -> i64:
    # O_NONBLOCK avoids hanging on a local pipe.
    let input: ptr<char> = path as ptr<char>
    let file: [8193]char
    let name: string = path
    if input[file_length] != 0:
        let i: i64 = 0
        while i < file_length:
            file[i] = input[i]
            i += 1
        file[file_length] = 0 as char
        name = (&file[0]) as string
    let remaining: i64 = http_transfer_remaining(transfer)
    if remaining < 0: return remaining
    return open(name, 2048, 0)

unsafe fn browser_validate_target(path: string) -> i64:
    let input: ptr<char> = path as ptr<char>
    let length: i64 = __volt_strlen(path)
    if length == 0 or length > BROWSER_ADDRESS_LIMIT: return -1001
    if browser_youtube_view_id(path) != "": return 0
    if browser_fragment_start(path) == 10 and html_match(input, 0, length, "about:home"): return 0
    if browser_web_prefix(path) > 0:
        let host: [254]char
        let target: [8193]char
        let port: i64 = 0
        if browser_parse_url(path, &host[0], &target[0], &port) < 0: return -1001
    else:
        let scan: i64 = 0
        while scan < length and input[scan] != '/' and input[scan] != '#':
            if input[scan] == ':': return -1001
            scan += 1
    return 0

unsafe fn browser_fetch_source(path: string, source_buffer: ptr<ByteBuffer>, out: ptr<BrowserSource>, known_length: i64, transfer: ptr<HttpTransfer>) -> i64:
    if browser_validate_target(path) < 0: return -1001
    let final_address: ptr<char> = &out.address[0]
    let input: ptr<char> = path as ptr<char>
    let n: i64 = __volt_strlen(path)
    let youtube: string = browser_youtube_view_id(path)
    if youtube != "":
        let metadata: YoutubeMetadata
        browser_copy_address(final_address, path)
        out.resource_length = n
        return browser_youtube_html(source_buffer, youtube, &metadata, false, false)
    if browser_fragment_start(path) == 10 and html_match(input, 0, n, "about:home"):
        let home: string = "<style>body { color: #18232b; } h1, p { margin: 8px; } h1 { background: #246b66; color: white; }</style><body><h1>Браузер VOLT</h1><p>Ctrl+L — адрес страницы. Ctrl+V — вставить. Enter — открыть.</p><p><a href=\"https://example.org/\">Открыть example.org</a></p></body>"
        let length: i64 = __volt_strlen(home)
        source_buffer.len = 0
        let reserved: i64 = bytes_reserve(source_buffer, length + 1)
        if reserved < 0: return reserved
        let data: ptr<char> = home as ptr<char>
        let i: i64 = 0
        while i <= length:
            source_buffer.data[i] = data[i] as u8
            i += 1
        source_buffer.len = length + 1
        browser_copy_address(final_address, path)
        out.resource_length = 10
        return 0
    if browser_web_prefix(path) > 0:
        let policy: BrowserLoadPolicy = BrowserLoadPolicy(&out.csp, &out.script_peer)
        let status: i64 = browser_load_http_peer(path, source_buffer, final_address, transfer, &policy, 0 as ptr<BrowserHttpMedia>)
        if status == 0: out.resource_length = browser_fragment_start(final_address as string)
        return status
    let file_length: i64 = n
    if known_length >= 0:
        if known_length == 0 or known_length > n or (known_length < n and input[known_length] != '#'): return -1001
        file_length = known_length
    let fd: i64 = browser_open_local(path, file_length, transfer)
    if fd == -2 and known_length < 0:
        # A local file can contain '#' in its name. Try the literal path first.
        let fragment: i64 = browser_fragment_start(path)
        if fragment > 0 and fragment < n:
            file_length = fragment
            fd = browser_open_local(path, file_length, transfer)
    if fd == HTTP_CANCELLED or fd == HTTP_TIMEOUT: return fd
    if fd < 0: return -1002
    defer close(fd)
    source_buffer.len = 0
    while true:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        let room: i64 = bytes_read_room(source_buffer, HTML_DOCUMENT_LIMIT)
        if room < 0: return room
        let size: i64 = read(fd, source_buffer.data + source_buffer.len, room)
        if size == -4: continue
        if size < 0: return -1002
        if size == 0: break
        if size > HTML_DOCUMENT_LIMIT - source_buffer.len: return -90
        source_buffer.len += size
    source_buffer.data[source_buffer.len] = 0 as u8
    source_buffer.len += 1
    browser_copy_address(final_address, path)
    out.resource_length = file_length
    return 0

unsafe fn browser_present_pixels(renderer: ptr<char>, pixels: ptr<u32>, width: i64, height: i64) -> i64:
    let texture: ptr<char> = sdl_texture_create_argb8888(renderer, width, height)
    if texture == (0 as ptr<char>): return -22
    let status: i64 = sdl_texture_update_argb8888(texture, pixels, width, height, width, width * height)
    if status == 0: status = sdl_texture_copy(renderer, texture)
    sdl_texture_destroy(texture)
    return status

struct BrowserNavigationController:
    active_page: ptr<BrowserPage>
    candidate_page: ptr<BrowserPage>
    active_buffer: ptr<ByteBuffer>
    candidate_buffer: ptr<ByteBuffer>
    active_pixels: ptr<u32>
    candidate_pixels: ptr<u32>
    scroll: ptr<PaintScrollState>
    renderer: ptr<char>
    request_count: i64
    present_count: i64
    draw_presented: bool

unsafe fn browser_scroll_to_fragment(page: ptr<BrowserPage>, scroll: ptr<PaintScrollState>):
    let address: ptr<char> = page.url as ptr<char>
    let at: i64 = page.resource_length
    if address[at] == 0 or address[at + 1] == 0:
        scroll.offset = 0
        return
    let y: i64 = browser_fragment_y(page)
    if y >= 0: scroll.offset = min(y, scroll.max_offset)

unsafe fn browser_fragment_y(page: ptr<BrowserPage>) -> i64:
    let address: ptr<char> = page.url as ptr<char>
    let at: i64 = page.resource_length
    if address[at] != '#' or address[at + 1] == 0: return -1
    let name: [8193]char
    let fragment: ptr<char> = address + at + 1
    if browser_percent_decode(fragment, __volt_strlen(fragment as string), &name[0], 8193) < 0: return -1
    return browser_find_anchor(page, (&name[0]) as string)

struct BrowserSource:
    address: [8193]char
    resource_length: i64
    csp: BrowserPolicy
    script_peer: BrowserScriptPeer

unsafe fn browser_load_candidate(page: ptr<BrowserPage>, buffer: ptr<ByteBuffer>, url: string, known_length: i64, view: BrowserViewport, transfer: ptr<HttpTransfer>) -> i64:
    let source: BrowserSource
    transfer.accept_gzip = page.visual
    let status: i64 = browser_fetch_source(url, buffer, &source, known_length, transfer)
    if status == 0: status = min(0, http_transfer_remaining(transfer))
    if status == 0:
        page.resource_length = source.resource_length
        let address: string = (&source.address[0]) as string
        let network: ptr<HttpTransfer> = transfer
        if browser_youtube_view_id(address) != "": network = 0 as ptr<HttpTransfer>
        let peer: ptr<BrowserScriptPeer> = 0 as ptr<BrowserScriptPeer>
        if browser_web_prefix(address) > 0: peer = &source.script_peer
        let policy: BrowserLoadPolicy = BrowserLoadPolicy(&source.csp, peer)
        status = browser_prepare_document_with_peer(buffer, address, page, view, network, &policy)
    if status == 0: status = min(0, http_transfer_remaining(transfer))
    if status < 0:
        if page.storage != (0 as ptr<BrowserPageStorage>): browser_js_close(&page.storage.js)
        bytes_free(buffer)
    return status

unsafe fn browser_youtube_prepare(page: ptr<BrowserPage>, buffer: ptr<ByteBuffer>, url: string, view: BrowserViewport, response: ptr<ByteBuffer>) -> i64:
    let id: string = browser_youtube_view_id(url)
    if id == "" or page.storage == (0 as ptr<BrowserPageStorage>): return -22
    let metadata: YoutubeMetadata
    let fetched: bool = response != (0 as ptr<ByteBuffer>)
    if fetched:
        if youtube_metadata(response.data as ptr<char>, response.len - 1, id, &metadata) != 1: metadata.media[0] = '\0'
    let status: i64 = browser_youtube_html(buffer, id, &metadata, true, fetched)
    if status < 0: return status
    let policy: BrowserPolicy
    status = browser_prepare_loaded_document(buffer, url, page, view, 0 as ptr<HttpTransfer>, &policy)
    if status < 0 or metadata.media[0] == '\0': return status
    for node in 1..page.node_count:
        if html_name_equal(page.source, &page.nodes[node], "video"):
            page.storage.youtube_node = node
            browser_copy_address(&page.storage.youtube_media[0], (&metadata.media[0]) as string)
            return 0
    return -22

unsafe fn browser_youtube_load(page: ptr<BrowserPage>, buffer: ptr<ByteBuffer>, url: string, view: BrowserViewport, transfer: ptr<HttpTransfer>) -> i64:
    let id: string = browser_youtube_view_id(url)
    if id == "": return -22
    let response: ByteBuffer
    defer bytes_free(&response)
    transfer.accept_gzip = true
    let fetched: i64 = browser_youtube_fetch(id, &response, transfer, 0 as ptr<BrowserHttpMedia>)
    let remaining: i64 = http_transfer_remaining(transfer)
    if remaining < 0: return remaining
    let source: ptr<ByteBuffer> = 0 as ptr<ByteBuffer>
    if fetched == 0: source = &response
    let prepared: i64 = browser_youtube_prepare(page, buffer, url, view, source)
    if prepared < 0: return prepared
    return min(0, http_transfer_remaining(transfer))

unsafe fn browser_swap_page(controller: ptr<BrowserNavigationController>, page: ptr<BrowserPage>, buffer: ptr<ByteBuffer>):
    let old_buffer: ByteBuffer = controller.active_buffer[0]
    controller.active_buffer[0] = buffer[0]
    buffer[0] = old_buffer
    let old_page: BrowserPage = controller.active_page[0]
    controller.active_page[0] = page[0]
    page[0] = old_page
    controller.active_page.source_buffer = controller.active_buffer
    controller.active_page.url = (&controller.active_page.address[0]) as string
    page.source_buffer = buffer
    page.url = (&page.address[0]) as string
    if page.storage != (0 as ptr<BrowserPageStorage>):
        browser_js_close(&page.storage.js)
        browser_video_close(&page.storage.visual.video)
        page.storage.youtube_node = 0
        page.storage.youtube_media[0] = '\0'

unsafe fn browser_controller_navigate_url(controller: ptr<BrowserNavigationController>, target_url: string) -> i64:
    return browser_controller_load(controller, target_url, -1)

unsafe fn browser_controller_load(controller: ptr<BrowserNavigationController>, target_url: string, known_length: i64) -> i64:
    if controller == (0 as ptr<BrowserNavigationController>) or controller.active_page == (0 as ptr<BrowserPage>) or controller.candidate_page == (0 as ptr<BrowserPage>) or controller.active_buffer == (0 as ptr<ByteBuffer>) or controller.candidate_buffer == (0 as ptr<ByteBuffer>) or controller.active_pixels == (0 as ptr<u32>) or controller.candidate_pixels == (0 as ptr<u32>) or controller.scroll == (0 as ptr<PaintScrollState>): return -22
    controller.request_count += 1
    let deadline: i64 = http_deadline_after(HTTP_DEFAULT_TIMEOUT_MS)
    if deadline < 0: return deadline
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    controller.candidate_page.scripts_enabled = controller.active_page.scripts_enabled
    controller.candidate_page.visual = controller.active_page.visual
    let view: BrowserViewport = BrowserViewport(BROWSER_CONTROLLER_WIDTH, BROWSER_CONTROLLER_HEIGHT)
    let prepared: i64 = browser_load_candidate(controller.candidate_page, controller.candidate_buffer, target_url, known_length, view, &transfer)
    if prepared != 0: return prepared
    prepared = browser_paint_page(controller.candidate_page, controller.candidate_pixels, 0)
    if prepared != 0:
        if controller.candidate_page.storage != (0 as ptr<BrowserPageStorage>): browser_js_close(&controller.candidate_page.storage.js)
        bytes_free(controller.candidate_buffer)
        return prepared
    if controller.renderer != (0 as ptr<char>):
        if browser_present_pixels(controller.renderer, controller.candidate_pixels, BROWSER_CONTROLLER_WIDTH, BROWSER_CONTROLLER_HEIGHT) != 0:
            if controller.candidate_page.storage != (0 as ptr<BrowserPageStorage>): browser_js_close(&controller.candidate_page.storage.js)
            bytes_free(controller.candidate_buffer)
            return -22
        controller.present_count += 1
        if controller.draw_presented: sdl_present(controller.renderer)
    browser_swap_page(controller, controller.candidate_page, controller.candidate_buffer)
    let i: i64 = 0
    while i < BROWSER_CONTROLLER_WIDTH * BROWSER_CONTROLLER_HEIGHT:
        controller.active_pixels[i] = controller.candidate_pixels[i]
        i += 1
    let view_height: i64 = BROWSER_VIEW_HEIGHT
    if controller.active_page.visual: view_height = BROWSER_CONTROLLER_HEIGHT
    controller.scroll.max_offset = paint_scroll_max(controller.active_page.document_height, view_height)
    controller.scroll.offset = 0
    browser_scroll_to_fragment(controller.active_page, controller.scroll)
    return 1

unsafe fn browser_same_resource(page: ptr<BrowserPage>, target: string, resource_length: i64) -> bool:
    let current: ptr<char> = page.url as ptr<char>
    let wanted: ptr<char> = target as ptr<char>
    if page.resource_length == resource_length:
        let i: i64 = 0
        while i < resource_length and current[i] == wanted[i]: i += 1
        if i == resource_length: return true
    let scheme: i64 = browser_web_prefix(page.url)
    if scheme == 0 or scheme != browser_web_prefix(target): return false
    let current_host: [254]char
    let wanted_host: [254]char
    let current_target: [8193]char
    let wanted_target: [8193]char
    let current_port: i64 = 0
    let wanted_port: i64 = 0
    if browser_parse_url(page.url, &current_host[0], &current_target[0], &current_port) != 0: return false
    if browser_parse_url(target, &wanted_host[0], &wanted_target[0], &wanted_port) != 0: return false
    if current_port != wanted_port or (&current_target[0]) as string != (&wanted_target[0]) as string: return false
    let i: i64 = 0
    while current_host[i] != 0 or wanted_host[i] != 0:
        let a: i64 = current_host[i] as i64
        let b: i64 = wanted_host[i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn browser_update_fragment(page: ptr<BrowserPage>, target: string, known_length: i64) -> bool:
    let current: ptr<char> = page.url as ptr<char>
    let base_length: i64 = page.resource_length
    let length: i64 = __volt_strlen(target)
    let resource_length: i64 = known_length
    if resource_length < 0:
        resource_length = length
        if browser_web_prefix(target) > 0: resource_length = browser_fragment_start(target)
        elif target == page.url: resource_length = base_length
    if resource_length > 0 and resource_length <= length and length <= BROWSER_ADDRESS_LIMIT:
        if (resource_length < length or current[base_length] == '#') and browser_same_resource(page, target, resource_length):
            browser_copy_address(&page.address[0], target)
            page.resource_length = resource_length
            return true
    return false

unsafe fn browser_controller_follow(controller: ptr<BrowserNavigationController>, target: string, known_length: i64) -> i64:
    if browser_update_fragment(controller.active_page, target, known_length):
        browser_scroll_to_fragment(controller.active_page, controller.scroll)
        return 1
    return browser_controller_load(controller, target, known_length)

unsafe fn browser_controller_dispatch(controller: ptr<BrowserNavigationController>, event: SdlInputEvent) -> i64:
    if event.kind != SDL_INPUT_EVENT_BUTTON or event.button != SDL_BUTTON_LEFT: return 0
    if controller == (0 as ptr<BrowserNavigationController>) or controller.scroll == (0 as ptr<PaintScrollState>): return -22
    if event.mouse_y < 0 or event.mouse_y >= BROWSER_VIEW_HEIGHT: return 0
    let href: [8193]char
    let hit: i64 = browser_hit_test(controller.active_page, controller.scroll.offset, event.mouse_x, event.mouse_y, &href[0])
    if hit <= 0: return 0
    return browser_follow_link(controller, (&href[0]) as string)

unsafe fn browser_follow_link(controller: ptr<BrowserNavigationController>, href: string) -> i64:
    let target: [8193]char
    let resource_length: i64 = -1
    if browser_resolve_href(controller.active_page, href, &target[0], &resource_length) < 0: return 0
    return browser_controller_follow(controller, (&target[0]) as string, resource_length)
