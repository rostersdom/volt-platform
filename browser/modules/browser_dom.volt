# Apply the build-once DOM patch sent by the JavaScript worker. New nodes are
# parsed from an HTML fragment appended to the page source, spliced into the
# existing node arrays, and linked under an existing or created element.
use buffer
use bytes
use css
use html
use browser_engine
use browser_js

const BROWSER_DOM_NODES: i64 = 256
const BROWSER_DOM_ATTRIBUTES: i64 = 512
# Wire format, mirrored in browser/workers/browser_js_worker.c:
# append op = [op=1, parent_kind, parent_ref, html_len] (four i64) + html bytes.
# parent_kind 0 is a page node index, 1 is a JS-created temporary id.
const BROWSER_DOM_OP_APPEND: i64 = 1
const BROWSER_DOM_OP_HEADER_BYTES: i64 = 32
const BROWSER_DOM_PARENT_NODE: i64 = 0
const BROWSER_DOM_PARENT_TEMP: i64 = 1

unsafe fn browser_dom_source_append(page: ptr<BrowserPage>, data: ptr<char>, length: i64) -> i64:
    if page.source_buffer == (0 as ptr<ByteBuffer>) or length < 1: return -22
    let buffer: ptr<ByteBuffer> = page.source_buffer
    let used: i64 = buffer.len - 1
    if used < 0 or used + length + 1 > HTML_DOCUMENT_LIMIT: return -90
    let status: i64 = bytes_reserve(buffer, used + length + 1)
    if status < 0: return status
    page.source = buffer.data as ptr<char> as string
    let i: i64 = 0
    while i < length:
        (page.source as ptr<char>)[used + i] = data[i]
        i += 1
    (page.source as ptr<char>)[used + length] = 0 as char
    buffer.len = used + length + 1
    return used

unsafe fn browser_dom_attribute_used(page: ptr<BrowserPage>) -> i64:
    let used: i64 = 0
    let i: i64 = 0
    while i < page.node_count:
        let node: ptr<HtmlNode> = &page.nodes[i]
        if node.attribute_start >= 0 and node.attribute_start + node.attribute_count > used:
            used = node.attribute_start + node.attribute_count
        i += 1
    return used

unsafe fn browser_dom_fragment_attributes(nodes: ptr<HtmlNode>, count: i64) -> i64:
    let used: i64 = 0
    let i: i64 = 0
    while i < count:
        if nodes[i].attribute_start >= 0 and nodes[i].attribute_start + nodes[i].attribute_count > used:
            used = nodes[i].attribute_start + nodes[i].attribute_count
        i += 1
    return used

unsafe fn browser_dom_map(index: i64, base: i64) -> i64:
    if index <= 0: return -1
    return base + index - 1

unsafe fn browser_dom_record_ids(page: ptr<BrowserPage>, first: i64, count: i64):
    let i: i64 = first
    while i < first + count:
        let node: ptr<HtmlNode> = &page.nodes[i]
        if node.kind == HTML_ELEMENT:
            let attr: i64 = css_find_html_attribute(page.source, node, page.attributes, "data-volt-id")
            if attr >= 0 and page.attributes[attr].has_value:
                let value: ptr<HtmlAttribute> = &page.attributes[attr]
                if value.value_length > 0 and value.value_length <= 18:
                    let id: i64 = 0
                    let digits: i64 = 0
                    let k: i64 = 0
                    let valid: bool = true
                    while k < value.value_length:
                        let c: i64 = (page.source as ptr<char>)[value.value_start + k] as i64
                        if c < 48 or c > 57:
                            valid = false
                        else:
                            id = id * 10 + (c - 48)
                            digits += 1
                        k += 1
                    if valid and digits > 0: browser_js_temp_record(&page.storage.js, id, i)
        i += 1

