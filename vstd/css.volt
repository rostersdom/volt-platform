use html
use utf8
use buffer

# Bounded CSS rule parser and simple selector matcher for the staged VOLT browser engine.
const CSS_FRAGMENT_LIMIT: i64 = 262144
const CSS_STYLESHEET_LIMIT: i64 = 65536

struct CssRule:
    selector_start: i64
    selector_count: i64
    declaration_start: i64
    declaration_count: i64
    min_width: i64
    max_width: i64

struct CssSelector:
    owner: i64
    start: i64
    length: i64

struct CssDeclaration:
    owner: i64
    property_start: i64
    property_length: i64
    value_start: i64
    value_length: i64
    important: bool

struct CssBuffers:
    rules: ptr<CssRule>
    rule_capacity: i64
    selectors: ptr<CssSelector>
    selector_capacity: i64
    declarations: ptr<CssDeclaration>
    declaration_capacity: i64

struct CssMatchContext:
    css_source: string
    selector: ptr<CssSelector>
    html_source: string
    nodes: ptr<HtmlNode>
    attributes: ptr<HtmlAttribute>
    node_count: i64
    node_index: i64

struct CssCascadeContext:
    css_source: string
    rules: ptr<CssRule>
    rule_count: i64
    selectors: ptr<CssSelector>
    selector_count: i64
    declarations: ptr<CssDeclaration>
    declaration_count: i64
    html_source: string
    nodes: ptr<HtmlNode>
    attributes: ptr<HtmlAttribute>
    node_count: i64
    node_index: i64

struct CssComputedStyle:
    color: i64
    background: i64
    margin: i64
    display: i64

struct CssResolvedStyle:
    color_rgb: i64
    background_rgb: i64
    margin_px: i64
    display: i64

struct CssLayoutBox:
    x: i64
    y: i64
    width: i64
    height: i64
    hidden: bool

struct CssFlowFragment:
    node_index: i64
    byte_start: i64
    byte_length: i64
    x: i64
    y: i64
    color_rgb: i64
    clip_x: i64
    clip_y: i64
    clip_width: i64
    clip_height: i64
    advance: i64
    line_height: i64
    baseline: i64

struct CssFlowCursor:
    origin_x: i64
    origin_y: i64
    width: i64
    x: i64
    y: i64
    line_height: i64
    pending_space: bool
    occupied: bool

struct CssLayoutContext:
    nodes: ptr<HtmlNode>
    node_count: i64
    styles: ptr<CssResolvedStyle>
    style_count: i64
    viewport_width: i64
    boxes: ptr<CssLayoutBox>
    box_capacity: i64
    fragments: ptr<CssFlowFragment>
    fragment_capacity: i64
    fragment_count: i64
    text_bytes: ptr<char>
    text_capacity: i64
    text_length: i64
    html_source: string
    flow_enabled: bool

struct CssDocumentContext:
    cascade: ptr<CssCascadeContext>
    styles: ptr<CssResolvedStyle>
    style_capacity: i64
    layout: ptr<CssLayoutContext>

struct CssSelectorPart:
    start: i64
    length: i64
    relation: char

unsafe fn css_space(c: char) -> bool:
    return c == ' ' or c == '\t' or c == '\n' or c == '\r'

unsafe fn css_skip_space(p: ptr<char>, at: ptr<i64>, end: i64):
    while at[0] < end and css_space(p[at[0]]): at[0] += 1

unsafe fn css_skip_comment(p: ptr<char>, at: ptr<i64>, end: i64) -> i64:
    if at[0] + 1 >= end or p[at[0]] != '/' or p[at[0] + 1] != '*': return 0
    at[0] += 2
    while at[0] + 1 < end and not (p[at[0]] == '*' and p[at[0] + 1] == '/'):
        at[0] += 1
    if at[0] + 1 >= end: return -22
    at[0] += 2
    return 1

unsafe fn css_trim_end(p: ptr<char>, start: i64, end: i64) -> i64:
    let result: i64 = end
    while result > start and css_space(p[result - 1]): result -= 1
    return result

unsafe fn css_trim_start(p: ptr<char>, start: i64, end: i64) -> i64:
    let result: i64 = start
    while result < end and css_space(p[result]): result += 1
    return result

unsafe fn css_important_start(p: ptr<char>, start: i64, end: i64) -> i64:
    let value_end: i64 = css_trim_end(p, start, end)
    let word_end: i64 = value_end
    let word_start: i64 = word_end - 9
    if word_start < start: return value_end
    let word: string = "important"
    let q: ptr<char> = word as ptr<char>
    let i: i64 = 0
    while i < 9:
        let a: i64 = p[word_start + i] as i64
        if a >= 65 and a <= 90: a += 32
        if a != q[i] as i64: return value_end
        i += 1
    let bang: i64 = word_start - 1
    while bang >= start and css_space(p[bang]): bang -= 1
    if bang < start or p[bang] != '!': return value_end
    return css_trim_end(p, start, bang)

struct CssSelectorBuffers:
    selectors: ptr<CssSelector>
    used: ptr<i64>
    capacity: i64

unsafe fn css_selector_split(p: ptr<char>, start: i64, end: i64, owner: i64, buffers: ptr<CssSelectorBuffers>) -> i64:
    let part_start: i64 = start
    while part_start <= end:
        let at: i64 = part_start
        let boundary: i64 = css_find_delimiter(p, &at, end, ',', ',')
        if boundary < 0: return boundary
        let left: i64 = css_trim_start(p, part_start, boundary)
        let right: i64 = css_trim_end(p, left, boundary)
        if right == left: return -22
        if buffers.used[0] >= buffers.capacity: return -7
        buffers.selectors[buffers.used[0]] = CssSelector(owner, left, right - left)
        buffers.used[0] += 1
        part_start = boundary + 1
    return buffers.used[0]

unsafe fn css_find_delimiter(p: ptr<char>, at: ptr<i64>, end: i64, delimiter: char, alternate: char) -> i64:
    let quote: char = '\0'
    let closes: [128]char
    let depth: i64 = 0
    while at[0] < end:
        let c: char = p[at[0]]
        if c == '\\':
            at[0] = min(end, at[0] + 2)
            continue
        if quote != '\0':
            if c == quote: quote = '\0'
        else:
            if c == '\'' or c == '"': quote = c
            else:
                if c == '/' and at[0] + 1 < end and p[at[0] + 1] == '*':
                    let comment: i64 = css_skip_comment(p, at, end)
                    if comment < 0: return -22
                    continue
                if depth == 0 and (c == delimiter or c == alternate): return at[0]
                if c == '(' or c == '[' or c == '{':
                    if depth == 128: return -22
                    closes[depth] = ')'
                    if c == '[': closes[depth] = ']'
                    elif c == '{': closes[depth] = '}'
                    depth += 1
                elif depth > 0 and c == closes[depth - 1]:
                    depth -= 1
        at[0] += 1
    if quote != '\0' or depth != 0: return -22
    return end

