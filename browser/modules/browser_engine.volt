# Shared interaction helpers for the VOLT-owned browser.
use bytes
use html
use css
use utf8
use buffer
use browser_js
use browser_layout

const BROWSER_ENGINE_VIEW_WIDTH: i64 = 640
const BROWSER_ENGINE_VIEW_HEIGHT: i64 = 480
const BROWSER_TOOLBAR_HEIGHT: i64 = 56
const BROWSER_VIEW_HEIGHT: i64 = BROWSER_ENGINE_VIEW_HEIGHT - BROWSER_TOOLBAR_HEIGHT
const BROWSER_ADDRESS_LIMIT: i64 = 8192
const BROWSER_HISTORY_LIMIT: i64 = 32
const BROWSER_CANVAS_COLOR: i64 = 0xffffff

struct BrowserViewport:
    width: i64
    height: i64

struct BrowserPage:
    source: string
    source_buffer: ptr<ByteBuffer>
    nodes: ptr<HtmlNode>
    attributes: ptr<HtmlAttribute>
    node_count: i64
    styles: ptr<CssResolvedStyle>
    boxes: ptr<CssLayoutBox>
    fragments: ptr<CssFlowFragment>
    fragment_count: i64
    flow_text: ptr<char>
    text_length: i64
    document_height: i64
    layout_width: i64
    layout_height: i64
    styled_nodes: i64
    storage: ptr<BrowserPageStorage>
    url: string
    resource_length: i64
    address: [8193]char
    scripts_enabled: bool
    visual: bool

struct BrowserPageStorage:
    nodes: Buffer<HtmlNode>
    attributes: Buffer<HtmlAttribute>
    styles: Buffer<CssResolvedStyle>
    boxes: Buffer<CssLayoutBox>
    fragments: Buffer<CssFlowFragment>
    text: Buffer<char>
    js: BrowserJs
    visual: BrowserVisual
    youtube_node: i64
    youtube_media: [8193]char

unsafe fn browser_page_allocate(page: ptr<BrowserPage>) -> ptr<BrowserPageStorage>:
    let storage: ptr<BrowserPageStorage> = mmap(sizeof(BrowserPageStorage)) as ptr<BrowserPageStorage>
    if (storage as i64) <= 0: return 0 as ptr<BrowserPageStorage>
    page.storage = storage
    return storage

unsafe fn browser_page_free(storage: ptr<BrowserPageStorage>):
    if storage == (0 as ptr<BrowserPageStorage>): return
    browser_js_close(&storage.js)
    browser_visual_free(&storage.visual)
    buffer_free(&storage.text)
    buffer_free(&storage.fragments)
    buffer_free(&storage.boxes)
    buffer_free(&storage.styles)
    buffer_free(&storage.attributes)
    buffer_free(&storage.nodes)
    munmap(storage as ptr<char>, sizeof(BrowserPageStorage))

unsafe fn browser_copy_address(destination: ptr<char>, address: string) -> i64:
    let length: i64 = __volt_strlen(address)
    if length > BROWSER_ADDRESS_LIMIT: return -90
    let source: ptr<char> = address as ptr<char>
    let i: i64 = 0
    while i < length:
        destination[i] = source[i]
        i += 1
    destination[length] = 0 as char
    return length

unsafe fn browser_fragment_start(address: string) -> i64:
    let p: ptr<char> = address as ptr<char>
    let end: i64 = 0
    while p[end] != 0 and p[end] != '#': end += 1
    return end

unsafe fn browser_find_anchor(page: ptr<BrowserPage>, name: string) -> i64:
    let decoded: [8193]char
    let source: ptr<char> = page.source as ptr<char>
    let source_length: i64 = __volt_strlen(page.source)
    let i: i64 = 1
    while i < page.node_count:
        let node: ptr<HtmlNode> = &page.nodes[i]
        if node.kind == HTML_ELEMENT and not page.boxes[i].hidden:
            let index: i64 = css_find_html_attribute(page.source, node, page.attributes, "id")
            if index < 0 and html_name_equal(page.source, node, "a"):
                index = css_find_html_attribute(page.source, node, page.attributes, "name")
            if index >= 0:
                let attr: ptr<HtmlAttribute> = &page.attributes[index]
                if attr.has_value and html_decode_range(source, source_length, attr.value_start, attr.value_length, &decoded[0], 8193) > 0:
                    if (&decoded[0]) as string == name: return page.boxes[i].y
        i += 1
    if name == "top": return 0
    return -1

struct BrowserHistory:
    addresses: [32][8193]char
    resource_lengths: [32]i64
    first: i64
    count: i64
    current: i64

unsafe fn browser_history_init(history: ptr<BrowserHistory>):
    history.first = 0
    history.count = 0
    history.current = -1

unsafe fn browser_history_at(history: ptr<BrowserHistory>, index: i64) -> string:
    if index < 0 or index >= history.count: return ""
    let slot: i64 = (history.first + index) % BROWSER_HISTORY_LIMIT
    return (&history.addresses[slot][0]) as string

unsafe fn browser_history_resource_length(history: ptr<BrowserHistory>, index: i64) -> i64:
    if index < 0 or index >= history.count: return -1
    return history.resource_lengths[(history.first + index) % BROWSER_HISTORY_LIMIT]

