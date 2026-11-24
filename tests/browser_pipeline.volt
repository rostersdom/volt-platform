use html
use css

fn main() -> i64:
    let source: string = "<style>p { color: #246; background: white; margin: 4px; display: block; }</style><body><p><span>Hello &amp; VOLT 123</span></p></body>"
    let nodes: [16]HtmlNode
    let attributes: [16]HtmlAttribute
    let node_count: i64 = 0
    unsafe: node_count = html_parse(source, &nodes[0], 16, &attributes[0], 16)
    if node_count != 7:
        panic("browser pipeline DOM")

    let stylesheet: [256]char
    let defaults: string = "style, script { display: none; }"
    let default_length: i64 = __volt_strlen(defaults)
    let i: i64 = 0
    unsafe:
        while i < default_length:
            stylesheet[i] = (defaults as ptr<char>)[i]
            i += 1
    let inline_length: i64 = 0
    unsafe: inline_length = css_collect_inline_styles(source, &nodes[0], node_count, &stylesheet[default_length], 256 - default_length)
    if inline_length <= 0:
        panic("browser pipeline inline CSS")
    let css_text: string
    unsafe: css_text = (&stylesheet[0]) as string

    let rules: [4]CssRule
    let selectors: [8]CssSelector
    let declarations: [8]CssDeclaration
    let buffers: CssBuffers = CssBuffers(&rules[0], 4, &selectors[0], 8, &declarations[0], 8)
    let rule_count: i64 = 0
    unsafe: rule_count = css_parse(css_text, &buffers)
    if rule_count != 2:
        panic("browser pipeline CSS rules")
    let selector_count: i64 = 0
    let declaration_count: i64 = 0
    i = 0
    while i < rule_count:
        selector_count += rules[i].selector_count
        declaration_count += rules[i].declaration_count
        i += 1

    let styles: [16]CssResolvedStyle
    let boxes: [16]CssLayoutBox
    let fragments: [128]CssFlowFragment
    let flow_text: [4096]char
    let cascade: CssCascadeContext = CssCascadeContext(css_text, &rules[0], rule_count, &selectors[0], selector_count, &declarations[0], declaration_count, source, &nodes[0], &attributes[0], node_count, 0)
    let layout: CssLayoutContext = CssLayoutContext(&nodes[0], node_count, &styles[0], node_count, 40, &boxes[0], 16, &fragments[0], 128, 0, &flow_text[0], 4096, 0, source, true)
    let document: CssDocumentContext = CssDocumentContext(&cascade, &styles[0], 16, &layout)
    unsafe:
        match css_prepare_document(&document):
            Ok(count):
                if count != node_count: panic("browser pipeline layout count")
            Err(error): panic("browser pipeline document preparation")

    if styles[1].display != 0 or styles[4].display != 2 or styles[4].color_rgb != 2245734 or styles[4].background_rgb != 16777215 or styles[4].margin_px != 4 or styles[6].color_rgb != 2245734:
        panic("browser pipeline computed style")
    if not boxes[1].hidden or not boxes[2].hidden or boxes[3].hidden or boxes[4].hidden or boxes[5].hidden or boxes[6].hidden:
        panic("browser pipeline visibility")
    if boxes[4].x != 4 or boxes[4].y != 4 or boxes[4].width != 32 or boxes[4].height < 64:
        panic("browser pipeline wrapped paragraph box")
    if layout.fragment_count < 3 or fragments[0].x != 4 or fragments[0].y != 4 or fragments[2].y <= fragments[0].y:
        panic("browser pipeline word wrapping")
    if fragments[0].color_rgb != 2245734:
        panic("browser pipeline inherited text color")
    let decoded: [64]char
    let decoded_length: i64 = 0
    unsafe: decoded_length = html_decode_node_text(source, &nodes[6], &decoded[0], 64)
    if decoded_length != 16 or decoded[6] != '&':
        panic("browser pipeline text decode")
    layout.viewport_width = 357913941
    unsafe:
        match css_layout_blocks(&layout):
            Ok(_):
                if boxes[0].width != 357913941: panic("browser pipeline maximum viewport width")
            Err(_): panic("browser pipeline maximum viewport rejected")
    let boundary_fragment_count: i64 = layout.fragment_count
    layout.viewport_width = 2147483647
    unsafe:
        match css_layout_blocks(&layout):
            Ok(_): panic("browser pipeline unsafe viewport accepted")
            Err(_):
                if boxes[0].width != 357913941 or layout.fragment_count != boundary_fragment_count:
                    panic("browser pipeline unsafe viewport rejection mutated layout")
    layout.viewport_width = 357913941
    unsafe:
        match css_layout_blocks(&layout):
            Ok(_):
                if boxes[0].width != 357913941: panic("browser pipeline maximum viewport width")
            Err(_): panic("browser pipeline maximum viewport rejected")
    let saved_width: i64 = boxes[0].width
    let saved_height: i64 = boxes[0].height
    let saved_fragment_count: i64 = layout.fragment_count
    layout.viewport_width = 357913942
    unsafe:
        match css_layout_blocks(&layout):
            Ok(_): panic("browser pipeline overflow viewport accepted")
            Err(_):
                if boxes[0].width != saved_width or boxes[0].height != saved_height or layout.fragment_count != saved_fragment_count:
                    panic("browser pipeline overflow rejection mutated layout")
    # A directly supplied cursor at the signed limit must fail before emission.
    let boundary_cursor: CssFlowCursor = CssFlowCursor(9223372036854775801, 0, 357913941, 9223372036854775801, 0, 16, true, true)
    let cursor_fragment_count: i64 = layout.fragment_count
    let cursor_text_length: i64 = layout.text_length
    unsafe:
        let decoded_word: [2]char
        decoded_word[0] = 'Z'
        let emit_result: i64 = css_emit_word(&layout, &boundary_cursor, 6, &decoded_word[0], 0, 1)
        if emit_result != -22 or layout.fragment_count != cursor_fragment_count or layout.text_length != cursor_text_length or boundary_cursor.x != 9223372036854775801:
            panic("browser pipeline cursor overflow rejection mutated layout")
    # Pending whitespace alone fits both capacities, but the word does not; failure must be atomic.
    layout.fragment_count = 0
    layout.text_length = 0
    layout.fragment_capacity = 1
    layout.text_capacity = 1
    let capacity_cursor: CssFlowCursor = CssFlowCursor(0, 0, 40, 6, 0, 16, true, true)
    let capacity_text_before: i64 = layout.text_length
    let capacity_fragments_before: i64 = layout.fragment_count
    unsafe:
        let decoded_word: [2]char
        decoded_word[0] = 'Z'
        let emit_capacity: i64 = css_emit_word(&layout, &capacity_cursor, 6, &decoded_word[0], 0, 1)
        if emit_capacity != -7 or layout.fragment_count != capacity_fragments_before or layout.text_length != capacity_text_before or capacity_cursor.x != 6 or not capacity_cursor.pending_space or not capacity_cursor.occupied:
            panic("browser pipeline pending space capacity rejection mutated state")
    layout.fragment_capacity = 128
    layout.text_capacity = 4096
    boundary_cursor.width = 357913942
    boundary_cursor.x = 0
    boundary_cursor.pending_space = false
    boundary_cursor.occupied = false
    unsafe:
        let decoded_word: [2]char
        decoded_word[0] = 'Z'
        if css_emit_word(&layout, &boundary_cursor, 6, &decoded_word[0], 0, 1) != -22:
            panic("browser pipeline excessive flow width accepted")
    print("browser pipeline ok", node_count - 1, rule_count)
    return 0
