use browser_controller
use process

# Consume an actual result page, resolve its first link, and load that local source.
unsafe fn search_link_check(results: string, expected: string) -> i64:
    let source: ByteBuffer
    bytes_init(&source)
    defer bytes_free(&source)
    if bytes_read_file(&source, results) < 0 or bytes_push(&source, 0 as u8) < 0: return 1
    let html: string = source.data as ptr<char> as string
    let nodes: [64]HtmlNode
    let attributes: [32]HtmlAttribute
    let count: i64 = html_parse(html, &nodes[0], 64, &attributes[0], 32)
    if count < 1: return 2
    for i in 1..count:
        if nodes[i].kind != HTML_ELEMENT or not html_name_equal(html, &nodes[i], "a"): continue
        let attr: i64 = css_find_html_attribute(html, &nodes[i], &attributes[0], "href")
        if attr < 0: return 3
        let href: [8193]char
        if html_decode_attribute(html, &attributes[attr], &href[0], 8193) <= 0: return 4
        let page: BrowserPage
        page.url = results
        page.resource_length = __volt_strlen(results)
        let path: [8193]char
        let size: i64 = -1
        if browser_resolve_href(&page, (&href[0]) as string, &path[0], &size) <= 0: return 5
        if (&path[0]) as string != expected or size != __volt_strlen(expected): return 6
        let target: BrowserSource
        let transfer: HttpTransfer = HttpTransfer(http_deadline_after(1000), 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
        if browser_fetch_source((&path[0]) as string, &source, &target, size, &transfer) != 0: return 7
        print("browser search local link ok")
        return 0
    return 8

fn main() -> i64:
    let results: string = ""
    let expected: string = ""
    match arg_at(1):
        Ok(value): results = value
        Err(_): return 9
    match arg_at(2):
        Ok(value): expected = value
        Err(_): return 9
    unsafe: return search_link_check(results, expected)