unsafe fn browser_history_store(history: ptr<BrowserHistory>, index: i64, address: string, resource_length: i64):
    if index < 0:
        if browser_history_at(history, history.current) == address and browser_history_resource_length(history, history.current) == resource_length: return
        if history.current == BROWSER_HISTORY_LIMIT - 1:
            history.first = (history.first + 1) % BROWSER_HISTORY_LIMIT
        else:
            history.current += 1
        history.count = history.current + 1
    else:
        history.current = index
    let slot: i64 = (history.first + history.current) % BROWSER_HISTORY_LIMIT
    browser_copy_address(&history.addresses[slot][0], address)
    history.resource_lengths[slot] = resource_length

unsafe fn browser_anchor_for_node(source: string, nodes: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>, node_count: i64, node_index: i64, url_out: ptr<char>) -> i64:
    if source == "" or nodes == (0 as ptr<HtmlNode>) or attributes == (0 as ptr<HtmlAttribute>) or node_count < 1 or node_count > HTML_NODE_LIMIT or node_index < 0 or node_index >= node_count: return -22
    let current: i64 = node_index
    let steps: i64 = 0
    while current > 0 and steps < 128:
        let parent: i64 = nodes[current].parent
        if parent < 0 or parent >= current or parent >= node_count: return -22
        if nodes[current].kind == HTML_ELEMENT and html_name_equal(source, &nodes[current], "a"):
            let start: i64 = nodes[current].attribute_start
            let count: i64 = nodes[current].attribute_count
            if start < 0 or count < 0 or start > HTML_ATTRIBUTE_LIMIT or count > HTML_ATTRIBUTE_LIMIT - start: return -22
            let a: i64 = start
            while a < start + count:
                if attributes[a].owner != current: return -22
                if html_attribute_name_equal(source, &attributes[a], "href"):
                    return html_decode_attribute(source, &attributes[a], url_out, BROWSER_ADDRESS_LIMIT + 1)
                a += 1
            return -22
        current = parent
        steps += 1
    return -22

# Writes a decoded href to a caller-owned buffer of BROWSER_ADDRESS_LIMIT + 1 bytes.
unsafe fn browser_hit_test(page: ptr<BrowserPage>, scroll_y: i64, x: i64, y: i64, url_out: ptr<char>) -> i64:
    return browser_hit_test_view(page, scroll_y, x, y, BROWSER_ENGINE_VIEW_HEIGHT, url_out)

unsafe fn browser_hit_test_view(page: ptr<BrowserPage>, scroll_y: i64, x: i64, y: i64, height: i64, url_out: ptr<char>) -> i64:
    if url_out == (0 as ptr<char>): return -22
    return browser_find_hit(page, scroll_y, x, y, height, url_out)

unsafe fn browser_find_hit(page: ptr<BrowserPage>, scroll_y: i64, x: i64, y: i64, height: i64, url_out: ptr<char>) -> i64:
    if page == (0 as ptr<BrowserPage>) or x < 0 or y < 0 or y >= height or scroll_y < 0 or scroll_y > page.document_height: return -22
    let width: i64 = page.layout_width
    if width < 1: width = BROWSER_ENGINE_VIEW_WIDTH
    if x >= width: return -22
    if page.fragments == (0 as ptr<CssFlowFragment>) or page.flow_text == (0 as ptr<char>) or page.boxes == (0 as ptr<CssLayoutBox>): return -22
    if page.node_count < 1 or page.node_count > HTML_NODE_LIMIT: return -22
    if page.fragment_count < 0 or page.fragment_count > CSS_FRAGMENT_LIMIT or page.text_length < 0 or page.text_length > HTML_DOCUMENT_LIMIT: return -22
    if y > 9223372036854775807 - scroll_y: return -22
    let document_y: i64 = y + scroll_y
    let i: i64 = page.fragment_count - 1
    while i >= 0:
        let fragment: ptr<CssFlowFragment> = &page.fragments[i]
        if fragment.node_index < 0 or fragment.node_index >= page.node_count or fragment.byte_start < 0 or fragment.byte_length < 0 or fragment.byte_start > page.text_length or fragment.byte_length > page.text_length - fragment.byte_start: return -22
        if (fragment.byte_length > 0 or fragment.advance > 0) and fragment.clip_width > 0 and fragment.clip_height > 0 and fragment.x >= 0 and fragment.y >= 0 and fragment.clip_x >= 0 and fragment.clip_y >= 0:
            let line: i64 = fragment.line_height
            if line == 0: line = 16
            if x >= fragment.x and x >= fragment.clip_x and x - fragment.clip_x < fragment.clip_width and document_y >= fragment.y and document_y - fragment.y < line and document_y >= fragment.clip_y and document_y - fragment.clip_y < fragment.clip_height and not page.boxes[fragment.node_index].hidden:
                let advance: i64 = fragment.advance
                if fragment.line_height == 0: advance = utf8_count(page.flow_text + fragment.byte_start, fragment.byte_length) * 6
                if x - fragment.x < advance:
                    # A null output requests the topmost node instead of a link.
                    if url_out == (0 as ptr<char>): return fragment.node_index
                    let resolved: i64 = browser_anchor_for_node(page.source, page.nodes, page.attributes, page.node_count, fragment.node_index, url_out)
                    if resolved > 0: return resolved
        i -= 1
    if page.visual:
        i = page.node_count - 1
        while i > 0:
            let box: ptr<CssLayoutBox> = &page.boxes[i]
            if not box.hidden and x >= box.x and x - box.x < box.width and document_y >= box.y and document_y - box.y < box.height and html_name_equal(page.source, &page.nodes[i], "a"):
                if url_out == (0 as ptr<char>): return i
                let resolved: i64 = browser_anchor_for_node(page.source, page.nodes, page.attributes, page.node_count, i, url_out)
                if resolved > 0: return resolved
            i -= 1
    return -1
