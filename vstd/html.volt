# Bounded HTML tokenizer and tree builder. This is not an HTML5 parser.
use utf8

const HTML_TEXT: i64 = 1
const HTML_START_TAG: i64 = 2
const HTML_END_TAG: i64 = 3
const HTML_COMMENT: i64 = 4
const HTML_DOCTYPE: i64 = 5
const HTML_EOF: i64 = 0
const HTML_ERROR: i64 = -1

const HTML_DOCUMENT: i64 = 0
const HTML_ELEMENT: i64 = 1
const HTML_TEXT_NODE: i64 = 2

const HTML_DOCUMENT_LIMIT: i64 = 2097152
const HTML_NODE_LIMIT: i64 = 65536
const HTML_ATTRIBUTE_LIMIT: i64 = 131072
const HTML_DEPTH_EXCEEDED: i64 = -40

struct HtmlToken:
    kind: i64
    start: i64
    length: i64
    raw_start: i64
    raw_length: i64
    self_closing: bool

struct HtmlNode:
    kind: i64
    parent: i64
    first_child: i64
    last_child: i64
    next_sibling: i64
    name_start: i64
    name_length: i64
    attribute_start: i64
    attribute_count: i64
    raw_start: i64
    raw_length: i64
    text_start: i64
    text_length: i64
    previous_element: i64

struct HtmlAttribute:
    owner: i64
    name_start: i64
    name_length: i64
    value_start: i64
    value_length: i64
    has_value: bool

unsafe fn html_space(c: char) -> bool:
    return c == ' ' or c == '\t' or c == '\n' or c == '\r'

unsafe fn html_match(p: ptr<char>, at: i64, limit: i64, pattern: string) -> bool:
    let q: ptr<char> = pattern as ptr<char>
    let n: i64 = __volt_strlen(pattern)
    if at < 0 or n > limit - at:
        return false
    let i: i64 = 0
    while i < n:
        if p[at + i] != q[i]:
            return false
        i += 1
    return true

# Returns one token and advances position. Names/text refer to the original source.
unsafe fn html_next(source: string, position: ptr<i64>, token: ptr<HtmlToken>) -> i64:
    return html_next_range(source as ptr<char>, __volt_strlen(source), position, token)

unsafe fn html_next_range(p: ptr<char>, length: i64, position: ptr<i64>, token: ptr<HtmlToken>) -> i64:
    let at: i64 = position[0]
    if at < 0 or at > length:
        return HTML_ERROR
    if at == length:
        token.kind = HTML_EOF
        token.start = at
        token.length = 0
        token.raw_start = at
        token.raw_length = 0
        token.self_closing = false
        return HTML_EOF
    token.self_closing = false
    if p[at] != '<':
        let start: i64 = at
        while at < length and p[at] != '<':
            at += 1
        token.kind = HTML_TEXT
        token.start = start
        token.length = at - start
        token.raw_start = start
        token.raw_length = at - start
        position[0] = at
        return HTML_TEXT
    if html_match(p, at, length, "<!--"):
        let start: i64 = at + 4
        at = start
        while at < length and not html_match(p, at, length, "-->"):
            at += 1
        if at == length:
            return HTML_ERROR
        token.kind = HTML_COMMENT
        token.start = start
        token.length = at - start
        token.raw_start = start - 4
        token.raw_length = at + 3 - token.raw_start
        position[0] = at + 3
        return HTML_COMMENT
    if html_match(p, at, length, "<!") or html_match(p, at, length, "<?"):
        while at < length and p[at] != '>':
            at += 1
        if at == length:
            return HTML_ERROR
        token.kind = HTML_DOCTYPE
        token.start = at
        token.length = 0
        token.raw_start = position[0]
        token.raw_length = at + 1 - position[0]
        position[0] = at + 1
        return HTML_DOCTYPE
    at += 1
    let kind: i64 = HTML_START_TAG
    if at < length and p[at] == '/':
        kind = HTML_END_TAG
        at += 1
    while at < length and html_space(p[at]):
        at += 1
    let start: i64 = at
    while at < length and not html_space(p[at]) and p[at] != '/' and p[at] != '>':
        at += 1
    if at == start:
        return HTML_ERROR
    token.start = start
    token.length = at - start
    token.kind = kind
    token.raw_start = position[0]
    let quote: char = '\0'
    let last_nonspace: char = '\0'
    let last_nonspace_at: i64 = -1
    while at < length:
        let c: char = p[at]
        if quote != '\0':
            if c == quote: quote = '\0'
        else:
            if c == '\'' or c == '"':
                quote = c
            else:
                if c == '>': break
                if not html_space(c):
                    last_nonspace = c
                    last_nonspace_at = at
        at += 1
    if at == length:
        return HTML_ERROR
    if quote != '\0': return HTML_ERROR
    token.self_closing = kind == HTML_START_TAG and last_nonspace == '/' and (last_nonspace_at == token.start + token.length or html_space(p[last_nonspace_at - 1]))
    token.raw_length = at + 1 - token.raw_start
    position[0] = at + 1
    return kind