unsafe fn css_property_equal(source: string, declaration: ptr<CssDeclaration>, property: string) -> bool:
    let p: ptr<char> = source as ptr<char>
    let q: ptr<char> = property as ptr<char>
    let n: i64 = __volt_strlen(property)
    if declaration.property_length != n: return false
    let i: i64 = 0
    while i < n:
        let a: i64 = p[declaration.property_start + i] as i64
        let b: i64 = q[i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn css_read_declaration(p: ptr<char>, position: ptr<i64>, end: i64, out: ptr<CssDeclaration>) -> i64:
    let start: i64 = position[0]
    let stop: i64 = css_find_delimiter(p, position, end, ';', '}')
    if stop < 0: return stop
    if stop < end and p[stop] == ';': position[0] += 1
    let at: i64 = start
    let colon: i64 = css_find_delimiter(p, &at, stop, ':', '{')
    if colon < 0 or colon >= stop or p[colon] != ':': return 1
    let property_end: i64 = css_trim_end(p, start, colon)
    let value_start: i64 = css_trim_start(p, colon + 1, stop)
    let raw_value_end: i64 = css_trim_end(p, value_start, stop)
    let value_end: i64 = css_important_start(p, value_start, raw_value_end)
    if property_end <= start or value_end <= value_start: return 1
    out[0] = CssDeclaration(0, start, property_end - start, value_start, value_end - value_start, value_end != raw_value_end)
    return 0

unsafe fn css_value_equal(source: string, declaration: ptr<CssDeclaration>, value: string) -> bool:
    return css_range_equal(source, declaration.value_start, declaration.value_length, value)

unsafe fn css_hex_digit(c: char) -> i64:
    let n: i64 = c as i64
    if n >= 48 and n <= 57: return n - 48
    if n >= 65 and n <= 70: return n - 55
    if n >= 97 and n <= 102: return n - 87
    return -1

unsafe fn css_color_value(source: string, declaration: ptr<CssDeclaration>) -> i64:
    if css_value_equal(source, declaration, "black"): return 0
    if css_value_equal(source, declaration, "white"): return 16777215
    if css_value_equal(source, declaration, "red"): return 16711680
    if css_value_equal(source, declaration, "green"): return 32768
    if css_value_equal(source, declaration, "blue"): return 255
    let p: ptr<char> = source as ptr<char>
    let start: i64 = declaration.value_start
    let length: i64 = declaration.value_length
    if length != 4 and length != 7: return -1
    if p[start] != '#': return -1
    let result: i64 = 0
    let i: i64 = 1
    while i < length:
        let high: i64 = css_hex_digit(p[start + i])
        if high < 0: return -1
        let component: i64 = high
        if length == 4:
            component = high * 17
        else:
            i += 1
            let low: i64 = css_hex_digit(p[start + i])
            if low < 0: return -1
            component = high * 16 + low
        result = result * 256 + component
        i += 1
    return result

unsafe fn css_margin_value(source: string, declaration: ptr<CssDeclaration>, out: ptr<i64>) -> bool:
    let p: ptr<char> = source as ptr<char>
    let start: i64 = declaration.value_start
    let length: i64 = declaration.value_length
    if length < 3 or p[start + length - 2] != 'p' or p[start + length - 1] != 'x': return false
    let end: i64 = start + length - 2
    let at: i64 = start
    let negative: bool = false
    if at < end and p[at] == '-':
        negative = true
        at += 1
    if at == end: return false
    let value: i64 = 0
    while at < end:
        let digit: i64 = p[at] as i64 - 48
        if digit < 0 or digit > 9: return false
        if value > 214748364: return false
        value = value * 10 + digit
        if value > 2147483647: return false
        at += 1
    if negative: out[0] = 0 - value
    else: out[0] = value
    return true

unsafe fn css_range_equal(source: string, start: i64, length: i64, value: string) -> bool:
    let p: ptr<char> = source as ptr<char>
    let q: ptr<char> = value as ptr<char>
    let n: i64 = __volt_strlen(value)
    if length != n: return false
    let i: i64 = 0
    while i < n:
        let a: i64 = p[start + i] as i64
        let b: i64 = q[i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn css_html_range_equal(css_source: string, css_start: i64, html_source: string, html_start: i64, length: i64) -> bool:
    let p: ptr<char> = css_source as ptr<char>
    let q: ptr<char> = html_source as ptr<char>
    let i: i64 = 0
    while i < length:
        let a: i64 = p[css_start + i] as i64
        let b: i64 = q[html_start + i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn css_html_tag_equal(css_source: string, css_start: i64, css_length: i64, html_source: string, node: ptr<HtmlNode>) -> bool:
    if node.name_length != css_length: return false
    return css_html_range_equal(css_source, css_start, html_node_name(html_source, node) as string, 0, css_length)

unsafe fn css_find_html_attribute(html_source: string, node: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>, name: string) -> i64:
    let i: i64 = 0
    while i < node.attribute_count:
        let index: i64 = node.attribute_start + i
        if html_attribute_name_equal(html_source, &attributes[index], name): return index
        i += 1
    return -1

unsafe fn css_class_token(html_source: string, attribute: ptr<HtmlAttribute>, css_source: string, token_start: i64, token_length: i64) -> bool:
    let p: ptr<char> = html_source as ptr<char>
    let q: ptr<char> = css_source as ptr<char>
    let value_end: i64 = attribute.value_start + attribute.value_length
    let at: i64 = attribute.value_start
    while at < value_end:
        while at < value_end and html_space(p[at]): at += 1
        let word_start: i64 = at
        while at < value_end and not html_space(p[at]): at += 1
        if at - word_start == token_length:
            let i: i64 = 0
            let same: bool = true
            while i < token_length:
                if p[word_start + i] != q[token_start + i]: same = false
                i += 1
            if same: return true
    return false

fn css_ident_byte(c: char) -> bool:
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_' or c == '-' or c as i64 >= 128

fn css_combinator(c: char) -> bool:
    return c == '>' or c == '+' or c == '~'

unsafe fn css_compound_end(p: ptr<char>, at: i64, end: i64) -> i64:
    while at < end and not css_space(p[at]) and not css_combinator(p[at]):
        if p[at] == '[':
            at += 1
            if css_find_delimiter(p, &at, end, ']', ']') < 0 or at == end: return -1
        at += 1
    return at

unsafe fn css_bytes_equal(a: ptr<char>, b: ptr<char>, length: i64, insensitive: bool) -> bool:
    let i: i64 = 0
    while i < length:
        let left: i64 = a[i] as i64
        let right: i64 = b[i] as i64
        if insensitive:
            if left >= 65 and left <= 90: left += 32
            if right >= 65 and right <= 90: right += 32
        if left != right: return false
        i += 1
    return true

unsafe fn css_attribute_matches(source: string, start: i64, end: i64, html_source: string, node: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>) -> bool:
    let p: ptr<char> = source as ptr<char>
    let name: i64 = css_trim_start(p, start, end)
    let i: i64 = name
    while i < end and css_ident_byte(p[i]): i += 1
    let name_length: i64 = i - name
    if name_length == 0: return false
    let attr: ptr<HtmlAttribute> = 0 as ptr<HtmlAttribute>
    let a: i64 = 0
    while a < node.attribute_count:
        let item: ptr<HtmlAttribute> = &attributes[node.attribute_start + a]
        if item.name_length == name_length and css_html_range_equal(source, name, html_source, item.name_start, name_length):
            attr = item
            break
        a += 1
    if attr == (0 as ptr<HtmlAttribute>): return false
    i = css_trim_start(p, i, end)
    if i == end: return true
    if p[i] != '=': return false
    i = css_trim_start(p, i + 1, end)
    if i == end: return false
    let value: i64 = i
    let length: i64 = 0
    if p[i] == '"' or p[i] == '\'':
        let quote: char = p[i]
        i += 1
        value = i
        while i < end and p[i] != quote:
            if p[i] == '\\': return false
            i += 1
        if i == end: return false
        length = i - value
        i += 1
    else:
        while i < end and css_ident_byte(p[i]): i += 1
        length = i - value
        if length == 0: return false
    let suffix: i64 = i
    i = css_trim_start(p, i, end)
    let insensitive: bool = false
    if i < end:
        if i == suffix: return false
        insensitive = p[i] == 'i' or p[i] == 'I'
        if not insensitive and p[i] != 's' and p[i] != 'S': return false
        if css_trim_start(p, i + 1, end) != end: return false
    let text: ptr<char> = (html_source as ptr<char>) + attr.value_start
    i = 0
    while i < attr.value_length and text[i] != '&': i += 1
    if i == attr.value_length: return attr.value_length == length and css_bytes_equal(p + value, text, length, insensitive)
    if attr.value_length > 4096: return false
    let decoded: [4097]char
    let decoded_length: i64 = html_decode_range(text, attr.value_length, 0, attr.value_length, &decoded[0], 4097)
    return decoded_length == length and css_bytes_equal(p + value, &decoded[0], length, insensitive)

# Matches compounds composed of a tag, classes, IDs and simple attribute selectors.
unsafe fn css_selector_matches(source: string, selector: ptr<CssSelector>, html_source: string, node: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>) -> bool:
    let source_length: i64 = __volt_strlen(source)
    if selector.start < 0 or selector.length < 0 or selector.start > source_length or selector.length > source_length - selector.start: return false
    return css_match_compound(source, selector.start, selector.length, html_source, node, attributes)

unsafe fn css_match_compound(source: string, start: i64, length: i64, html_source: string, node: ptr<HtmlNode>, attributes: ptr<HtmlAttribute>) -> bool:
    if node.kind != HTML_ELEMENT: return false
    let p: ptr<char> = source as ptr<char>
    let end: i64 = start + length
    let at: i64 = start
    if at < end and p[at] == '*':
        at += 1
    elif at < end and css_ident_byte(p[at]):
        let tag_start: i64 = at
        while at < end and css_ident_byte(p[at]): at += 1
        if not css_html_tag_equal(source, tag_start, at - tag_start, html_source, node): return false
    while at < end:
        let marker: char = p[at]
        at += 1
        if marker == '[':
            let attribute: i64 = at
            if css_find_delimiter(p, &at, end, ']', ']') < 0 or at == end: return false
            if not css_attribute_matches(source, attribute, at, html_source, node, attributes): return false
            at += 1
            continue
        if marker != '.' and marker != '#': return false
        let name_start: i64 = at
        while at < end and css_ident_byte(p[at]): at += 1
        if at == name_start: return false
        let name_length: i64 = at - name_start
        if marker == '.':
            let class_index: i64 = css_find_html_attribute(html_source, node, attributes, "class")
            if class_index < 0 or not css_class_token(html_source, &attributes[class_index], source, name_start, name_length): return false
        else:
            let id_index: i64 = css_find_html_attribute(html_source, node, attributes, "id")
            if id_index < 0 or not attributes[id_index].has_value: return false
            let attr: ptr<HtmlAttribute> = &attributes[id_index]
            if attr.value_length != name_length or not css_bytes_equal(p + name_start, (html_source as ptr<char>) + attr.value_start, name_length, false): return false
    return length > 0

unsafe fn css_selector_part_matches(context: ptr<CssMatchContext>, part: ptr<CssSelectorPart>, node_index: i64) -> bool:
    if node_index < 0 or node_index >= context.node_count: return false
    return css_match_compound(context.css_source, part.start, part.length, context.html_source, &context.nodes[node_index], context.attributes)

# Supports descendants, direct children and previous element siblings.
unsafe fn css_selector_matches_tree(context: ptr<CssMatchContext>) -> bool:
    return css_selector_matches_tree_range(context, __volt_strlen(context.css_source))

unsafe fn css_selector_step(context: ptr<CssMatchContext>, node: i64, relation: char) -> i64:
    let previous: i64 = context.nodes[node].parent
    if relation == '+' or relation == '~': previous = context.nodes[node].previous_element
    if previous < 0 or previous >= node: return -1
    return previous

unsafe fn css_selector_matches_tree_range(context: ptr<CssMatchContext>, source_length: i64) -> bool:
    if context.node_count < 1 or context.node_index < 0 or context.node_index >= context.node_count: return false
    if context.selector.start < 0 or context.selector.length < 1 or context.selector.start > source_length or context.selector.length > source_length - context.selector.start: return false
    let p: ptr<char> = context.css_source as ptr<char>
    let parts: [32]CssSelectorPart
    let count: i64 = 0
    let position: i64 = context.selector.start
    let end: i64 = context.selector.start + context.selector.length
    let relation: char = ' '
    while position < end:
        css_skip_space(p, &position, end)
        if position >= end: break
        if css_combinator(p[position]):
            if count == 0: return false
            relation = p[position]
            position += 1
            css_skip_space(p, &position, end)
            if position >= end: return false
        if count >= 32: return false
        let start: i64 = position
        position = css_compound_end(p, position, end)
        if position <= start: return false
        parts[count] = CssSelectorPart(start, position - start, relation)
        count += 1
        relation = ' '
    if count == 0: return false
    let part: i64 = count - 1
    if not css_selector_part_matches(context, &parts[part], context.node_index): return false
    if part == 0: return true
    let choices: [32]i64
    part -= 1
    choices[part] = css_selector_step(context, context.node_index, parts[part + 1].relation)
    # shortcut: cap candidate visits until selector matching has a shared work budget.
    let visits: i64 = 0
    while part < count - 1 and visits < 1024:
        let candidate: i64 = choices[part]
        if candidate < 0:
            part += 1
            continue
        visits += 1
        relation = parts[part + 1].relation
        choices[part] = -1
        if relation == ' ' or relation == '~': choices[part] = css_selector_step(context, candidate, relation)
        if not css_selector_part_matches(context, &parts[part], candidate): continue
        if part == 0: return true
        part -= 1
        choices[part] = css_selector_step(context, candidate, parts[part + 1].relation)
    return false

unsafe fn css_selector_specificity(source: string, selector: ptr<CssSelector>) -> i64:
    let length: i64 = __volt_strlen(source)
    if selector.start < 0 or selector.length < 1 or selector.start > length or selector.length > length - selector.start: return -1
    return css_specificity_range(source as ptr<char>, selector.start, selector.start + selector.length)

unsafe fn css_specificity_range(p: ptr<char>, start: i64, end: i64) -> i64:
    let at: i64 = start
    let ids: i64 = 0
    let classes: i64 = 0
    let tags: i64 = 0
    let compound_start: bool = true
    let type_seen: bool = false
    while at < end:
        if p[at] == '[':
            at += 1
            if css_find_delimiter(p, &at, end, ']', ']') < 0 or at == end: return -1
            classes += 1
            compound_start = false
        elif css_space(p[at]) or css_combinator(p[at]):
            compound_start = true
            type_seen = false
        else:
            if p[at] == '#': ids += 1
            if p[at] == '.': classes += 1
            if compound_start and p[at] != '#' and p[at] != '.' and p[at] != '*' and not type_seen:
                tags += 1
                type_seen = true
            compound_start = false
        at += 1
    if ids > 999 or classes > 999 or tags > 999: return -1
    return ids * 1000000 + classes * 1000 + tags

# Return the winning declaration index for one property, or -1 if unmatched.
unsafe fn css_cascade_property(context: ptr<CssCascadeContext>, property: string) -> Result<i64, i32>:
    return css_cascade_supported(context, property, false, __volt_strlen(context.css_source))

unsafe fn css_cascade_supported(context: ptr<CssCascadeContext>, property: string, skip_unsupported: bool, css_length: i64) -> Result<i64, i32>:
    if context.rule_count < 0 or context.rule_count > 1024 or context.selector_count < 0 or context.selector_count > 4096 or context.declaration_count < 0 or context.declaration_count > 8192: return Err(22 as i32)
    if context.node_count < 1 or context.node_index < 0 or context.node_index >= context.node_count: return Err(22 as i32)
    let winner: i64 = -1
    let winner_important: bool = false
    let winner_specificity: i64 = -1
    let rule_index: i64 = 0
    while rule_index < context.rule_count:
        let rule: ptr<CssRule> = &context.rules[rule_index]
        if rule.selector_start < 0 or rule.selector_count < 0 or rule.selector_start > context.selector_count or rule.selector_count > context.selector_count - rule.selector_start: return Err(22 as i32)
        let matched_specificity: i64 = -1
        let selector_offset: i64 = 0
        while selector_offset < rule.selector_count:
            let selector_index: i64 = rule.selector_start + selector_offset
            let selector: ptr<CssSelector> = &context.selectors[selector_index]
            if selector.owner != rule_index: return Err(22 as i32)
            let match_context: CssMatchContext = CssMatchContext(context.css_source, selector, context.html_source, context.nodes, context.attributes, context.node_count, context.node_index)
            if css_selector_matches_tree_range(&match_context, css_length):
                let specificity: i64 = css_specificity_range(context.css_source as ptr<char>, selector.start, selector.start + selector.length)
                if specificity < 0: return Err(22 as i32)
                if specificity > matched_specificity: matched_specificity = specificity
            selector_offset += 1
        if matched_specificity >= 0:
            if rule.declaration_start < 0 or rule.declaration_count < 0 or rule.declaration_start > context.declaration_count or rule.declaration_count > context.declaration_count - rule.declaration_start: return Err(22 as i32)
            let declaration_offset: i64 = 0
            while declaration_offset < rule.declaration_count:
                let declaration_index: i64 = rule.declaration_start + declaration_offset
                let declaration: ptr<CssDeclaration> = &context.declarations[declaration_index]
                if declaration.owner != rule_index: return Err(22 as i32)
                if declaration.property_start < 0 or declaration.property_length < 1 or declaration.value_start < 0 or declaration.value_length < 1 or declaration.property_start > css_length or declaration.property_length > css_length - declaration.property_start or declaration.value_start > css_length or declaration.value_length > css_length - declaration.value_start: return Err(22 as i32)
                if css_matches_property(context.css_source, declaration, property, skip_unsupported) and (not skip_unsupported or css_supported_value(context.css_source, declaration, property)):
                    let same_importance: bool = declaration.important and winner_important or not declaration.important and not winner_important
                    let wins: bool = winner == -1 or declaration.important and not winner_important
                    if same_importance and matched_specificity > winner_specificity: wins = true
                    if same_importance and matched_specificity == winner_specificity and declaration_index > winner: wins = true
                    if wins:
                        winner = declaration_index
                        winner_important = declaration.important
                        winner_specificity = matched_specificity
                declaration_offset += 1
        rule_index += 1
    return Ok(winner)

unsafe fn css_matches_property(source: string, declaration: ptr<CssDeclaration>, property: string, browser: bool) -> bool:
    if css_property_equal(source, declaration, property): return true
    return browser and property == "background" and css_property_equal(source, declaration, "background-color")

unsafe fn css_supported_value(source: string, declaration: ptr<CssDeclaration>, property: string) -> bool:
    if property == "color": return css_color_value(source, declaration) >= 0
    if property == "background": return css_color_value(source, declaration) >= 0 or css_value_equal(source, declaration, "transparent")
    if property == "margin":
        let margin: i64 = 0
        return css_margin_value(source, declaration, &margin) and margin >= 0
    if property == "display":
        return css_value_equal(source, declaration, "none") or css_value_equal(source, declaration, "block") or css_value_equal(source, declaration, "inline")
    return true

unsafe fn css_collect_style_attribute(context: ptr<CssCascadeContext>, output: ptr<char>, names: ptr<string>, winners: ptr<CssDeclaration>, html_length: i64) -> bool:
    let node: ptr<HtmlNode> = &context.nodes[context.node_index]
    if node.kind != HTML_ELEMENT: return false
    let index: i64 = css_find_html_attribute(context.html_source, node, context.attributes, "style")
    if index < 0: return false
    let attr: ptr<HtmlAttribute> = &context.attributes[index]
    if not attr.has_value: return false
    # shortcut: ignore oversized style attributes until declaration parsing can read directly from the DOM range.
    let length: i64 = html_decode_range(context.html_source as ptr<char>, html_length, attr.value_start, attr.value_length, output, 4097)
    if length <= 0: return false
    let source: string = output as string
    let position: i64 = 0
    while position < length:
        css_skip_space(output, &position, length)
        if position >= length: break
        let comment: i64 = css_skip_comment(output, &position, length)
        if comment < 0: return false
        if comment > 0: continue
        if output[position] == ';':
            position += 1
            continue
        let declaration: CssDeclaration
        if css_read_declaration(output, &position, length, &declaration) != 0: return false
        if position < length and output[position] == '}': return false
        let field: i64 = 0
        while field < 4:
            if css_matches_property(source, &declaration, names[field], true) and css_supported_value(source, &declaration, names[field]):
                if not winners[field].important or declaration.important: winners[field] = declaration
                break
            field += 1
    return true

unsafe fn css_compute_style(context: ptr<CssCascadeContext>, style: ptr<CssComputedStyle>) -> Result<i64, i32>:
    style.color = -1
    style.background = -1
    style.margin = -1
    style.display = -1
    let result: Result<i64, i32> = css_cascade_property(context, "color")
    match result:
        Ok(index): style.color = index
        Err(error): return Err(error)
    match css_cascade_property(context, "background"):
        Ok(index): style.background = index
        Err(error): return Err(error)
    match css_cascade_property(context, "margin"):
        Ok(index): style.margin = index
        Err(error): return Err(error)
    match css_cascade_property(context, "display"):
        Ok(index): style.display = index
        Err(error): return Err(error)
    let count: i64 = 0
    if style.color >= 0: count += 1
    if style.background >= 0: count += 1
    if style.margin >= 0: count += 1
    if style.display >= 0: count += 1
    return Ok(count)

unsafe fn css_resolve_style(context: ptr<CssCascadeContext>, style: ptr<CssResolvedStyle>) -> Result<i64, i32>:
    let lengths: CssSourceLengths = CssSourceLengths(__volt_strlen(context.css_source), 0)
    return css_resolve_supported(context, style, false, 0, &lengths)

struct CssSourceLengths:
    css: i64
    html: i64

unsafe fn css_resolve_supported(context: ptr<CssCascadeContext>, style: ptr<CssResolvedStyle>, skip_unsupported: bool, inherited_color: i64, lengths: ptr<CssSourceLengths>) -> Result<i64, i32>:
    style.color_rgb = inherited_color
    style.background_rgb = -1
    style.margin_px = 0
    style.display = 1
    let names: [4]string = ["color", "background", "margin", "display"]
    let inline_bytes: [4097]char
    let inline_winners: [4]CssDeclaration
    let has_inline: bool = skip_unsupported and css_collect_style_attribute(context, &inline_bytes[0], &names[0], &inline_winners[0], lengths.html)
    let field: i64 = 0
    while field < 4:
        let index: i64 = -1
        match css_cascade_supported(context, names[field], skip_unsupported, lengths.css):
            Ok(found): index = found
            Err(error): return Err(error)
        let declaration: ptr<CssDeclaration> = 0 as ptr<CssDeclaration>
        let source: string = context.css_source
        if index >= 0: declaration = &context.declarations[index]
        if has_inline and inline_winners[field].value_length > 0:
            if declaration == (0 as ptr<CssDeclaration>) or not declaration.important or inline_winners[field].important:
                declaration = &inline_winners[field]
                source = (&inline_bytes[0]) as string
        if declaration != (0 as ptr<CssDeclaration>):
            if field == 0:
                style.color_rgb = css_color_value(source, declaration)
                if style.color_rgb < 0: return Err(95 as i32)
            elif field == 1:
                style.background_rgb = css_color_value(source, declaration)
                if style.background_rgb < 0 and not (skip_unsupported and css_value_equal(source, declaration, "transparent")): return Err(95 as i32)
            elif field == 2:
                if not css_margin_value(source, declaration, &style.margin_px): return Err(95 as i32)
            else:
                if css_value_equal(source, declaration, "none"): style.display = 0
                elif css_value_equal(source, declaration, "block"): style.display = 2
                elif not css_value_equal(source, declaration, "inline"): return Err(95 as i32)
        field += 1
    return Ok(4)

unsafe fn css_emit_word(context: ptr<CssLayoutContext>, cursor: ptr<CssFlowCursor>, node_index: i64, decoded: ptr<char>, start: i64, length: i64) -> i64:
    if node_index < 0 or node_index >= context.style_count: return -22
    let color: i64 = context.styles[node_index].color_rgb
    if color < 0 or color > 16777215: return -22
    if length <= 0 or start < 0 or length > HTML_DOCUMENT_LIMIT - start: return -22
    if cursor.width < 1 or cursor.x < cursor.origin_x or cursor.x - cursor.origin_x > cursor.width: return -22
    if length > 357913941: return -22
    if cursor.width > 357913941: return -22
    let word_width: i64 = utf8_count(decoded + start, length) * 6
    let space_width: i64 = 0
    if cursor.pending_space and cursor.occupied: space_width = 6
    let remaining: i64 = cursor.width - (cursor.x - cursor.origin_x)
    let wrap_word: bool = cursor.occupied and (space_width > remaining or word_width > remaining - space_width)
    if wrap_word: space_width = 0
    if context.fragment_count < 0 or context.fragment_count > context.fragment_capacity or context.fragment_count > CSS_FRAGMENT_LIMIT or context.text_length < 0 or context.text_length > context.text_capacity: return -22
    let needed_fragments: i64 = 1
    let needed_text: i64 = length
    if cursor.pending_space and cursor.occupied and not wrap_word:
        needed_fragments += 1
        needed_text += 1
    if needed_fragments > context.fragment_capacity - context.fragment_count or needed_fragments > CSS_FRAGMENT_LIMIT - context.fragment_count: return -7
    if needed_text > context.text_capacity - context.text_length: return -7
    if word_width > 9223372036854775807 - space_width: return -22
    let advance: i64 = word_width + space_width
    if cursor.x > 9223372036854775807 - advance: return -22
    if wrap_word and cursor.y > 9223372036854775807 - 16: return -22
    if wrap_word:
        cursor.x = cursor.origin_x
        cursor.y += 16
        cursor.occupied = false
        cursor.pending_space = false
    if cursor.pending_space and cursor.occupied:
        context.text_bytes[context.text_length] = ' '
        context.fragments[context.fragment_count].node_index = node_index
        context.fragments[context.fragment_count].byte_start = context.text_length
        context.fragments[context.fragment_count].byte_length = 1
        context.fragments[context.fragment_count].x = cursor.x
        context.fragments[context.fragment_count].y = cursor.y
        context.fragments[context.fragment_count].color_rgb = color
        context.fragments[context.fragment_count].clip_x = cursor.origin_x
        context.fragments[context.fragment_count].clip_y = cursor.origin_y
        context.fragments[context.fragment_count].clip_width = cursor.width
        context.fragments[context.fragment_count].clip_height = 2147483647
        context.fragments[context.fragment_count].advance = 0
        context.fragments[context.fragment_count].line_height = 0
        context.fragments[context.fragment_count].baseline = 0
        context.text_length += 1
        context.fragment_count += 1
        cursor.x += 6
    let i: i64 = 0
    while i < length:
        context.text_bytes[context.text_length + i] = decoded[start + i]
        i += 1
    context.fragments[context.fragment_count].node_index = node_index
    context.fragments[context.fragment_count].byte_start = context.text_length
    context.fragments[context.fragment_count].byte_length = length
    context.fragments[context.fragment_count].x = cursor.x
    context.fragments[context.fragment_count].y = cursor.y
    context.fragments[context.fragment_count].color_rgb = color
    context.fragments[context.fragment_count].clip_x = cursor.origin_x
    context.fragments[context.fragment_count].clip_y = cursor.origin_y
    context.fragments[context.fragment_count].clip_width = cursor.width
    context.fragments[context.fragment_count].clip_height = 2147483647
    context.fragments[context.fragment_count].advance = 0
    context.fragments[context.fragment_count].line_height = 0
    context.fragments[context.fragment_count].baseline = 0
    context.text_length += length
    context.fragment_count += 1
    # shortcut: clip words wider than the viewport until character-level wrapping is implemented.
    cursor.x += min(word_width, cursor.width - (cursor.x - cursor.origin_x))
    cursor.pending_space = false
    cursor.occupied = true
    return 0

unsafe fn css_hide_subtree(context: ptr<CssLayoutContext>, parent_index: i64, depth: i64) -> i64:
    if depth > 128: return -22
    let nodes: ptr<HtmlNode> = context.nodes
    let boxes: ptr<CssLayoutBox> = context.boxes
    let child: i64 = nodes[parent_index].first_child
    let steps: i64 = 0
    while child >= 0:
        if steps >= context.node_count or child >= context.node_count or nodes[child].parent != parent_index: return -22
        let next: i64 = nodes[child].next_sibling
        if next >= context.node_count: return -22
        boxes[child].hidden = true
        let status: i64 = css_hide_subtree(context, child, depth + 1)
        if status < 0: return status
        child = next
        steps += 1
    return 0

unsafe fn css_legacy_hide(context: ptr<CssLayoutContext>, parent_index: i64, depth: i64) -> i64:
    if depth > 128: return -22
    let child: i64 = context.nodes[parent_index].first_child
    let steps: i64 = 0
    while child >= 0:
        if steps >= context.node_count or child >= context.node_count: return -22
        context.boxes[child].hidden = true
        let next: i64 = context.nodes[child].next_sibling
        let status: i64 = css_legacy_hide(context, child, depth + 1)
        if status < 0: return status
        child = next
        steps += 1
    return 0

struct CssTextScratch:
    data: ptr<char>
    capacity: i64
    source_length: i64
    overrides: ptr<CssTextOverrides>

const CSS_TEXT_OVERRIDE_LIMIT: i64 = 64
const CSS_OVERRIDE_BYTES: i64 = 4096

struct CssTextOverride:
    node: i64
    length: i64
    text: [4096]char

struct CssTextOverrides:
    count: i64
    total: i64
    entries: [64]CssTextOverride

unsafe fn css_text_override(overrides: ptr<CssTextOverrides>, node: i64) -> ptr<CssTextOverride>:
    if overrides == (0 as ptr<CssTextOverrides>): return 0 as ptr<CssTextOverride>
    let low: i64 = 0
    let high: i64 = overrides.count
    while low < high:
        let mid: i64 = (low + high) / 2
        let entry: ptr<CssTextOverride> = &overrides.entries[mid]
        if entry.node == node: return entry
        if entry.node < node: low = mid + 1
        else: high = mid
    return 0 as ptr<CssTextOverride>

unsafe fn css_flow_text(context: ptr<CssLayoutContext>, cursor: ptr<CssFlowCursor>, node: i64, decoded: ptr<char>, length: i64) -> i64:
    let pos: i64 = 0
    while pos < length:
        while pos < length and css_space(decoded[pos]):
            cursor.pending_space = true
            pos += 1
        if pos >= length: break
        let start: i64 = pos
        while pos < length and not css_space(decoded[pos]): pos += 1
        let emit: i64 = css_emit_word(context, cursor, node, decoded, start, pos - start)
        if emit < 0: return emit
    return 0

unsafe fn css_flow_list(context: ptr<CssLayoutContext>, parent_index: i64, cursor: ptr<CssFlowCursor>, depth: i64, scratch: ptr<CssTextScratch>) -> i64:
    if depth > 128: return -22
    let override: ptr<CssTextOverride> = css_text_override(scratch.overrides, parent_index)
    if override != (0 as ptr<CssTextOverride>):
        let hidden: i64 = css_hide_subtree(context, parent_index, depth)
        if hidden < 0: return hidden
        return css_flow_text(context, cursor, parent_index, &override.text[0], override.length)
    let nodes: ptr<HtmlNode> = context.nodes
    let styles: ptr<CssResolvedStyle> = context.styles
    let boxes: ptr<CssLayoutBox> = context.boxes
    let child: i64 = nodes[parent_index].first_child
    let steps: i64 = 0
    while child >= 0:
        if steps >= context.node_count or child >= context.node_count: return -22
        if nodes[child].parent != parent_index: return -22
        let next: i64 = nodes[child].next_sibling
        if next >= context.node_count: return -22
        if styles[child].display != 0 and not boxes[parent_index].hidden:
            boxes[child].hidden = false
            let child_display: i64 = styles[child].display
            if parent_index == 0 and child_display == 1:
                child_display = 2
            if nodes[child].kind == HTML_TEXT_NODE:
                let decoded: ptr<char> = scratch.data
                let length: i64 = html_decode_range(context.html_source as ptr<char>, scratch.source_length, nodes[child].text_start, nodes[child].text_length, decoded, scratch.capacity)
                if length < 0: return length
                let emit: i64 = css_flow_text(context, cursor, child, decoded, length)
                if emit < 0: return emit
            elif nodes[child].kind == HTML_ELEMENT and child_display == 1:
                let first_fragment: i64 = context.fragment_count
                boxes[child].y = cursor.y
                let status: i64 = css_flow_list(context, child, cursor, depth + 1, scratch)
                if status < 0: return status
                if context.fragment_count > first_fragment: boxes[child].y = context.fragments[first_fragment].y
            elif nodes[child].kind == HTML_ELEMENT and child_display == 2:
                if cursor.occupied:
                    if cursor.y > 9223372036854775807 - 16: return -22
                    cursor.y += 16
                    cursor.x = cursor.origin_x
                    cursor.occupied = false
                    cursor.pending_space = false
                let margin: i64 = styles[child].margin_px
                if margin < 0 or cursor.width < 1: return -22
                margin = min(margin, (cursor.width - 1) / 2)
                let bx: i64 = cursor.origin_x + margin
                let by: i64 = cursor.y + margin
                if bx < cursor.origin_x or by < cursor.y: return -22
                boxes[child] = CssLayoutBox(bx, by, cursor.width - margin * 2, 0, false)
                let block_cursor: CssFlowCursor = CssFlowCursor(bx, by, boxes[child].width, bx, by, 16, false, false)
                let status: i64 = css_flow_list(context, child, &block_cursor, depth + 1, scratch)
                if status < 0: return status
                let block_height: i64 = block_cursor.y - by
                if block_cursor.occupied: block_height += 16
                if margin > (9223372036854775807 - block_height) / 2: return -22
                block_height += margin * 2
                boxes[child].height = block_height
                cursor.y = by + block_height + margin
                if cursor.y < by: return -22
                cursor.x = cursor.origin_x
                cursor.occupied = false
                cursor.pending_space = false
            else:
                boxes[child].hidden = true
        else:
            boxes[child].hidden = true
            let hide_status: i64 = css_hide_subtree(context, child, depth + 1)
            if hide_status < 0: return hide_status
        child = next
        steps += 1
    return 0

unsafe fn css_layout_blocks(context: ptr<CssLayoutContext>) -> Result<i64, i32>:
    return css_layout_text(context, 0 as ptr<CssTextOverrides>)

unsafe fn css_layout_text(context: ptr<CssLayoutContext>, overrides: ptr<CssTextOverrides>) -> Result<i64, i32>:
    let nodes: ptr<HtmlNode> = context.nodes
    let node_count: i64 = context.node_count
    let styles: ptr<CssResolvedStyle> = context.styles
    let boxes: ptr<CssLayoutBox> = context.boxes
    if node_count < 1 or node_count > HTML_NODE_LIMIT or context.style_count != node_count or context.box_capacity < node_count or context.viewport_width < 1 or context.viewport_width > 357913941: return Err(22 as i32)
    let flow_enabled: bool = context.flow_enabled
    if flow_enabled and (context.fragments == (0 as ptr<CssFlowFragment>) or context.text_bytes == (0 as ptr<char>) or context.fragment_capacity < 1 or context.fragment_capacity > CSS_FRAGMENT_LIMIT or context.text_capacity < 1 or context.text_capacity > HTML_DOCUMENT_LIMIT): return Err(22 as i32)
    context.fragment_count = 0
    context.text_length = 0
    if not flow_enabled:
        let i: i64 = 0
        while i < node_count:
            boxes[i] = CssLayoutBox(0, 0, 0, 0, false)
            if nodes[i].parent < -1 or nodes[i].parent >= node_count or nodes[i].parent == i: return Err(22 as i32)
            i += 1
        boxes[0] = CssLayoutBox(0, 0, context.viewport_width, 0, false)
        let y: i64 = 0
        i = 1
        while i < node_count:
            if nodes[i].kind == HTML_ELEMENT and styles[i].display != 0:
                if styles[i].display == 2:
                    let margin: i64 = styles[i].margin_px
                    if margin < 0 or margin > (2147483647 - context.viewport_width) / 2: return Err(22 as i32)
                    y += margin
                    boxes[i] = CssLayoutBox(margin, y, context.viewport_width - margin * 2, 16, false)
                    y += 16 + margin
                else:
                    boxes[i] = CssLayoutBox(0, y, context.viewport_width, 16, false)
            else:
                boxes[i] = CssLayoutBox(0, y, context.viewport_width, 16, true)
                let hide_status: i64 = css_legacy_hide(context, i, 0)
                if hide_status < 0: return Err((0 - hide_status) as i32)
            i += 1
        boxes[0].height = y
        return Ok(node_count)
    let i: i64 = 0
    let source_length: i64 = __volt_strlen(context.html_source)
    if source_length > HTML_DOCUMENT_LIMIT: return Err(7 as i32)
    let max_text_length: i64 = 0
    while i < node_count:
        boxes[i] = CssLayoutBox(0, 0, 0, 0, false)
        if nodes[i].parent < -1 or nodes[i].parent >= node_count or nodes[i].parent == i: return Err(22 as i32)
        if nodes[i].kind == HTML_TEXT_NODE:
            let length: i64 = nodes[i].text_length
            if length < 0 or length > source_length: return Err(22 as i32)
            max_text_length = max(max_text_length, length)
        i += 1
    let decoded: Buffer<char>
    defer buffer_free(&decoded)
    let allocated: i64 = buffer_reserve(&decoded, max_text_length + 1)
    if allocated < 0: return Err((0 - allocated) as i32)
    let scratch: CssTextScratch = CssTextScratch(buffer_data(&decoded), max_text_length + 1, source_length, overrides)
    boxes[0] = CssLayoutBox(0, 0, context.viewport_width, 0, false)
    let root_cursor: CssFlowCursor = CssFlowCursor(0, 0, context.viewport_width, 0, 0, 16, false, false)
    let status: i64 = css_flow_list(context, 0, &root_cursor, 0, &scratch)
    if status < 0: return Err((0 - status) as i32)
    if root_cursor.occupied:
        if root_cursor.y > 9223372036854775807 - 16: return Err(22 as i32)
        root_cursor.y += 16
    boxes[0].height = root_cursor.y
    return Ok(node_count)

unsafe fn css_collect_inline_styles(html_source: string, nodes: ptr<HtmlNode>, node_count: i64, out: ptr<char>, capacity: i64) -> i64:
    if node_count < 1 or node_count > HTML_NODE_LIMIT or capacity < 1 or capacity > CSS_STYLESHEET_LIMIT + 1: return -22
    let source_length: i64 = __volt_strlen(html_source)
    let written: i64 = 0
    let i: i64 = 1
    while i < node_count:
        if nodes[i].kind == HTML_TEXT_NODE:
            let parent: i64 = nodes[i].parent
            if parent > 0 and parent < node_count and nodes[parent].kind == HTML_ELEMENT and html_name_equal(html_source, &nodes[parent], "style"):
                if nodes[i].text_start < 0 or nodes[i].text_length < 0 or nodes[i].text_start > source_length or nodes[i].text_length > source_length - nodes[i].text_start: return -22
                if nodes[i].text_length > capacity - written - 2: return -7
                let source: ptr<char> = html_source as ptr<char>
                let j: i64 = 0
                while j < nodes[i].text_length:
                    out[written + j] = source[nodes[i].text_start + j]
                    j += 1
                written += nodes[i].text_length
                out[written] = '\n'
                written += 1
        i += 1
    out[written] = '\0'
    return written

unsafe fn css_prepare_document(context: ptr<CssDocumentContext>) -> Result<i64, i32>:
    return css_prepare_document_mode(context, false)

unsafe fn css_prepare_document_mode(context: ptr<CssDocumentContext>, skip_unsupported: bool) -> Result<i64, i32>:
    css_prepare_styles(context, skip_unsupported)?
    return css_layout_blocks(context.layout)

unsafe fn css_prepare_styles(context: ptr<CssDocumentContext>, skip_unsupported: bool) -> Result<i64, i32>:
    if context.cascade.node_count < 1 or context.cascade.node_count > HTML_NODE_LIMIT or context.style_capacity < context.cascade.node_count: return Err(22 as i32)
    let lengths: CssSourceLengths = CssSourceLengths(__volt_strlen(context.cascade.css_source), __volt_strlen(context.cascade.html_source))
    let node_index: i64 = 0
    while node_index < context.cascade.node_count:
        let parent: i64 = context.cascade.nodes[node_index].parent
        if node_index == 0:
            if parent != -1: return Err(22 as i32)
        elif parent < 0 or parent >= node_index:
            return Err(22 as i32)
        context.cascade.node_index = node_index
        let inherited_color: i64 = 0
        if parent >= 0: inherited_color = context.styles[parent].color_rgb
        if context.cascade.nodes[node_index].kind == HTML_ELEMENT:
            css_resolve_supported(context.cascade, &context.styles[node_index], skip_unsupported, inherited_color, &lengths)?
        else:
            context.styles[node_index] = CssResolvedStyle(inherited_color, -1, 0, 1)
        node_index += 1
    context.layout.nodes = context.cascade.nodes
    context.layout.node_count = context.cascade.node_count
    context.layout.styles = context.styles
    context.layout.style_count = context.cascade.node_count
    context.layout.html_source = context.cascade.html_source
    return Ok(context.layout.node_count)

# EOF inside an unfinished rule cannot discard fully parsed rules from the same sheet.
fn css_parse_tail(rule_count: i64) -> i64:
    if rule_count == 0: return -22
    return rule_count

# Parses simple selector blocks. Returns rule count or a negative errno-like code.
unsafe fn css_parse(source: string, buffers: ptr<CssBuffers>) -> i64:
    if buffers.rule_capacity < 0 or buffers.rule_capacity > 1024 or buffers.selector_capacity < 0 or buffers.selector_capacity > 4096 or buffers.declaration_capacity < 0 or buffers.declaration_capacity > 8192: return -22
    let length: i64 = __volt_strlen(source)
    if length > CSS_STYLESHEET_LIMIT: return -7
    let counts: CssParseCounts
    return css_parse_range(source as ptr<char>, 0, length, buffers, &counts, false)

struct CssParseCounts:
    rule_count: i64
    selector_count: i64
    declaration_count: i64

struct CssMediaRange:
    min_width: i64
    max_width: i64

# shortcut: support screen/all and conjunctions of min/max-width in px until a media-query parser is available.
unsafe fn css_media_range(p: ptr<char>, start: i64, end: i64, bounds: ptr<CssMediaRange>) -> bool:
    let i: i64 = css_trim_start(p, start, end)
    let first: bool = true
    while i < end:
        if not first:
            let keyword: i64 = i
            while i < end and not css_space(p[i]) and p[i] != '(': i += 1
            if not css_range_equal(p as string, keyword, i - keyword, "and"): return false
            i = css_trim_start(p, i, end)
            if i >= end or p[i] != '(': return false
        if p[i] != '(':
            let kind: i64 = i
            while i < end and not css_space(p[i]): i += 1
            if not css_range_equal(p as string, kind, i - kind, "screen") and not css_range_equal(p as string, kind, i - kind, "all"): return false
        else:
            i = css_trim_start(p, i + 1, end)
            let key: i64 = i
            while i < end and p[i] != ':' and p[i] != ')': i += 1
            if i == end or p[i] != ':': return false
            let key_end: i64 = css_trim_end(p, key, i)
            let minimum: bool = css_range_equal(p as string, key, key_end - key, "min-width")
            if not minimum and not css_range_equal(p as string, key, key_end - key, "max-width"): return false
            i = css_trim_start(p, i + 1, end)
            let digits: i64 = i
            let pixels: i64 = 0
            while i < end and p[i] >= '0' and p[i] <= '9':
                pixels = pixels * 10 + (p[i] as i64 - 48)
                if pixels > 100000: return false
                i += 1
            if i == digits or i + 2 > end or not css_range_equal(p as string, i, 2, "px"): return false
            i = css_trim_start(p, i + 2, end)
            if i == end or p[i] != ')': return false
            if minimum: bounds.min_width = max(bounds.min_width, pixels)
            else: bounds.max_width = min(bounds.max_width, pixels)
            i += 1
        i = css_trim_start(p, i, end)
        first = false
    return not first

unsafe fn css_parse_range(p: ptr<char>, start: i64, length: i64, buffers: ptr<CssBuffers>, counts: ptr<CssParseCounts>, media: bool) -> i64:
    let position: i64 = start
    let rule_count: i64 = counts.rule_count
    let selector_count: i64 = counts.selector_count
    let declaration_count: i64 = counts.declaration_count
    let end: i64 = length
    let media_end: i64 = -1
    let bounds: CssMediaRange = CssMediaRange(0, 100000)
    while position < end or media_end >= 0:
        css_skip_space(p, &position, end)
        if position >= end:
            if media_end < 0: break
            position = media_end + 1
            media_end = -1
            end = length
            bounds = CssMediaRange(0, 100000)
            continue
        let comment: i64 = css_skip_comment(p, &position, end)
        if comment < 0: return css_parse_tail(rule_count)
        if comment > 0: continue
        if p[position] == '@':
            let prefix: i64 = position + 1
            let boundary: i64 = css_find_delimiter(p, &position, end, ';', '{')
            if boundary < 0: return css_parse_tail(rule_count)
            if boundary == end: break
            if p[boundary] == '{':
                position += 1
                let close: i64 = css_find_delimiter(p, &position, end, '}', '}')
                if close < 0 or close == end: return css_parse_tail(rule_count)
                if media and media_end < 0 and boundary > prefix + 5 and css_range_equal(p as string, prefix, 5, "media") and (css_space(p[prefix + 5]) or p[prefix + 5] == '('):
                    let query: CssMediaRange = CssMediaRange(0, 100000)
                    if css_media_range(p, prefix + 5, boundary, &query):
                        bounds = query
                        end = close
                        media_end = close
                        position = boundary + 1
                        continue
            position += 1
            continue
        if p[position] == '}':
            position += 1
            continue
        let selector_start: i64 = position
        let opening: i64 = css_find_delimiter(p, &position, end, '{', '}')
        if opening < 0 or opening == end: return css_parse_tail(rule_count)
        if p[opening] == '}':
            position += 1
            continue
        let selector_begin: i64 = css_trim_start(p, selector_start, opening)
        let selector_end: i64 = css_trim_end(p, selector_begin, opening)
        position = opening + 1
        let rule_index: i64 = rule_count
        let selectors_before: i64 = selector_count
        let declarations_before: i64 = declaration_count
        let selector_buffers: CssSelectorBuffers = CssSelectorBuffers(buffers.selectors, &selector_count, buffers.selector_capacity)
        let split_status: i64 = css_selector_split(p, selector_begin, selector_end, rule_index, &selector_buffers)
        if split_status == -7: return -7
        if split_status < 0:
            selector_count = selectors_before
            let close: i64 = css_find_delimiter(p, &position, end, '}', '}')
            if close < 0 or close == end: return css_parse_tail(rule_count)
            position += 1
            continue
        if rule_count >= buffers.rule_capacity: return -7
        while true:
            css_skip_space(p, &position, end)
            let inner_comment: i64 = css_skip_comment(p, &position, end)
            if inner_comment < 0 or position >= end: return css_parse_tail(rule_count)
            if inner_comment > 0: continue
            if p[position] == '}':
                position += 1
                break
            if p[position] == ';':
                position += 1
                continue
            let declaration: CssDeclaration
            let parsed: i64 = css_read_declaration(p, &position, end, &declaration)
            if parsed < 0: return css_parse_tail(rule_count)
            if parsed != 0: continue
            if declaration_count >= buffers.declaration_capacity: return -7
            declaration.owner = rule_index
            buffers.declarations[declaration_count] = declaration
            declaration_count += 1
        buffers.rules[rule_index] = CssRule(selectors_before, selector_count - selectors_before, declarations_before, declaration_count - declarations_before, bounds.min_width, bounds.max_width)
        rule_count += 1
        counts.rule_count = rule_count
        counts.selector_count = selector_count
        counts.declaration_count = declaration_count
    return rule_count
