use html
use css
use paint
use utf8

fn main() -> i64:
    let source: string = "<p>X</p>"
    let nodes: [8]HtmlNode
    let attributes: [8]HtmlAttribute
    let count: i64 = 0
    unsafe: count = html_parse(source, &nodes[0], 8, &attributes[0], 8)
    if count != 3: panic("paint fixture parse")

    let styles: [8]CssResolvedStyle
    let boxes: [8]CssLayoutBox
    let i: i64 = 0
    while i < count:
        styles[i] = CssResolvedStyle(0, -1, 0, 2)
        boxes[i] = CssLayoutBox(0, 0, 8, 12, false)
        i += 1
    styles[1].background_rgb = 0x123456
    boxes[1] = CssLayoutBox(1, 1, 5, 9, false)
    boxes[2] = CssLayoutBox(1, 1, 5, 9, false)

    let storage: [60]u32
    let original: [60]u32
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        original[i] = 0xdeadbeef as u32
        i += 1
    let surface: PaintSurface = PaintSurface(&storage[0], 8, 6, 10, 60)
    let result: i64 = 0
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &surface)
    if result != PAINT_OK: panic("paint status")
    if storage[0] != 0xff000000 as u32 or storage[11] != 0xff123456 as u32:
        panic("paint background pixels")
    if storage[16] != 0xff000000 as u32 or storage[11] != 0xff123456 as u32 or storage[18] != 0xff000000 as u32:
        panic("paint clipped fill and stride")
    # X top-row corners are ink; the center pixel remains unpainted.
    if storage[51] != 0xff000000 as u32 or storage[55] != 0xff000000 as u32:
        panic("paint X corner glyph pixels")
    if storage[53] != 0xff123456 as u32:
        panic("paint X center background pixel")
    # Lowercase maps deterministically; punctuation and replacement rows are fixed.
    let lowercase_row: i64 = 0
    let uppercase_row: i64 = 0
    let punctuation_row: i64 = 0
    let fallback_row: i64 = 0
    let unsupported_row: i64 = 0
    let unsupported_mid_row: i64 = 0
    unsafe:
        lowercase_row = paint_glyph_row(120, 0)
        uppercase_row = paint_glyph_row(88, 0)
        punctuation_row = paint_glyph_row(46, 5)
        fallback_row = paint_glyph_row(63, 0)
        unsupported_row = paint_glyph_row(35, 0)
        unsupported_mid_row = paint_glyph_row(35, 3)
    if lowercase_row != uppercase_row or punctuation_row != 12 or fallback_row != 14 or unsupported_row != fallback_row or unsupported_mid_row != 2:
        panic("paint lowercase, punctuation, replacement glyph rows")
    unsafe:
        if paint_glyph_row(60, 3) != 8 or paint_glyph_row(62, 3) != 2: panic("paint distinct navigation arrows")
        if paint_glyph_row(47, 0) != 1 or paint_glyph_row(58, 2) != 4: panic("paint URL punctuation")
        if paint_glyph_row(0x042f, 0) != 15 or paint_glyph_row(0x0451, 0) != 10: panic("paint Cyrillic glyphs")
        let unicode: ptr<char> = "Яё🙂" as ptr<char>
        let position: i64 = 0
        if utf8_next(unicode, &position, 8) != 0x042f or position != 2: panic("UTF-8 Cyrillic")
        if utf8_next(unicode, &position, 8) != 0x0451 or position != 4: panic("UTF-8 Cyrillic lowercase")
        if utf8_next(unicode, &position, 8) != 0x1f642 or position != 8: panic("UTF-8 four-byte scalar")
        if utf8_next(unicode, &position, 8) != -1: panic("UTF-8 end of input")
        let truncated: [2]char = [0xe2 as char, 0x82 as char]
        position = 0
        if utf8_next(&truncated[0], &position, 2) != 0xfffd or position != 1: panic("UTF-8 truncated scalar")

    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    let bad: PaintSurface = PaintSurface(&storage[0], 8, 6, 7, 60)
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &bad)
    i = 0
    while i < 60:
        if storage[i] != original[i]: panic("paint invalid stride changed backing memory")
        i += 1
    if result != PAINT_INVALID: panic("paint invalid stride accepted")
    bad = PaintSurface(&storage[0], 8, 6, 10, 59)
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &bad)
    i = 0
    while i < 60:
        if storage[i] != original[i]: panic("paint short capacity changed backing memory")
        i += 1
    if result != PAINT_INVALID: panic("paint short capacity accepted")
    bad = PaintSurface(&storage[0], 0, 6, 10, 60)
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &bad)
    i = 0
    while i < 60:
        if storage[i] != original[i]: panic("paint invalid dimensions changed backing memory")
        i += 1
    if result != PAINT_INVALID: panic("paint invalid dimensions accepted")

    let extreme: PaintSurface = PaintSurface(&storage[0], 8, 6, 10, 60)
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &extreme)
    if result != PAINT_OK: panic("paint order fixture status")
    if storage[11] != 0xff123456 as u32 or storage[53] != 0xff123456 as u32:
        panic("paint DOM preorder background then descendant text")
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe:
        paint_fill(&extreme, -9223372036854775807 - 1, 0, 9223372036854775807, 2, 0xffffff)
        paint_fill(&extreme, 0, -9223372036854775807 - 1, 2, 9223372036854775807, 0xffffff)
    boxes[1] = CssLayoutBox(0, 0, 0, 0, true)
    boxes[2] = CssLayoutBox(9223372036854775807 - 8, 0, 8, 12, false)
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &extreme)
    if result != PAINT_OK: panic("paint one-pixel text box status")
    i = 0
    while i < 60:
        if storage[i] != 0xff000000 as u32:
            panic("paint extreme positive text box escaped viewport")
        i += 1

    let null_surface: PaintSurface = PaintSurface(0 as ptr<u32>, 8, 6, 8, 48)
    unsafe: result = paint_document(source, &nodes[0], &styles[0], &boxes[0], count, &null_surface)
    if result != PAINT_INVALID: panic("paint null framebuffer rejected")
    unsafe:
        result = paint_document(source, 0 as ptr<HtmlNode>, &styles[0], &boxes[0], count, &extreme)
    if result != PAINT_INVALID: panic("paint null nodes rejected")
    unsafe:
        result = paint_document(source, &nodes[0], 0 as ptr<CssResolvedStyle>, &boxes[0], count, &extreme)
    if result != PAINT_INVALID: panic("paint null styles rejected")
    unsafe:
        result = paint_document(source, &nodes[0], &styles[0], 0 as ptr<CssLayoutBox>, count, &extreme)
    if result != PAINT_INVALID: panic("paint null boxes rejected")
    let flow_text: [16]char
    flow_text[0] = 'A'
    flow_text[1] = 'B'
    let flow_fragments: [2]CssFlowFragment
    flow_fragments[0] = CssFlowFragment(2, 0, 1, 0, 0, 0xffffff, 0, 0, 5, 12, 0, 0, 0)
    flow_fragments[1] = CssFlowFragment(2, 1, 1, 6, 0, 0xffffff, 0, 0, 5, 12, 0, 0, 0)
    boxes[1] = CssLayoutBox(0, 0, 8, 12, true)
    boxes[2] = CssLayoutBox(0, 0, 8, 12, false)
    let flow: PaintFlowContext = PaintFlowContext(&flow_fragments[0], 2, &flow_text[0], 2)
    let flow_context: PaintDocumentContext = PaintDocumentContext(source, &nodes[0], &styles[0], &boxes[0], count, &flow, &extreme)
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe: result = paint_document_fragments(&flow_context)
    if result != PAINT_OK or storage[43] != 0xffffffff as u32:
        panic("paint flow clipped glyph")
    if storage[57] != 0xff000000 as u32:
        panic("paint flow second fragment clipped to first line")
    flow_text[1] = ' '
    flow_fragments[1].x = 6
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe: result = paint_document_fragments(&flow_context)
    if result != PAINT_OK or storage[43] != 0xffffffff as u32 or storage[49] != 0xff000000 as u32:
        panic("paint flow whitespace stays blank")
    flow_text[1] = 'B'
    flow_fragments[1].x = 6
    flow_fragments[1].byte_start = 2
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe: result = paint_document_fragments(&flow_context)
    if result != PAINT_INVALID:
        panic("paint invalid fragment preflight")
    i = 0
    while i < 60:
        if storage[i] != 0xdeadbeef as u32: panic("paint invalid fragments mutated surface")
        i += 1
    let inherited: PaintSurface = PaintSurface(&storage[0], 8, 6, 10, 60)
    let inherited_css: string = "p { color: #246; }"
    let rules: [2]CssRule
    let selectors: [2]CssSelector
    let declarations: [4]CssDeclaration
    let css_buffers: CssBuffers = CssBuffers(&rules[0], 2, &selectors[0], 2, &declarations[0], 4)
    let rule_count: i64 = 0
    unsafe: rule_count = css_parse(inherited_css, &css_buffers)
    if rule_count != 1: panic("paint inherited CSS parse")
    let inherited_fragments: [8]CssFlowFragment
    let inherited_text: [32]char
    let inherited_layout: CssLayoutContext = CssLayoutContext(&nodes[0], count, &styles[0], count, 8, &boxes[0], 8, &inherited_fragments[0], 8, 0, &inherited_text[0], 32, 0, source, true)
    let inherited_cascade: CssCascadeContext = CssCascadeContext(inherited_css, &rules[0], rule_count, &selectors[0], rules[0].selector_count, &declarations[0], rules[0].declaration_count, source, &nodes[0], &attributes[0], count, 0)
    let inherited_document: CssDocumentContext = CssDocumentContext(&inherited_cascade, &styles[0], 8, &inherited_layout)
    unsafe:
        match css_prepare_document(&inherited_document):
            Ok(_):
                if styles[1].color_rgb != 0x224466 or styles[2].color_rgb != 0x224466: panic("paint inherited cascade color")
            Err(_): panic("paint inherited CSS preparation")
    if inherited_layout.fragment_count != 1 or inherited_fragments[0].color_rgb != 0x224466:
        panic("paint inherited flow color")
    flow_text[0] = 'X'
    i = 0
    while i < 60:
        storage[i] = 0xff000000 as u32
        i += 1
    let inherited_flow: PaintFlowContext = PaintFlowContext(&inherited_fragments[0], inherited_layout.fragment_count, &inherited_text[0], inherited_layout.text_length)
    let inherited_context: PaintDocumentContext = PaintDocumentContext(source, &nodes[0], &styles[0], &boxes[0], count, &inherited_flow, &inherited)
    unsafe: result = paint_document_fragments(&inherited_context)
    if result != PAINT_OK or storage[40] != 0xff224466 as u32:
        panic("paint inherited text color exact pixel")

    # Reject a fragment color outside 24-bit RGB before framebuffer mutation.
    inherited_fragments[0].color_rgb = 16777216
    i = 0
    while i < 60:
        storage[i] = 0xdeadbeef as u32
        i += 1
    unsafe: result = paint_document_fragments(&inherited_context)
    if result != PAINT_INVALID: panic("paint invalid fragment color accepted")
    i = 0
    while i < 60:
        if storage[i] != 0xdeadbeef as u32: panic("paint invalid fragment color mutated surface")
        i += 1
    inherited_fragments[0].color_rgb = 0x224466

    # Child index precedes parent: document preparation must reject non-preorder trees.
    let reordered_nodes: [8]HtmlNode
    i = 0
    while i < count:
        reordered_nodes[i] = nodes[i]
        i += 1
    reordered_nodes[1].parent = 2
    let reordered_cascade: CssCascadeContext = CssCascadeContext(inherited_css, &rules[0], rule_count, &selectors[0], rules[0].selector_count, &declarations[0], rules[0].declaration_count, source, &reordered_nodes[0], &attributes[0], count, 0)
    let reordered_layout: CssLayoutContext = CssLayoutContext(&reordered_nodes[0], count, &styles[0], count, 8, &boxes[0], 8, &inherited_fragments[0], 8, 0, &inherited_text[0], 32, 0, source, true)
    let reordered_document: CssDocumentContext = CssDocumentContext(&reordered_cascade, &styles[0], 8, &reordered_layout)
    unsafe:
        match css_prepare_document(&reordered_document):
            Ok(_): panic("paint non-preorder parent accepted")
            Err(_):
                if reordered_layout.fragment_count != 0: panic("paint non-preorder parent emitted fragments")

    # Later overlapping block background must cover earlier text in DOM paint order.
    let overlap_source: string = "<body><p>X</p><p></p></body>"
    let overlap_nodes: [8]HtmlNode
    let overlap_attrs: [8]HtmlAttribute
    let overlap_count: i64 = 0
    unsafe: overlap_count = html_parse(overlap_source, &overlap_nodes[0], 8, &overlap_attrs[0], 8)
    let overlap_styles: [8]CssResolvedStyle
    let overlap_boxes: [8]CssLayoutBox
    let overlap_fragments: [8]CssFlowFragment
    let overlap_text: [32]char
    let overlap_layout: CssLayoutContext = CssLayoutContext(&overlap_nodes[0], overlap_count, &overlap_styles[0], overlap_count, 8, &overlap_boxes[0], 8, &overlap_fragments[0], 8, 0, &overlap_text[0], 32, 0, overlap_source, true)
    let overlap_stylesheet: string = "p { color: #246; background: #f00; display: block; }"
    let overlap_rules: [2]CssRule
    let overlap_selectors: [2]CssSelector
    let overlap_declarations: [4]CssDeclaration
    let overlap_css_buffers: CssBuffers = CssBuffers(&overlap_rules[0], 2, &overlap_selectors[0], 2, &overlap_declarations[0], 4)
    let overlap_rule_count: i64 = 0
    unsafe: overlap_rule_count = css_parse(overlap_stylesheet, &overlap_css_buffers)
    let overlap_cascade: CssCascadeContext = CssCascadeContext(overlap_stylesheet, &overlap_rules[0], overlap_rule_count, &overlap_selectors[0], overlap_rules[0].selector_count, &overlap_declarations[0], overlap_rules[0].declaration_count, overlap_source, &overlap_nodes[0], &overlap_attrs[0], overlap_count, 0)
    let overlap_document: CssDocumentContext = CssDocumentContext(&overlap_cascade, &overlap_styles[0], 8, &overlap_layout)
    unsafe:
        match css_prepare_document(&overlap_document):
            Ok(_):
                if overlap_layout.fragment_count != 1 or overlap_text[0] != 'X': panic("paint overlap layout fixture")
            Err(_): panic("paint overlap document preparation")
    # Translate the later positioned block over the earlier glyph after layout.
    if overlap_boxes[4].y <= overlap_boxes[2].y: panic("paint overlap blocks initially distinct")
    overlap_boxes[4].x = overlap_boxes[2].x
    overlap_boxes[4].y = overlap_boxes[2].y
    overlap_boxes[4].height = 16
    let overlap_flow: PaintFlowContext = PaintFlowContext(&overlap_fragments[0], overlap_layout.fragment_count, &overlap_text[0], overlap_layout.text_length)
    let overlap_surface: PaintSurface = PaintSurface(&storage[0], 8, 6, 10, 60)
    let overlap_context: PaintDocumentContext = PaintDocumentContext(overlap_source, &overlap_nodes[0], &overlap_styles[0], &overlap_boxes[0], overlap_count, &overlap_flow, &overlap_surface)
    i = 0
    while i < 60:
        storage[i] = 0xff000000 as u32
        i += 1
    unsafe: result = paint_document_fragments(&overlap_context)
    if result != PAINT_OK or storage[40] != 0xffff0000 as u32 or storage[10] != 0xffff0000 as u32:
        panic("paint later overlapping block covers earlier glyph pixel")
    unsafe:
        let scroll_source: string = "<p>X</p>"
        let scroll_nodes: [8]HtmlNode
        let scroll_attrs: [8]HtmlAttribute
        let scroll_count: i64 = html_parse(scroll_source, &scroll_nodes[0], 8, &scroll_attrs[0], 8)
        if scroll_count != 3: panic("scroll fixture parse")
        let scroll_styles: [8]CssResolvedStyle
        let scroll_boxes: [8]CssLayoutBox
        scroll_styles[1] = CssResolvedStyle(0, 0x112233, 0, 2)
        scroll_boxes[1] = CssLayoutBox(0, 0, 8, 12, false)
        scroll_boxes[2] = CssLayoutBox(1, 8, 5, 16, false)
        let scroll_fragments: [1]CssFlowFragment
        scroll_fragments[0] = CssFlowFragment(2, 0, 1, 1, 8, 0xff00ff, 1, 8, 5, 16, 0, 0, 0)
        let scroll_text: [1]char
        scroll_text[0] = 'X'
        let scroll_flow: PaintFlowContext = PaintFlowContext(&scroll_fragments[0], 1, &scroll_text[0], 1)
        let scroll_zero_pixels: [160]u32
        let scroll_zero_surface: PaintSurface = PaintSurface(&scroll_zero_pixels[0], 8, 20, 8, 160)
        let scroll_context: PaintDocumentContext = PaintDocumentContext(scroll_source, &scroll_nodes[0], &scroll_styles[0], &scroll_boxes[0], scroll_count, &scroll_flow, &scroll_zero_surface)
        if paint_document_fragments_scrolled(&scroll_context, 0) != PAINT_OK: panic("zero scroll paint")
        if scroll_zero_pixels[97] != 0xffff00ff as u32 or scroll_zero_pixels[65] != 0xff112233 as u32: panic("zero scroll pixels")
        let scroll_pixels: [64]u32
        let scroll_surface: PaintSurface = PaintSurface(&scroll_pixels[0], 8, 8, 8, 64)
        scroll_context.surface = &scroll_surface
        if paint_document_fragments_scrolled(&scroll_context, 6) != PAINT_OK: panic("translated scroll paint")
        if scroll_pixels[17] != 0xff112233 as u32 or scroll_pixels[1] != 0xff112233 as u32 or scroll_pixels[57] != 0xff000000 as u32: panic("translated and clipped scroll pixels")
        let scroll_original: [64]u32
        i = 0
        while i < 64:
            scroll_original[i] = scroll_pixels[i]
            i += 1
        let invalid_scroll_context: PaintDocumentContext = PaintDocumentContext(scroll_source, &scroll_nodes[0], &scroll_styles[0], &scroll_boxes[0], scroll_count, &scroll_flow, &scroll_surface)
        if paint_document_fragments_scrolled(&invalid_scroll_context, -1) != PAINT_INVALID: panic("negative scroll rejected")
        i = 0
        while i < 64:
            if scroll_pixels[i] != scroll_original[i]: panic("invalid scroll preserves framebuffer")
            i += 1
    print("paint pixels ok")
    unsafe:
        let default_source: string = "<style>body { background: #18232b; } h1 { color: white; background: #246b66; margin: 8px; display: block; } p { color: #18232b; background: #dce8e6; margin: 8px; display: block; }</style><body><h1>VOLT Browser</h1><p>Local HTML parsed and laid out by the VOLT engine.</p><p>Close the window to exit.</p></body>"
        let default_nodes: [32]HtmlNode
        let default_attrs: [64]HtmlAttribute
        let default_count: i64 = html_parse(default_source, &default_nodes[0], 32, &default_attrs[0], 64)
        let default_styles: [32]CssResolvedStyle
        let default_boxes: [32]CssLayoutBox
        let default_fragments: [64]CssFlowFragment
        let default_text: [1024]char
        let default_sheet: string = "style, script { display: none; } body { background: #18232b; } h1 { color: white; background: #246b66; margin: 8px; display: block; } p { color: #18232b; background: #dce8e6; margin: 8px; display: block; }"
        let default_rules: [8]CssRule
        let default_selectors: [16]CssSelector
        let default_declarations: [32]CssDeclaration
        let default_css_buffers: CssBuffers = CssBuffers(&default_rules[0], 8, &default_selectors[0], 16, &default_declarations[0], 32)
        let default_rule_count: i64 = css_parse(default_sheet, &default_css_buffers)
        let default_selector_count: i64 = 0
        let default_declaration_count: i64 = 0
        i = 0
        while i < default_rule_count:
            default_selector_count += default_rules[i].selector_count
            default_declaration_count += default_rules[i].declaration_count
            i += 1
        let default_layout: CssLayoutContext = CssLayoutContext(&default_nodes[0], default_count, &default_styles[0], default_count, 640, &default_boxes[0], 32, &default_fragments[0], 64, 0, &default_text[0], 1024, 0, default_source, true)
        let default_cascade: CssCascadeContext = CssCascadeContext(default_sheet, &default_rules[0], default_rule_count, &default_selectors[0], default_selector_count, &default_declarations[0], default_declaration_count, default_source, &default_nodes[0], &default_attrs[0], default_count, 0)
        let default_document: CssDocumentContext = CssDocumentContext(&default_cascade, &default_styles[0], 32, &default_layout)
        match css_prepare_document(&default_document):
            Ok(_):
                if default_styles[3].background_rgb != 0x18232b or default_styles[4].background_rgb != 0x246b66 or default_styles[6].background_rgb != 0xdce8e6: panic("default fixture colors")
            Err(_): panic("default fixture preparation")
        let default_pixels: [307200]u32
        let default_surface: PaintSurface = PaintSurface(&default_pixels[0], 640, 480, 640, 307200)
        let default_flow: PaintFlowContext = PaintFlowContext(&default_fragments[0], default_layout.fragment_count, &default_text[0], default_layout.text_length)
        let default_context: PaintDocumentContext = PaintDocumentContext(default_source, &default_nodes[0], &default_styles[0], &default_boxes[0], default_count, &default_flow, &default_surface)
        let default_status: i64 = paint_document_fragments(&default_context)
        if default_status != PAINT_OK: panic("default fixture paint status")
        if default_pixels[0] != 0xff18232b as u32: panic("default body pixel")
        if default_pixels[8 * 640 + 8] != 0xff246b66 as u32: panic("default heading background pixel")
        if default_pixels[16 * 640 + 14] != 0xffffffff as u32: panic("default heading glyph pixel")
        if default_pixels[80 * 640 + 8] != 0xffdce8e6 as u32: panic("default paragraph background pixel")
        if default_pixels[92 * 640 + 20] != 0xff18232b as u32: panic("default paragraph glyph pixel")
        print("default fixture pixels ok")
    return 0
