use browser_engine
use html
use css
use bytes

fn main() -> i64:
    unsafe:
        let source: string = "<body><a href=\"http://example.test/next\">X</a></body>"
        let nodes: [16]HtmlNode
        let attributes: [16]HtmlAttribute
        let count: i64 = html_parse(source, &nodes[0], 16, &attributes[0], 16)
        if count < 4: return 1
        let fragments: [4]CssFlowFragment
        fragments[0].node_index = count - 1
        fragments[0].byte_start = 0
        fragments[0].byte_length = 1
        fragments[0].x = 10
        fragments[0].y = 20
        fragments[0].clip_x = 0
        fragments[0].clip_y = 0
        fragments[0].clip_width = 640
        fragments[0].clip_height = 480
        let boxes: [16]CssLayoutBox
        let page: BrowserPage
        page.source = source
        page.nodes = &nodes[0]
        page.attributes = &attributes[0]
        page.node_count = count
        page.fragments = &fragments[0]
        page.fragment_count = 1
        page.flow_text = "X" as ptr<char>
        page.text_length = 1
        page.boxes = &boxes[0]
        page.document_height = 480
        let url: [8193]char
        if browser_hit_test(&page, 0, 11, 21, &url[0]) <= 0: return 2
        if url[0] != 'h' or url[7] != 'e': return 3
        if browser_hit_test(&page, 0, 9, 21, &url[0]) != -1: return 4
    return 0
