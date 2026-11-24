use html
use bytes

const BROWSER_SEARCH_FILE_BYTES: i64 = 262144
const BROWSER_SEARCH_TERM_BYTES: i64 = 96

struct BrowserSearchFields:
    title: ByteBuffer
    body: ByteBuffer

struct BrowserSearchDom:
    nodes: [8192]HtmlNode
    attributes: [16384]HtmlAttribute

unsafe fn browser_search_utf8(text: ptr<char>, length: i64) -> bool:
    let at: i64 = 0
    while at < length:
        let start: i64 = at
        let code: i64 = utf8_next(text, &at, length)
        if code == 0 or (code == 0xfffd and at - start == 1): return false
    return true

# shortcut: exact ASCII Latin/Russian words and digits; use Unicode word breaking if more scripts are needed.
fn browser_search_fold(code: i64) -> i64:
    if code >= 65 and code <= 90: return code + 32
    if code >= 0x410 and code <= 0x42f: return code + 32
    if code == 0x401: return 0x451
    if (code >= 97 and code <= 122) or (code >= 48 and code <= 57) or (code >= 0x430 and code <= 0x44f) or code == 0x451: return code
    return 0

# Skip overlong words rather than indexing or querying a misleading prefix.
unsafe fn browser_search_next_term(text: ptr<char>, length: i64, at: ptr<i64>, key: ptr<char>) -> bool:
    while at[0] < length:
        let size: i64 = 0
        while at[0] < length:
            let code: i64 = browser_search_fold(utf8_next(text, at, length))
            if code == 0: break
            if size <= BROWSER_SEARCH_TERM_BYTES:
                let n: i64 = utf8_write(code, key + size, BROWSER_SEARCH_TERM_BYTES - size)
                if n < 0: size = BROWSER_SEARCH_TERM_BYTES + 1
                else: size += n
        if size > 0 and size <= BROWSER_SEARCH_TERM_BYTES:
            key[size] = '\0'
            return true
    return false

# Trim/collapse whitespace and clip by Unicode scalars, not bytes. The result needs 644 bytes.
unsafe fn browser_search_preview(text: ptr<char>, length: i64, output: ptr<char>):
    let at: i64 = 0
    let bytes: i64 = 0
    let chars: i64 = 0
    let space: bool = false
    while at < length:
        let code: i64 = utf8_next(text, &at, length)
        if code <= 32 or (code >= 0x7f and code <= 0xa0) or (code >= 0x2000 and code <= 0x200a) or code == 0xfeff:
            space = chars > 0
            continue
        if chars >= 160 or (space and chars == 159):
            bytes += utf8_write(0x2026, output + bytes, 643 - bytes)
            break
        if space:
            output[bytes] = ' '
            bytes += 1
            chars += 1
            space = false
        bytes += utf8_write(code, output + bytes, 643 - bytes)
        chars += 1
    output[bytes] = '\0'

unsafe fn browser_search_append_node(source: string, size: i64, node: ptr<HtmlNode>, out: ptr<ByteBuffer>) -> i64:
    let status: i64 = bytes_reserve(out, out.len + node.text_length + 1)
    if status < 0: return status
    let written: i64 = html_decode_range(source as ptr<char>, size, node.text_start, node.text_length, (out.data + out.len) as ptr<char>, out.cap - out.len)
    if written < 0: return written
    out.len += written
    return 0

unsafe fn browser_search_break(out: ptr<ByteBuffer>) -> i64:
    if out.len == 0 or out.data[out.len - 1] == 32: return 0
    return bytes_push(out, 32 as u8)

unsafe fn browser_search_collect(source: string, size: i64, nodes: ptr<HtmlNode>, first: i64, body: bool, fields: ptr<BrowserSearchFields>) -> i64:
    let at: i64 = first
    while at >= 0:
        let node: ptr<HtmlNode> = &nodes[at]
        let status: i64 = 0
        if node.kind == HTML_TEXT_NODE and body:
            status = browser_search_append_node(source, size, node, &fields.body)
        elif node.kind == HTML_ELEMENT and not html_name_in(source, node.name_start, node.name_length, "script style template noscript iframe noembed noframes svg math"):
            if html_name_equal(source, node, "title"):
                if fields.title.len == 0 and node.first_child >= 0:
                    status = browser_search_append_node(source, size, &nodes[node.first_child], &fields.title)
            else:
                let content: bool = body and not html_name_equal(source, node, "head")
                let split: bool = content and html_name_in(source, node.name_start, node.name_length, "address article aside blockquote br caption dd details div dl dt fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hr li main nav ol p pre section summary table tbody td th thead tr ul")
                if split: status = browser_search_break(&fields.body)
                if status == 0 and node.first_child >= 0:
                    status = browser_search_collect(source, size, nodes, node.first_child, content, fields)
                if status == 0 and split: status = browser_search_break(&fields.body)
        if status < 0: return status
        at = node.next_sibling
    return 0

unsafe fn browser_search_extract(source: string, size: i64, fields: ptr<BrowserSearchFields>) -> i64:
    let dom: ptr<BrowserSearchDom> = mmap(sizeof(BrowserSearchDom)) as ptr<BrowserSearchDom>
    if (dom as i64) < 0: return dom as i64
    defer munmap(dom as ptr<char>, sizeof(BrowserSearchDom))
    let nodes: ptr<HtmlNode> = &dom.nodes[0]
    let n: i64 = html_parse(source, nodes, 8192, &dom.attributes[0], 16384)
    if n < 0: return n
    return browser_search_collect(source, size, nodes, nodes[0].first_child, true, fields)
