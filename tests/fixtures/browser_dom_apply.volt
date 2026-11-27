use browser_controller
use browser_dom
use bytes
use css
use html

fn main() -> i64:
    let html_text: string = "<div id=\"out\"></div>"
    let page_source: ByteBuffer
    let spare_source: ByteBuffer
    let page: BrowserPage
    let spare: BrowserPage
    unsafe:
        bytes_init(&page_source)
        bytes_init(&spare_source)
        defer bytes_free(&page_source)
        defer bytes_free(&spare_source)
        let length: i64 = __volt_strlen(html_text)
        if bytes_reserve(&page_source, length + 1) < 0: return 1
        let text: ptr<char> = page_source.data as ptr<char>
        let i: i64 = 0
        while i <= length:
            text[i] = (html_text as ptr<char>)[i]
            i += 1
        page_source.len = length + 1
        if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
        defer browser_page_free(page.storage)
        if browser_page_allocate(&spare) == (0 as ptr<BrowserPageStorage>): return 1
        defer browser_page_free(spare.storage)
        page.visual = true
        if browser_prepare_document(&page_source, "test.html", &page, 640) < 0: return 1
        let out: i64 = -1
        i = 1
        while i < page.node_count:
            let attr: i64 = css_find_html_attribute(page.source, &page.nodes[i], page.attributes, "id")
            if attr >= 0 and page.attributes[attr].has_value:
                let value: [16]char
                let size: i64 = html_decode_range(page.source as ptr<char>, __volt_strlen(page.source), page.attributes[attr].value_start, page.attributes[attr].value_length, &value[0], 16)
                if size == 3 and value[0] == 'o' and value[1] == 'u' and value[2] == 't': out = i
            i += 1
        if out < 0: return 1
        let fragment: string = "<div class=\"made\">DOM</div>"
        let fragment_length: i64 = __volt_strlen(fragment)
        let dom: ByteBuffer
        bytes_init(&dom)
        defer bytes_free(&dom)
        if bytes_reserve(&dom, BROWSER_DOM_OP_HEADER_BYTES + fragment_length) < 0: return 1
        let head: ptr<i64> = dom.data as ptr<i64>
        head[0] = BROWSER_DOM_OP_APPEND
        head[1] = BROWSER_DOM_PARENT_NODE
        head[2] = out
        head[3] = fragment_length
        let target: ptr<char> = (dom.data + BROWSER_DOM_OP_HEADER_BYTES) as ptr<char>
        i = 0
        while i < fragment_length:
            target[i] = (fragment as ptr<char>)[i]
            i += 1
        dom.len = BROWSER_DOM_OP_HEADER_BYTES + fragment_length
        if browser_dom_apply(&page, &dom, 0 as ptr<ptr<CssTextOverrides>>) < 0: return 1
        if browser_relayout(&page, &spare, BrowserViewport(640, 480), 0 as ptr<CssTextOverrides>) < 0: return 1
        put_str("text ")
        i = 0
        while i < page.text_length:
            put_char(page.flow_text[i])
            i += 1
        nl()
        put_str("nodes ")
        put_int(page.node_count)
        nl()
    return 0