unsafe fn html_node_name(source: string, node: ptr<HtmlNode>) -> ptr<char>:
    if node.name_start == -1: return "html" as ptr<char>
    if node.name_start == -2: return "body" as ptr<char>
    return (source as ptr<char>) + node.name_start

unsafe fn html_name_equal(source: string, node: ptr<HtmlNode>, name: string) -> bool:
    let p: ptr<char> = html_node_name(source, node)
    let q: ptr<char> = name as ptr<char>
    let n: i64 = __volt_strlen(name)
    if node.name_length != n:
        return false
    let i: i64 = 0
    while i < n:
        let a: i64 = p[i] as i64
        let b: i64 = q[i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn html_attribute_name_equal(source: string, attribute: ptr<HtmlAttribute>, name: string) -> bool:
    let p: ptr<char> = source as ptr<char>
    let q: ptr<char> = name as ptr<char>
    let n: i64 = __volt_strlen(name)
    if attribute.name_length != n: return false
    let i: i64 = 0
    while i < n:
        let a: i64 = p[attribute.name_start + i] as i64
        let b: i64 = q[i] as i64
        if a >= 65 and a <= 90: a += 32
        if b >= 65 and b <= 90: b += 32
        if a != b: return false
        i += 1
    return true

unsafe fn html_attribute_equal(source: string, a: ptr<HtmlAttribute>, b: ptr<HtmlAttribute>) -> bool:
    let p: ptr<char> = source as ptr<char>
    if a.name_length != b.name_length: return false
    let i: i64 = 0
    while i < a.name_length:
        let x: i64 = p[a.name_start + i] as i64
        let y: i64 = p[b.name_start + i] as i64
        if x >= 65 and x <= 90: x += 32
        if y >= 65 and y <= 90: y += 32
        if x != y: return false
        i += 1
    return true

# Recognizes one single-byte named reference and returns its input length.
unsafe fn html_decode_named(source: string, at: i64, end: i64, out: ptr<char>) -> i64:
    let p: ptr<char> = source as ptr<char>
    if html_match(p, at, end, "&amp;"):
        out[0] = '&'
        return 5
    if html_match(p, at, end, "&lt;"):
        out[0] = '<'
        return 4
    if html_match(p, at, end, "&gt;"):
        out[0] = '>'
        return 4
    if html_match(p, at, end, "&quot;"):
        out[0] = '"'
        return 6
    if html_match(p, at, end, "&apos;"):
        out[0] = '\''
        return 6
    return 0

unsafe fn html_decode_numeric(p: ptr<char>, at: i64, end: i64, scalar: ptr<i64>) -> i64:
    let i: i64 = at + 2
    let base: i64 = 10
    if i < end and (p[i] == 'x' or p[i] == 'X'):
        i += 1
        base = 16
    let start: i64 = i
    let code: i64 = 0
    while i < end and p[i] != ';':
        let c: i64 = p[i] as i64
        let digit: i64 = c - 48
        if base == 16 and c >= 65 and c <= 70: digit = c - 55
        elif base == 16 and c >= 97 and c <= 102: digit = c - 87
        elif digit < 0 or digit > 9: return 0
        # Keep scanning the digits after overflow so the entire reference is consumed.
        if code <= 0x10ffff: code = code * base + digit
        i += 1
    if i == start or i == end: return 0
    if code == 0 or not utf8_is_scalar(code): code = 0xfffd
    scalar[0] = code
    return i - at + 1

# Unknown references remain literal. Capacity includes the terminator.
unsafe fn html_decode(source: string, start: i64, length: i64, out: ptr<char>, capacity: i64) -> i64:
    return html_decode_range(source as ptr<char>, __volt_strlen(source), start, length, out, capacity)

unsafe fn html_decode_range(p: ptr<char>, total: i64, start: i64, length: i64, out: ptr<char>, capacity: i64) -> i64:
    if start < 0 or length < 0 or start > total or length > total - start or capacity < 1: return -22
    let end: i64 = start + length
    let input: i64 = start
    let output: i64 = 0
    while input < end:
        let consumed: i64 = 0
        let scalar: i64 = 0
        if p[input] == '&':
            if end - input >= 2 and p[input + 1] == '#':
                consumed = html_decode_numeric(p, input, end, &scalar)
            elif html_match(p, input, end, "&nbsp;"):
                consumed = 6
                scalar = 0xa0
            else:
                let byte: char = 0 as char
                consumed = html_decode_named(p as string, input, end, &byte)
                scalar = byte as i64
        if consumed > 0:
            let written: i64 = utf8_write(scalar, out + output, capacity - output - 1)
            if written < 0: return written
            output += written
            input += consumed
        else:
            if output + 1 >= capacity: return -7
            out[output] = p[input]
            output += 1
            input += 1
    out[output] = '\0'
    return output

unsafe fn html_decode_node_text(source: string, node: ptr<HtmlNode>, out: ptr<char>, capacity: i64) -> i64:
    if node.kind != HTML_TEXT_NODE: return -22
    return html_decode(source, node.text_start, node.text_length, out, capacity)

unsafe fn html_decode_attribute(source: string, attribute: ptr<HtmlAttribute>, out: ptr<char>, capacity: i64) -> i64:
    if not attribute.has_value: return -22
    return html_decode(source, attribute.value_start, attribute.value_length, out, capacity)

unsafe fn html_raw_end(source: string, start: i64, tag: string) -> i64:
    return html_raw_end_range(source as ptr<char>, __volt_strlen(source), start, tag)

unsafe fn html_raw_end_range(p: ptr<char>, length: i64, start: i64, tag: string) -> i64:
    let tag_length: i64 = __volt_strlen(tag)
    let at: i64 = start
    while at + tag_length + 2 < length:
        if p[at] == '<' and p[at + 1] == '/':
            let j: i64 = 0
            let same: bool = true
            while j < tag_length:
                let a: i64 = p[at + 2 + j] as i64
                let q: ptr<char> = tag as ptr<char>
                let b: i64 = q[j] as i64
                if a >= 65 and a <= 90: a += 32
                if b >= 65 and b <= 90: b += 32
                if a != b: same = false
                j += 1
            if same and (html_space(p[at + 2 + tag_length]) or p[at + 2 + tag_length] == '>' or p[at + 2 + tag_length] == '/'):
                return at
        at += 1
    return length

unsafe fn html_token_is(source: string, token: ptr<HtmlToken>, name: string) -> bool:
    let p: ptr<char> = source as ptr<char>
    let q: ptr<char> = name as ptr<char>
    let n: i64 = __volt_strlen(name)
    if token.length != n: return false
    let i: i64 = 0
    while i < n:
        let c: i64 = p[token.start + i] as i64
        let d: i64 = q[i] as i64
        if c >= 65 and c <= 90: c += 32
        if d >= 65 and d <= 90: d += 32
        if c != d: return false
        i += 1
    return true

unsafe fn html_void_tag(source: string, token: ptr<HtmlToken>) -> bool:
    return html_token_is(source, token, "area") or html_token_is(source, token, "base") or html_token_is(source, token, "br") or html_token_is(source, token, "col") or html_token_is(source, token, "embed") or html_token_is(source, token, "hr") or html_token_is(source, token, "img") or html_token_is(source, token, "input") or html_token_is(source, token, "link") or html_token_is(source, token, "meta") or html_token_is(source, token, "param") or html_token_is(source, token, "source") or html_token_is(source, token, "track") or html_token_is(source, token, "wbr")

# Builds a bounded tree. Returns node count, or a negative error.
unsafe fn html_parse_attributes(source: string, token: ptr<HtmlToken>, owner: i64, attributes: ptr<HtmlAttribute>, used: ptr<i64>, capacity: i64) -> i64:
    let p: ptr<char> = source as ptr<char>
    let owner_attribute_start: i64 = used[0]
    let limit: i64 = token.raw_start + token.raw_length - 1
    let at: i64 = token.start + token.length
    while at < limit:
        while at < limit and html_space(p[at]):
            at += 1
        if at == limit: break
        if p[at] == '/' and token.self_closing: break
        let name_start: i64 = at
        while at < limit and not html_space(p[at]) and p[at] != '=' and p[at] != '>':
            if p[at] == '<' or p[at] == '\'' or p[at] == '"' or p[at] == '`': return -22
            at += 1
        if at == name_start: return -22
        let name_length: i64 = at - name_start
        while at < limit and html_space(p[at]): at += 1
        let value_start: i64 = at
        let value_length: i64 = 0
        let has_value: bool = false
        if at < limit and p[at] == '=':
            has_value = true
            at += 1
            while at < limit and html_space(p[at]): at += 1
            if at < limit and (p[at] == '\'' or p[at] == '"'):
                let quote: char = p[at]
                at += 1
                value_start = at
                while at < limit and p[at] != quote:
                    if p[at] == '<': return -22
                    at += 1
                if at == limit: return -22
                value_length = at - value_start
                at += 1
            else:
                value_start = at
                while at < limit and not html_space(p[at]):
                    if p[at] == '<' or p[at] == '\'' or p[at] == '"' or p[at] == '`' or p[at] == '=': return -22
                    at += 1
                value_length = at - value_start
        let candidate: HtmlAttribute = HtmlAttribute(owner, name_start, name_length, value_start, value_length, has_value)
        let duplicate: bool = false
        let previous: i64 = owner_attribute_start
        while previous < used[0] and not duplicate:
            if attributes[previous].owner == owner and html_attribute_equal(source, &attributes[previous], &candidate):
                duplicate = true
            previous += 1
        if not duplicate:
            if used[0] >= capacity: return -7
            attributes[used[0]] = candidate
            used[0] += 1
    return used[0] - owner_attribute_start

unsafe fn html_name_in(source: string, start: i64, length: i64, names: string) -> bool:
    let p: ptr<char> = (source as ptr<char>) + start
    let q: ptr<char> = names as ptr<char>
    let at: i64 = 0
    while q[at] != '\0':
        let first: i64 = at
        while q[at] != ' ' and q[at] != '\0': at += 1
        if at - first == length:
            let i: i64 = 0
            while i < length:
                let c: i64 = p[i] as i64
                if c >= 65 and c <= 90: c += 32
                if c != q[first + i] as i64: break
                i += 1
            if i == length: return true
        if q[at] == ' ': at += 1
    return false

unsafe fn html_close_in_scope(source: string, nodes: ptr<HtmlNode>, stack: ptr<i64>, depth: i64, tag: string, barriers: string) -> i64:
    let i: i64 = depth - 1
    while i > 0:
        let node: ptr<HtmlNode> = &nodes[stack[i]]
        if html_name_equal(source, node, tag): return i
        if html_name_in(source, node.name_start, node.name_length, barriers): break
        i -= 1
    return depth

# Builds a bounded tree and attribute table. Returns node count, or a negative error.
unsafe fn html_parse(source: string, nodes: ptr<HtmlNode>, capacity: i64, attributes: ptr<HtmlAttribute>, attribute_capacity: i64) -> i64:
    let result: i64 = html_parse_tree(source, nodes, capacity, attributes, attribute_capacity)
    if result == HTML_DEPTH_EXCEEDED: return -7
    return result

unsafe fn html_parse_tree(source: string, nodes: ptr<HtmlNode>, capacity: i64, attributes: ptr<HtmlAttribute>, attribute_capacity: i64) -> i64:
    return html_parse_tree_mode(source, nodes, capacity, attributes, attribute_capacity, false)

unsafe fn html_raw_tag(source: string, token: ptr<HtmlToken>, scripting: bool) -> string:
    if html_token_is(source, token, "script"): return "script"
    if html_token_is(source, token, "style"): return "style"
    if html_token_is(source, token, "title"): return "title"
    if html_token_is(source, token, "textarea"): return "textarea"
    if html_token_is(source, token, "iframe"): return "iframe"
    if html_token_is(source, token, "xmp"): return "xmp"
    if html_token_is(source, token, "noembed"): return "noembed"
    if html_token_is(source, token, "noframes"): return "noframes"
    if html_token_is(source, token, "plaintext"): return "plaintext"
    if scripting and html_token_is(source, token, "noscript"): return "noscript"
    return ""

unsafe fn html_parse_tree_mode(source: string, nodes: ptr<HtmlNode>, capacity: i64, attributes: ptr<HtmlAttribute>, attribute_capacity: i64, scripting: bool) -> i64:
    if capacity < 1 or capacity > HTML_NODE_LIMIT or attribute_capacity < 0 or attribute_capacity > HTML_ATTRIBUTE_LIMIT:
        return -22
    if nodes == (0 as ptr<HtmlNode>) or (attribute_capacity > 0 and attributes == (0 as ptr<HtmlAttribute>)): return -22
    let length: i64 = __volt_strlen(source)
    if length > HTML_DOCUMENT_LIMIT:
        return -7
    let input: ptr<char> = source as ptr<char>
    nodes[0] = HtmlNode(HTML_DOCUMENT, -1, -1, -1, -1, 0, 0, -1, 0, 0, 0, 0, 0, -1)
    let count: i64 = 1
    let attribute_count: i64 = 0
    let stack: [128]i64
    stack[0] = 0
    let raw: string = ""
    let depth: i64 = 1
    let position: i64 = 0
    let done: bool = false
    while not done:
        let token: HtmlToken
        let kind: i64 = HTML_EOF
        if raw != "":
            let raw_start: i64 = position
            let raw_end: i64 = length
            if raw != "plaintext": raw_end = html_raw_end_range(input, length, raw_start, raw)
            if raw_end > raw_start:
                token.kind = HTML_TEXT
                token.start = raw_start
                token.length = raw_end - raw_start
                token.raw_start = raw_start
                token.raw_length = token.length
                token.self_closing = false
                position = raw_end
                kind = HTML_TEXT
            else:
                raw = ""
                kind = html_next_range(input, length, &position, &token)
        else:
            kind = html_next_range(input, length, &position, &token)
        if kind == HTML_EOF:
            done = true
        else:
            if kind == HTML_ERROR:
                return -22
            if kind == HTML_COMMENT or kind == HTML_DOCTYPE:
                continue
            if kind == HTML_END_TAG:
                if html_token_is(source, &token, "p"):
                    depth = html_close_in_scope(source, nodes, &stack[0], depth, "p", "applet button caption html marquee object table td th template")
                    continue
                if html_token_is(source, &token, "li"):
                    depth = html_close_in_scope(source, nodes, &stack[0], depth, "li", "applet caption html marquee object ol table td th template ul")
                    continue
                let j: i64 = depth - 1
                let found: i64 = -1
                while j > 0 and found == -1:
                    let n: i64 = stack[j]
                    if nodes[n].name_length == token.length:
                        let p: ptr<char> = source as ptr<char>
                        let k: i64 = 0
                        let same: bool = true
                        while k < token.length:
                            let a: i64 = p[nodes[n].name_start + k] as i64
                            let b: i64 = p[token.start + k] as i64
                            if a >= 65 and a <= 90: a += 32
                            if b >= 65 and b <= 90: b += 32
                            if a != b: same = false
                            k += 1
                        if same: found = j
                    if found < 0 and html_name_equal(source, &nodes[n], "template"): break
                    j -= 1
                if found > 0: depth = found
            else:
                if count >= capacity: return -7
                if kind == HTML_START_TAG:
                    if html_token_is(source, &token, "li"):
                        # Special HTML elements stop the previous-item search, except address, div and p.
                        depth = html_close_in_scope(source, nodes, &stack[0], depth, "li", "applet area article aside base basefont bgsound blockquote body br button caption center col colgroup dd details dialog dir dl dt embed fieldset figcaption figure footer form frame frameset h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img input keygen link listing main marquee menu meta nav noembed noframes noscript object ol param plaintext pre script search section select source style summary table tbody td template textarea tfoot th thead title tr track ul wbr xmp")
                    # shortcut: only p/li omission rules here; table insertion modes and formatting reconstruction are separate.
                    if html_name_in(source, token.start, token.length, "address article aside blockquote center dd details dialog dir div dl dt fieldset figcaption figure footer form h1 h2 h3 h4 h5 h6 header hgroup hr li listing main menu nav ol p plaintext pre search section summary table ul xmp"):
                        depth = html_close_in_scope(source, nodes, &stack[0], depth, "p", "applet button caption html marquee object table td th template")
                let index: i64 = count
                let parent: i64 = stack[depth - 1]
                let previous: i64 = nodes[parent].last_child
                if previous >= 0 and nodes[previous].kind != HTML_ELEMENT: previous = nodes[previous].previous_element
                nodes[index] = HtmlNode(HTML_TEXT_NODE, parent, -1, -1, -1, 0, 0, -1, 0, token.raw_start, token.raw_length, token.start, token.length, previous)
                if kind == HTML_START_TAG:
                    nodes[index].kind = HTML_ELEMENT
                    nodes[index].name_start = token.start
                    nodes[index].name_length = token.length
                    nodes[index].attribute_start = attribute_count
                    nodes[index].raw_start = token.raw_start
                    nodes[index].raw_length = token.raw_length
                    nodes[index].text_start = 0
                    nodes[index].text_length = 0
                    let attribute_result: i64 = html_parse_attributes(source, &token, index, attributes, &attribute_count, attribute_capacity)
                    if attribute_result < 0: return attribute_result
                    nodes[index].attribute_count = attribute_count - nodes[index].attribute_start
                if nodes[parent].first_child == -1:
                    nodes[parent].first_child = index
                else:
                    nodes[nodes[parent].last_child].next_sibling = index
                nodes[parent].last_child = index
                count += 1
                if kind == HTML_START_TAG:
                    let raw_tag: string = html_raw_tag(source, &token, scripting)
                    if raw_tag != "" or (not token.self_closing and not html_void_tag(source, &token)):
                        if depth == 128: return HTML_DEPTH_EXCEEDED
                        raw = raw_tag
                        stack[depth] = index
                        depth += 1
    return count
