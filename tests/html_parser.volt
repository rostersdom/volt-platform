use html

fn main() -> i64:
    let source: string = "<!doctype html><!--x--><html><body><p title=\">\" >Hello</p><br/>World</body></html>"
    let nodes: [16]HtmlNode
    let attributes: [8]HtmlAttribute
    let count: i64 = 0
    unsafe: count = html_parse(source, &nodes[0], 16, &attributes[0], 8)
    if count != 7:
        panic("html node count")
    if nodes[0].kind != HTML_DOCUMENT or nodes[0].first_child != 1:
        panic("html document root")
    if nodes[1].kind != HTML_ELEMENT or nodes[1].parent != 0:
        panic("html root element")
    if nodes[2].kind != HTML_ELEMENT or nodes[2].parent != 1:
        panic("html body element")
    if nodes[3].kind != HTML_ELEMENT or nodes[3].parent != 2:
        panic("html paragraph element")
    if nodes[4].kind != HTML_TEXT_NODE or nodes[4].parent != 3:
        panic("html text node")
    if nodes[3].raw_length == 0 or nodes[3].raw_start < 0:
        panic("html raw tag range")
    if nodes[3].attribute_count != 1 or attributes[0].owner != 3 or not attributes[0].has_value:
        panic("html quoted attribute")
    if attributes[0].value_length != 1:
        panic("html attribute value range")
    let attribute_text: [8]char
    let attribute_text_length: i64 = 0
    unsafe: attribute_text_length = html_decode_attribute(source, &attributes[0], &attribute_text[0], 8)
    if attribute_text_length != 1 or attribute_text[0] != '>':
        panic("html decoded attribute")
    let node_text: [16]char
    let node_text_length: i64 = 0
    unsafe: node_text_length = html_decode_node_text(source, &nodes[4], &node_text[0], 16)
    if node_text_length != 5 or node_text[0] != 'H' or node_text[4] != 'o':
        panic("html decoded text node")
    let attribute_small: [1]char
    let attribute_small_result: i64 = 0
    unsafe: attribute_small_result = html_decode_attribute(source, &attributes[0], &attribute_small[0], 1)
    if attribute_small_result != -7:
        panic("html decoded attribute bound")
    let boolean_attribute: HtmlAttribute = HtmlAttribute(1, 0, 8, 0, 0, false)
    let boolean_result: i64 = 0
    unsafe: boolean_result = html_decode_attribute("disabled", &boolean_attribute, &attribute_small[0], 1)
    if boolean_result != -22:
        panic("html boolean attribute decode")
    unsafe:
        let entities: string = "&#1071;&#x451;&#X1f642;&amp;&unknown;"
        let decoded: [32]char
        if html_decode(entities, 0, __volt_strlen(entities), &decoded[0], 32) != 18: panic("html numeric entity length")
        if (&decoded[0]) as string != "Яё🙂&&unknown;": panic("html numeric entity text")
        let invalid: string = "&#0;&#xD800;&#999999999999999999;&#xGG;"
        if html_decode(invalid, 0, __volt_strlen(invalid), &decoded[0], 32) != 15: panic("html invalid numeric entity length")
        if (&decoded[0]) as string != "���&#xGG;": panic("html invalid numeric entity text")
        let nbsp: string = "&nbsp;"
        if html_decode(nbsp, 0, 6, &decoded[0], 3) != 2 or decoded[0] as i64 != 0xc2 or decoded[1] as i64 != 0xa0: panic("html nonbreaking space")
        decoded[3] = 'Z'
        if html_decode("&#x1f642;", 0, 9, &decoded[0], 4) != -7 or decoded[3] != 'Z': panic("html UTF-8 entity output bound")
    let attr_name_ok: bool = false
    unsafe: attr_name_ok = html_attribute_name_equal(source, &attributes[0], "TITLE")
    if not attr_name_ok:
        panic("html attribute name")
    if nodes[5].kind != HTML_ELEMENT or nodes[5].parent != 2:
        panic("html void element")
    if nodes[6].kind != HTML_TEXT_NODE or nodes[6].parent != 2:
        panic("html trailing text")
    if nodes[1].next_sibling != -1 or nodes[2].next_sibling != -1:
        panic("html sibling links")

    let same_name: bool = false
    unsafe: same_name = html_name_equal(source, &nodes[1], "HTML")
    if not same_name:
        panic("html case insensitive tag name")
    let invalid: i64 = 0
    unsafe: invalid = html_parse(source, &nodes[0], 0, &attributes[0], 8)
    if invalid != -22:
        panic("html invalid capacity")
    let too_small: i64 = 0
    unsafe: too_small = html_parse("<a>x</a>", &nodes[0], 2, &attributes[0], 8)
    if too_small != -7:
        panic("html node capacity limit")
    let malformed: i64 = 0
    unsafe: malformed = html_parse("<!-- unfinished", &nodes[0], 16, &attributes[0], 8)
    if malformed != -22:
        panic("html malformed comment")
    let attr_error: i64 = 0
    unsafe: attr_error = html_parse("<a x='unfinished>", &nodes[0], 16, &attributes[0], 8)
    if attr_error != -22:
        panic("html malformed attribute")
    let attr_full: i64 = 0
    unsafe: attr_full = html_parse("<a x=1 y=2>", &nodes[0], 16, &attributes[0], 1)
    if attr_full != -7:
        panic("html attribute capacity")
    let mixed: i64 = 0
    unsafe: mixed = html_parse("<a disabled data-x=value></a>", &nodes[0], 16, &attributes[0], 8)
    if mixed != 2 or nodes[1].attribute_count != 2:
        panic("html boolean and unquoted attributes")
    if attributes[0].has_value or not attributes[1].has_value or attributes[1].value_length != 5:
        panic("html attribute value kinds")
    let slash_values: i64 = 0
    unsafe: slash_values = html_parse("<a href=/path x=/>z</a>", &nodes[0], 16, &attributes[0], 8)
    if slash_values != 3 or nodes[1].attribute_count != 2:
        panic("html slash values")
    if attributes[0].value_length != 5 or attributes[1].value_length != 1:
        panic("html slash attribute ranges")
    let duplicate: i64 = 0
    unsafe: duplicate = html_parse("<a HREF=first href=second>", &nodes[0], 16, &attributes[0], 8)
    if duplicate != 2 or nodes[1].attribute_count != 1:
        panic("html duplicate attribute")
    let raw_count: i64 = 0
    unsafe: raw_count = html_parse("<script>if (a < b) x='</not-script>';</script><p>ok</p>", &nodes[0], 16, &attributes[0], 8)
    if raw_count != 5 or nodes[2].kind != HTML_TEXT_NODE or nodes[2].parent != 1:
        panic("html raw script text")
    if nodes[2].text_length == 0 or nodes[3].kind != HTML_ELEMENT:
        panic("html raw script close")
    let style_count: i64 = 0
    unsafe: style_count = html_parse("<style>.x{content:'</not-style>'}</style><p>end</p>", &nodes[0], 16, &attributes[0], 8)
    if style_count != 5 or nodes[2].kind != HTML_TEXT_NODE or nodes[2].parent != 1:
        panic("html raw style text")
    let raw_eof: i64 = 0
    unsafe: raw_eof = html_parse("<script>x</script>", &nodes[0], 16, &attributes[0], 8)
    if raw_eof != 3 or nodes[2].kind != HTML_TEXT_NODE or nodes[2].text_length != 1:
        panic("html raw end at eof")
    unsafe:
        let paragraphs: string = "<body><p><em>one<P>two<div>three</div></body>"
        let paragraphs_count: i64 = html_parse(paragraphs, &nodes[0], 16, &attributes[0], 8)
        if paragraphs_count != 9 or nodes[2].next_sibling != 5 or nodes[5].next_sibling != 7:
            panic("html implicit paragraph ends")
        if nodes[5].parent != 1 or nodes[6].parent != 5 or nodes[7].parent != 1:
            panic("html tree after implicit paragraph ends")
        let items: string = "<ul><li><ul><li>a<li>b</ul><li>c</ul>"
        if html_parse(items, &nodes[0], 16, &attributes[0], 8) != 10:
            panic("html list node count")
        if nodes[3].parent != 2 or nodes[4].next_sibling != 6 or nodes[6].parent != 3 or nodes[2].next_sibling != 8 or nodes[8].parent != 1:
            panic("html implicit list item ends in nested lists")
        let table: string = "<p>before<table><tbody><tr><td>a</td><td>b</td></tr></tbody></table>after"
        if html_parse(table, &nodes[0], 16, &attributes[0], 8) != 11:
            panic("html table node count")
        if nodes[1].next_sibling != 3 or nodes[3].next_sibling != 10 or nodes[5].parent != 4 or nodes[6].next_sibling != 8 or nodes[8].parent != 5:
            panic("html table after implicit paragraph end")
        let cells: string = "<table><tbody><tr><td><p>one<p>two</td><td>three</td></tr></tbody></table>"
        if html_parse(cells, &nodes[0], 16, &attributes[0], 8) != 11:
            panic("html table cells node count")
        if nodes[4].next_sibling != 9 or nodes[9].parent != 3 or nodes[5].next_sibling != 7 or nodes[7].parent != 4:
            panic("html implicit paragraphs stay inside their table cell")
    print("html parser ok", count)
    return 0