unsafe fn browser_dom_insert(page: ptr<BrowserPage>, parent: i64, data: ptr<char>, length: i64) -> i64:
    if parent <= 0 or parent >= page.node_count: return -22
    if page.nodes[parent].kind != HTML_ELEMENT: return -22
    let base: i64 = browser_dom_source_append(page, data, length)
    if base < 0: return base
    let fragment_nodes: Buffer<HtmlNode>
    let fragment_attributes: Buffer<HtmlAttribute>
    defer buffer_free(&fragment_nodes)
    defer buffer_free(&fragment_attributes)
    if buffer_reserve(&fragment_nodes, BROWSER_DOM_NODES) < 0: return -12
    if buffer_reserve(&fragment_attributes, BROWSER_DOM_ATTRIBUTES) < 0: return -12
    let fragment: string = ((page.source as ptr<char>) + base) as string
    let count: i64 = html_parse_tree(fragment, buffer_data(&fragment_nodes), BROWSER_DOM_NODES, buffer_data(&fragment_attributes), BROWSER_DOM_ATTRIBUTES)
    if count < 0: return count
    if count <= 1: return 0
    let add: i64 = count - 1
    if page.node_count + add > HTML_NODE_LIMIT: return -7
    let attribute_base: i64 = browser_dom_attribute_used(page)
    let attribute_add: i64 = browser_dom_fragment_attributes(buffer_data(&fragment_nodes), count)
    if attribute_base + attribute_add > HTML_ATTRIBUTE_LIMIT: return -7
    let storage: ptr<BrowserPageStorage> = page.storage
    if storage == (0 as ptr<BrowserPageStorage>): return -22
    let node_base: i64 = page.node_count
    # The HTML parser fills the buffers without updating Buffer.len; publish the
    # used bytes so a reallocation copies the live nodes and attributes instead
    # of discarding them.
    storage.nodes.storage.len = page.node_count * sizeof(HtmlNode)
    storage.attributes.storage.len = attribute_base * sizeof(HtmlAttribute)
    if buffer_reserve(&storage.nodes, node_base + add + 8) < 0: return -12
    if buffer_reserve(&storage.attributes, attribute_base + attribute_add + 8) < 0: return -12
    page.nodes = buffer_data(&storage.nodes)
    page.attributes = buffer_data(&storage.attributes)
    let i: i64 = 1
    while i < count:
        let source: ptr<HtmlNode> = &buffer_data(&fragment_nodes)[i]
        let target: ptr<HtmlNode> = &page.nodes[node_base + i - 1]
        target[0] = source[0]
        target.parent = browser_dom_map(source.parent, node_base)
        target.first_child = browser_dom_map(source.first_child, node_base)
        target.last_child = browser_dom_map(source.last_child, node_base)
        target.next_sibling = browser_dom_map(source.next_sibling, node_base)
        target.previous_element = browser_dom_map(source.previous_element, node_base)
        target.name_start += base
        target.raw_start += base
        target.text_start += base
        if source.attribute_count > 0:
            target.attribute_start = attribute_base + source.attribute_start
            let j: i64 = 0
            while j < source.attribute_count:
                let attribute: HtmlAttribute = buffer_data(&fragment_attributes)[source.attribute_start + j]
                attribute.name_start += base
                attribute.value_start += base
                attribute.owner = node_base + i - 1
                page.attributes[target.attribute_start + j] = attribute
                j += 1
        i += 1
    let top: i64 = buffer_data(&fragment_nodes)[0].first_child
    if top <= 0: return 0
    let previous: i64 = page.nodes[parent].last_child
    let previous_element: i64 = -1
    if previous >= 0:
        if page.nodes[previous].kind == HTML_ELEMENT: previous_element = previous
        else: previous_element = page.nodes[previous].previous_element
    let first_new: i64 = browser_dom_map(top, node_base)
    let current_temp: i64 = top
    let current_new: i64 = first_new
    let prior: i64 = previous
    let prior_element: i64 = previous_element
    let last_new: i64 = first_new
    while current_temp > 0 and current_new > 0:
        let next_temp: i64 = buffer_data(&fragment_nodes)[current_temp].next_sibling
        let next_new: i64 = browser_dom_map(next_temp, node_base)
        page.nodes[current_new].parent = parent
        page.nodes[current_new].next_sibling = next_new
        page.nodes[current_new].previous_element = prior_element
        if prior >= 0: page.nodes[prior].next_sibling = current_new
        else: page.nodes[parent].first_child = current_new
        if page.nodes[current_new].kind == HTML_ELEMENT: prior_element = current_new
        prior = current_new
        last_new = current_new
        current_temp = next_temp
        current_new = next_new
    page.nodes[parent].last_child = last_new
    page.node_count = node_base + add
    storage.nodes.storage.len = page.node_count * sizeof(HtmlNode)
    storage.attributes.storage.len = (attribute_base + attribute_add) * sizeof(HtmlAttribute)
    browser_dom_record_ids(page, node_base, add)
    return 0

# Apply the structural ops produced by the worker. Only append ops exist in v1.
unsafe fn browser_dom_apply(page: ptr<BrowserPage>, dom: ptr<ByteBuffer>, overrides: ptr<ptr<CssTextOverrides>>) -> i64:
    if page == (0 as ptr<BrowserPage>) or dom == (0 as ptr<ByteBuffer>) or dom.len < 0: return -22
    let pos: i64 = 0
    while pos < dom.len:
        if dom.len - pos < BROWSER_DOM_OP_HEADER_BYTES: return -22
        let head: ptr<i64> = (dom.data + pos) as ptr<i64>
        let kind: i64 = head[0]
        let parent_kind: i64 = head[1]
        let parent_ref: i64 = head[2]
        let length: i64 = head[3]
        pos += BROWSER_DOM_OP_HEADER_BYTES
        if kind != BROWSER_DOM_OP_APPEND or length < 1 or length > dom.len - pos: return -22
        let parent: i64 = 0
        if parent_kind == BROWSER_DOM_PARENT_NODE: parent = parent_ref
        elif parent_kind == BROWSER_DOM_PARENT_TEMP: parent = browser_js_temp_node(&page.storage.js, parent_ref)
        if parent <= 0: return -22
        let status: i64 = browser_dom_insert(page, parent, (dom.data + pos) as ptr<char>, length)
        if status < 0: return status
        pos += length
    return 0