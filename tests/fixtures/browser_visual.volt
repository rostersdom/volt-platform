use browser_controller

unsafe fn visual_link_node(page: ptr<BrowserPage>, id: string) -> i64:
    let i: i64 = 1
    while i < page.node_count:
        let attr: i64 = css_find_html_attribute(page.source, &page.nodes[i], page.attributes, "id")
        if attr >= 0 and css_range_equal(page.source, page.attributes[attr].value_start, page.attributes[attr].value_length, id): return i
        i += 1
    panic("missing visual fixture node")
    return -1

unsafe fn visual_check(path: string) -> i64:
    let page: BrowserPage
    let spare: BrowserPage
    let data: ByteBuffer
    defer bytes_free(&data)
    if browser_page_allocate(&page) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(page.storage)
    if browser_page_allocate(&spare) == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(spare.storage)
    page.visual = true
    let deadline: i64 = http_deadline_after(4000)
    let network: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
    if browser_load_candidate(&page, &data, path, -1, BrowserViewport(640, 480), &network) != 0: panic("visual page load failed")
    let first: i64 = visual_link_node(&page, "first")
    let second: i64 = visual_link_node(&page, "second")
    if page.boxes[first].y != page.boxes[second].y or page.boxes[first].x >= page.boxes[second].x: panic("wide grid placement")
    let styles: ptr<BrowserStyle> = buffer_data(&page.storage.visual.styles)
    if styles[second].background != 0x840020: panic("initial cascade")
    let target: [8193]char
    if browser_hit_test(&page, 0, page.boxes[second].x + 2, page.boxes[second].y + 2, &target[0]) <= 0 or (&target[0]) as string != "#second": panic("wide link hit")
    if browser_reflow_page(&page, &spare, BrowserViewport(440, 480)) != 0: panic("responsive reflow")
    if page.boxes[first].x != page.boxes[second].x or page.boxes[second].y <= page.boxes[first].y: panic("narrow grid placement")
    styles = buffer_data(&page.storage.visual.styles)
    if styles[second].background != 0x005580: panic("media query did not recascade")
    if browser_hit_test(&page, 0, page.boxes[second].x + 2, page.boxes[second].y + 2, &target[0]) <= 0 or (&target[0]) as string != "#second": panic("narrow link hit")
    if browser_reflow_page(&page, &spare, BrowserViewport(460, 480)) != 0: panic("same-media reflow")
    if styles != buffer_data(&page.storage.visual.styles): panic("unnecessary style replacement")
    if browser_reflow_page(&page, &spare, BrowserViewport(640, 480)) != 0: panic("wide reflow")
    if page.boxes[first].y != page.boxes[second].y: panic("wide placement not restored")
    let viewport_fixture: string = "<style>body{margin:0}.space{background:#1a334d}</style><div id='spacer' class='space' style='width:50vw;height:25vh'></div>"
    data.len = 0
    if http_append_text(&data, viewport_fixture) < 0 or bytes_push(&data, 0 as u8) < 0: return 1
    if browser_prepare_document(&data, "viewport.html", &page, 640) != 0: panic("viewport length layout failed")
    let spacer: i64 = visual_link_node(&page, "spacer")
    if page.boxes[spacer].width != 320 or page.boxes[spacer].height != 120: panic("viewport units did not resolve")
    if browser_reflow_page(&page, &spare, BrowserViewport(640, 320)) != 0: panic("height-only reflow failed")
    if page.boxes[spacer].height != 80 or page.boxes[spacer].width != 320: panic("viewport length did not follow height")
    return 0

fn main() -> i64:
    match arg_at(1):
        Ok(path):
            unsafe: return visual_check(path)
        Err(error): return 1
    return 1
