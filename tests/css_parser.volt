use css

fn main() -> i64:
    let source: string = "/*x*/ p, .note { color: red; margin: calc(1px + 2px); content: \"}\"; }"
    let rules: [4]CssRule
    let selectors: [8]CssSelector
    let declarations: [8]CssDeclaration
    let buffers: CssBuffers = CssBuffers(&rules[0], 4, &selectors[0], 8, &declarations[0], 8)
    let count: i64 = 0
    unsafe: count = css_parse(source, &buffers)
    if count != 1 or rules[0].selector_count != 2 or rules[0].declaration_count != 3:
        panic("css rule shape")
    if declarations[0].owner != 0 or declarations[1].owner != 0 or declarations[2].owner != 0:
        panic("css declaration owner")
    let color_ok: bool = false
    unsafe: color_ok = css_property_equal(source, &declarations[0], "COLOR")
    if not color_ok or declarations[1].value_length != 15 or declarations[2].value_length != 3:
        panic("css declaration ranges")
    if selectors[0].length != 1 or selectors[1].length != 5 or selectors[1].start <= selectors[0].start:
        panic("css selector split")
    if selectors[0].length != 1 or selectors[1].length != 5 or selectors[0].owner != 0 or selectors[1].owner != 0:
        panic("css selector ranges")
    let html_source: string = "<p id=\"main\" class=\"note wide\">Text</p><div class=\"note\"></div>"
    let html_nodes: [8]HtmlNode
    let html_attributes: [8]HtmlAttribute
    let html_count: i64 = 0
    unsafe: html_count = html_parse(html_source, &html_nodes[0], 8, &html_attributes[0], 8)
    if html_count != 4:
        panic("css html fixture")
    let cascade_source: string = "p { color: red; } .wide { color: blue; } #main { color: green; } p { color: orange !important; } .wide { color: purple !important; } #main { color: black !important; }"
    let cascade_rules: [8]CssRule
    let cascade_selectors: [8]CssSelector
    let cascade_declarations: [8]CssDeclaration
    let cascade_buffers: CssBuffers = CssBuffers(&cascade_rules[0], 8, &cascade_selectors[0], 8, &cascade_declarations[0], 8)
    let cascade_rule_count: i64 = 0
    unsafe: cascade_rule_count = css_parse(cascade_source, &cascade_buffers)
    if cascade_rule_count != 6:
        panic("css cascade fixture")
    let cascade_context: CssCascadeContext = CssCascadeContext(cascade_source, &cascade_rules[0], cascade_rule_count, &cascade_selectors[0], 6, &cascade_declarations[0], 6, html_source, &html_nodes[0], &html_attributes[0], html_count, 1)
    let color_winner: i64 = -1
    unsafe:
        match css_cascade_property(&cascade_context, "color"):
            Ok(index): color_winner = index
            Err(error): panic("css invalid cascade context")
    if color_winner != 5 or not cascade_declarations[color_winner].important:
        panic("css important cascade")
    let important_specificity_source: string = "#main { color: black !important; } .wide { color: violet !important; }"
    let priority_rules: [4]CssRule
    let priority_selectors: [4]CssSelector
    let priority_declarations: [4]CssDeclaration
    let priority_buffers: CssBuffers = CssBuffers(&priority_rules[0], 4, &priority_selectors[0], 4, &priority_declarations[0], 4)
    let priority_count: i64 = 0
    unsafe: priority_count = css_parse(important_specificity_source, &priority_buffers)
    let priority_context: CssCascadeContext = CssCascadeContext(important_specificity_source, &priority_rules[0], priority_count, &priority_selectors[0], 2, &priority_declarations[0], 2, html_source, &html_nodes[0], &html_attributes[0], html_count, 1)
    let priority_winner: i64 = -1
    unsafe:
        match css_cascade_property(&priority_context, "color"):
            Ok(index): priority_winner = index
            Err(error): panic("css invalid priority context")
    if priority_winner != 0:
        panic("css important specificity")
    let absent: i64 = -2
    unsafe:
        match css_cascade_property(&priority_context, "background"):
            Ok(index): absent = index
            Err(error): panic("css absent property error")
    if absent != -1:
        panic("css missing property")
    let style: CssComputedStyle
    let style_count: i64 = -1
    unsafe:
        match css_compute_style(&priority_context, &style):
            Ok(count): style_count = count
            Err(error): panic("css computed style error")
    if style_count != 1 or style.color != 0 or style.background != -1 or style.margin != -1 or style.display != -1:
        panic("css computed style fields")
    let invalid_context: CssCascadeContext = CssCascadeContext(important_specificity_source, &priority_rules[0], priority_count, &priority_selectors[0], 2, &priority_declarations[0], 2, html_source, &html_nodes[0], &html_attributes[0], 0, 0)
    let invalid_result: bool = false
    unsafe:
        match css_cascade_property(&invalid_context, "color"):
            Ok(index): invalid_result = false
            Err(error): invalid_result = error == 22
    if not invalid_result:
        panic("css invalid context distinct from miss")
    let later_source: string = "p { margin: 1px; } p { margin: 2px; }"
    let later_rules: [4]CssRule
    let later_selectors: [4]CssSelector
    let later_declarations: [4]CssDeclaration
    let later_buffers: CssBuffers = CssBuffers(&later_rules[0], 4, &later_selectors[0], 4, &later_declarations[0], 4)
    let later_count: i64 = 0
    unsafe: later_count = css_parse(later_source, &later_buffers)
    let later_context: CssCascadeContext = CssCascadeContext(later_source, &later_rules[0], later_count, &later_selectors[0], 2, &later_declarations[0], 2, html_source, &html_nodes[0], &html_attributes[0], html_count, 1)
    let margin_winner: i64 = -1
    unsafe:
        match css_cascade_property(&later_context, "margin"):
            Ok(index): margin_winner = index
            Err(error): panic("css invalid source-order context")
    if margin_winner != 1:
        panic("css source order cascade")
    let later_style: CssComputedStyle
    let later_style_count: i64 = -1
    unsafe:
        match css_compute_style(&later_context, &later_style):
            Ok(count): later_style_count = count
            Err(error): panic("css source-order style error")
    if later_style_count != 1 or later_style.margin != 1:
        panic("css source-order computed style")
    let style_html: string = "<style>p { color: red; }</style><style>p { margin: 3px; }</style><p>x</p>"
    let style_nodes: [8]HtmlNode
    let style_attributes: [8]HtmlAttribute
    let style_node_count: i64 = 0
    unsafe: style_node_count = html_parse(style_html, &style_nodes[0], 8, &style_attributes[0], 8)
    let collected_css: [128]char
    let collected_length: i64 = 0
    unsafe: collected_length = css_collect_inline_styles(style_html, &style_nodes[0], style_node_count, &collected_css[0], 128)
    if collected_length != 37:
        panic("css inline styles length")
    let collected_source: string
    unsafe: collected_source = (&collected_css[0]) as string
    let collected_rules: [4]CssRule
    let collected_selectors: [4]CssSelector
    let collected_declarations: [4]CssDeclaration
    let collected_buffers: CssBuffers = CssBuffers(&collected_rules[0], 4, &collected_selectors[0], 4, &collected_declarations[0], 4)
    let collected_rule_count: i64 = 0
    unsafe: collected_rule_count = css_parse(collected_source, &collected_buffers)
    if collected_rule_count != 2 or collected_declarations[0].value_length != 3 or collected_declarations[1].value_length != 3:
        panic("css inline style order")
    let too_small_css: [4]char
    let too_small_css_result: i64 = 0
    unsafe: too_small_css_result = css_collect_inline_styles(style_html, &style_nodes[0], style_node_count, &too_small_css[0], 4)
    if too_small_css_result != -7:
        panic("css inline stylesheet capacity")
    let resolved_source: string = "p { color: #f08; background: #123456; margin: -1px; display: block; }"
    let resolved_rules: [2]CssRule
    let resolved_selectors: [2]CssSelector
    let resolved_declarations: [4]CssDeclaration
    let resolved_buffers: CssBuffers = CssBuffers(&resolved_rules[0], 2, &resolved_selectors[0], 2, &resolved_declarations[0], 4)
    let resolved_count: i64 = 0
    unsafe: resolved_count = css_parse(resolved_source, &resolved_buffers)
    let resolved_context: CssCascadeContext = CssCascadeContext(resolved_source, &resolved_rules[0], resolved_count, &resolved_selectors[0], 1, &resolved_declarations[0], 4, html_source, &html_nodes[0], &html_attributes[0], html_count, 1)
    let resolved_style: CssResolvedStyle
    unsafe:
        match css_resolve_style(&resolved_context, &resolved_style):
            Ok(count):
                if count != 4: panic("css resolved property count")
            Err(error): panic("css resolved style")
    if resolved_style.color_rgb != 16711816 or resolved_style.background_rgb != 1193046 or resolved_style.margin_px != -1 or resolved_style.display != 2:
        panic("css resolved values")
    let hidden_style_source: string = "style, script { display: none; }"
    let hidden_rules: [2]CssRule
    let hidden_selectors: [4]CssSelector
    let hidden_declarations: [2]CssDeclaration
    let hidden_buffers: CssBuffers = CssBuffers(&hidden_rules[0], 2, &hidden_selectors[0], 4, &hidden_declarations[0], 2)
    let hidden_rule_count: i64 = 0
    unsafe: hidden_rule_count = css_parse(hidden_style_source, &hidden_buffers)
    let hidden_selector_count: i64 = 0
    let hidden_declaration_count: i64 = 0
    let hidden_i: i64 = 0
    while hidden_i < hidden_rule_count:
        hidden_selector_count += hidden_rules[hidden_i].selector_count
        hidden_declaration_count += hidden_rules[hidden_i].declaration_count
        hidden_i += 1
    let hidden_context: CssCascadeContext = CssCascadeContext(hidden_style_source, &hidden_rules[0], hidden_rule_count, &hidden_selectors[0], hidden_selector_count, &hidden_declarations[0], hidden_declaration_count, style_html, &style_nodes[0], &style_attributes[0], style_node_count, 1)
    let hidden_style: CssResolvedStyle
    unsafe:
        match css_resolve_style(&hidden_context, &hidden_style):
            Ok(count):
                if count != 4: panic("css hidden computed property count")
            Err(error): panic("css hidden style resolution")
    if hidden_style.display != 0:
        panic("css style element default hidden")
    let layout_styles: [4]CssResolvedStyle
    let layout_boxes: [4]CssLayoutBox
    layout_styles[0] = CssResolvedStyle(0, -1, 0, 2)
    layout_styles[1] = CssResolvedStyle(0, -1, 0, 2)
    layout_styles[2] = CssResolvedStyle(0, -1, 0, 1)
    layout_styles[3] = CssResolvedStyle(0, -1, 0, 2)
    let layout_context: CssLayoutContext = CssLayoutContext(&html_nodes[0], html_count, &layout_styles[0], html_count, 800, &layout_boxes[0], 4, 0 as ptr<CssFlowFragment>, 0, 0, 0 as ptr<char>, 0, 0, html_source, false)
    unsafe:
        match css_layout_blocks(&layout_context):
            Ok(count):
                if count != html_count: panic("css layout box count")
            Err(error): panic("css block layout")
    if layout_boxes[0].width != 800 or layout_boxes[1].width != 800 or layout_boxes[1].height != 16 or layout_boxes[3].y != 16:
        panic("css block layout geometry")
    layout_styles[1].display = 0
    unsafe:
        match css_layout_blocks(&layout_context):
            Ok(count):
                if count != html_count: panic("css hidden layout count")
            Err(error): panic("css hidden layout")
    if not layout_boxes[1].hidden or not layout_boxes[2].hidden or layout_boxes[3].y != 0:
        panic("css display none layout")
    let document_css: string = "p { color: #123456; margin: 2px; display: block; } div { display: none; }"
    let document_rules: [4]CssRule
    let document_selectors: [4]CssSelector
    let document_declarations: [8]CssDeclaration
    let document_buffers: CssBuffers = CssBuffers(&document_rules[0], 4, &document_selectors[0], 4, &document_declarations[0], 8)
    let document_rule_count: i64 = 0
    unsafe: document_rule_count = css_parse(document_css, &document_buffers)
    let document_cascade: CssCascadeContext = CssCascadeContext(document_css, &document_rules[0], document_rule_count, &document_selectors[0], 2, &document_declarations[0], 5, html_source, &html_nodes[0], &html_attributes[0], html_count, 0)
    let document_layout: CssLayoutContext = CssLayoutContext(&html_nodes[0], html_count, &layout_styles[0], html_count, 800, &layout_boxes[0], 4, 0 as ptr<CssFlowFragment>, 0, 0, 0 as ptr<char>, 0, 0, html_source, false)
    let document_context: CssDocumentContext = CssDocumentContext(&document_cascade, &layout_styles[0], 4, &document_layout)
    unsafe:
        match css_prepare_document(&document_context):
            Ok(count):
                if count != html_count: panic("css document box count")
            Err(error): panic("css document preparation")
    if layout_styles[1].color_rgb != 1193046 or layout_styles[1].margin_px != 2 or layout_styles[1].display != 2 or not layout_boxes[3].hidden:
        panic("css document computed layout")
    let tag_rule: i64 = 0
    unsafe: tag_rule = css_parse("p { color: red; }", &buffers)
    let tag_match: bool = false
    unsafe: tag_match = css_selector_matches("p", &selectors[0], html_source, &html_nodes[1], &html_attributes[0])
    if tag_rule != 1 or not tag_match:
        panic("css tag match")
    let class_rule: i64 = 0
    unsafe: class_rule = css_parse(".wide { color: blue; }", &buffers)
    let class_match: bool = false
    unsafe: class_match = css_selector_matches(".wide", &selectors[0], html_source, &html_nodes[1], &html_attributes[0])
    let class_miss: bool = false
    unsafe: class_miss = css_selector_matches(".wide", &selectors[0], html_source, &html_nodes[3], &html_attributes[0])
    if class_rule != 1 or not class_match or class_miss:
        panic("css class match")
    let id_match: bool = false
    unsafe: id_match = css_selector_matches("#main", &selectors[0], html_source, &html_nodes[1], &html_attributes[0])
    if not id_match:
        panic("css id match")
    let compound_rule: i64 = 0
    unsafe: compound_rule = css_parse("p.note#main { color: green; }", &buffers)
    let compound_match: bool = false
    unsafe: compound_match = css_selector_matches("p.note#main", &selectors[0], html_source, &html_nodes[1], &html_attributes[0])
    if compound_rule != 1 or not compound_match:
        panic("css compound match")
    let tree_html: string = "<section><div><p class=\"target\">x</p></div></section>"
    let tree_nodes: [8]HtmlNode
    let tree_attributes: [8]HtmlAttribute
    let tree_count: i64 = 0
    unsafe: tree_count = html_parse(tree_html, &tree_nodes[0], 8, &tree_attributes[0], 8)
    if tree_count != 5:
        panic("css tree fixture")
    let descendant_rule: i64 = 0
    unsafe: descendant_rule = css_parse("section p.target { color: red; }", &buffers)
    let context: CssMatchContext = CssMatchContext("section p.target { color: red; }", &selectors[0], tree_html, &tree_nodes[0], &tree_attributes[0], tree_count, 3)
    let descendant_match: bool = false
    unsafe: descendant_match = css_selector_matches_tree(&context)
    if descendant_rule != 1 or not descendant_match:
        panic("css descendant match")
    let child_rule: i64 = 0
    unsafe: child_rule = css_parse("div > p.target { color: blue; }", &buffers)
    context.css_source = "div > p.target { color: blue; }"
    context.selector = &selectors[0]
    let child_match: bool = false
    unsafe: child_match = css_selector_matches_tree(&context)
    if child_rule != 1 or not child_match:
        panic("css child match")
    let child_miss_rule: i64 = 0
    unsafe: child_miss_rule = css_parse("section > p.target { color: blue; }", &buffers)
    context.css_source = "section > p.target { color: blue; }"
    context.selector = &selectors[0]
    let child_miss: bool = false
    unsafe: child_miss = css_selector_matches_tree(&context)
    if child_miss_rule != 1 or child_miss:
        panic("css child miss")
    let malformed_rule: i64 = 0
    unsafe: malformed_rule = css_parse("div > { x: y; }", &buffers)
    if malformed_rule != 1:
        panic("css malformed selector parse remains bounded")
    context.css_source = "div > { x: y; }"
    context.selector = &selectors[0]
    let malformed_match: bool = false
    unsafe: malformed_match = css_selector_matches_tree(&context)
    if malformed_match:
        panic("css dangling combinator")
    let invalid_selector: CssSelector = CssSelector(0, 99999, 4)
    let invalid_match: bool = false
    unsafe: invalid_match = css_selector_matches("p", &invalid_selector, html_source, &html_nodes[1], &html_attributes[0])
    if invalid_match:
        panic("css selector bounds")
    let spaced: i64 = 0
    unsafe: spaced = css_parse("  p  {  color  :  blue  ; }  ", &buffers)
    if spaced != 1 or selectors[0].length != 1 or declarations[0].property_length != 5 or declarations[0].value_length != 4:
        panic("css trimmed ranges")
    let bad: i64 = 0
    unsafe: bad = css_parse("p { color: \"unfinished; }", &buffers)
    if bad != -22:
        panic("css unterminated quote")
    let unclosed: i64 = 0
    unsafe: unclosed = css_parse("p { color: red;", &buffers)
    if unclosed != -22:
        panic("css missing closing brace")
    let important: i64 = 0
    unsafe: important = css_parse("p { color: red ! IMPORTANT ; }", &buffers)
    if important != 1 or not declarations[0].important or declarations[0].value_length != 3:
        panic("css important")
    let grouped: i64 = 0
    unsafe: grouped = css_parse("p:is(.a, .b), [x=\",\"] { width: calc(1px, 2px); }", &buffers)
    if grouped != 1 or rules[0].selector_count != 2 or selectors[0].length != 12 or selectors[1].length != 7:
        panic("css grouped selector commas")
    unsafe:
        let recovered: string = "p { color: red; broken; } @import url('a;b.css'); @media screen { /* } */ p { content: \"\\\"}x\"; color: black; } @supports (x:y) { b { color: blue } } } p, { color: blue; } a { color: green }"
        if css_parse(recovered, &buffers) != 2 or rules[0].declaration_count != 1 or rules[1].declaration_count != 1:
            panic("css recovery preserves adjacent rules")
        if not css_value_equal(recovered, &declarations[0], "red") or not css_value_equal(recovered, &declarations[1], "green") or declarations[1].owner != 1:
            panic("css skipped rules must not enter cascade")
        if css_parse("p { color: red } @media screen { a { color: blue }", &buffers) != 1:
            panic("css incomplete ignored block preserves preceding rule")
        let last_bad: string = "p { color: red; broken } @unknown { tokens: [ stray) } ]; } a { color: green }"
        if css_parse(last_bad, &buffers) != 2 or rules[0].declaration_count != 1 or rules[1].declaration_count != 1:
            panic("css skips a bad last declaration and balances nested blocks")
    let no_selector_room: i64 = 0
    buffers.selector_capacity = 1
    unsafe: no_selector_room = css_parse("p, a { x: y; }", &buffers)
    if no_selector_room != -7:
        panic("css selector capacity")
    buffers.selector_capacity = 8
    let full: i64 = 0
    buffers.declaration_capacity = 1
    unsafe: full = css_parse("p { a: 1; b: 2; }", &buffers)
    if full != -7:
        panic("css declaration capacity")
    let empty: i64 = 0
    buffers.rule_capacity = 0
    buffers.selector_capacity = 0
    buffers.declaration_capacity = 0
    unsafe: empty = css_parse("", &buffers)
    if empty != 0:
        panic("css empty input")
    let no_rules: i64 = 0
    buffers.selector_capacity = 8
    unsafe: no_rules = css_parse("p { }", &buffers)
    if no_rules != -7:
        panic("css zero rule capacity")
    print("css parser ok", count)
    return 0
