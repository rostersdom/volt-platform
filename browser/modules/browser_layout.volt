use browser_styles
use browser_images
use browser_video

struct BrowserVisual:
    sheet: BrowserStyleSheet
    styles: Buffer<BrowserStyle>
    images: BrowserImages
    has_video: bool
    media_allowed: bool
    video: BrowserVideo

struct WebMetrics:
    layout: ptr<char>
    font: ptr<char>
    size: i64
    family: i64
    weight: i32
    italic: i32

struct WebMeasure:
    width: i64                # Pango units so fractions survive across words.
    height: i64
    baseline: i64

struct WebFlexItem:
    basis: i64
    minimum: i64
    maximum: i64
    size: i64

struct WebLayout:
    output: ptr<CssLayoutContext>
    styles: ptr<BrowserStyle>
    images: ptr<BrowserImages>
    attrs: ptr<HtmlAttribute>
    metrics: ptr<WebMetrics>
    scratch: ptr<char>
    scratch_capacity: i64
    source_length: i64
    overrides: ptr<CssTextOverrides>
    transfer: ptr<HttpTransfer>
    table_columns: i64
    flex_items: ptr<Buffer<WebFlexItem>>

struct WebFlow:
    x: i64
    y: i64
    width: i64
    used: i64
    first: i64
    ascent: i64
    descent: i64
    margin: i64
    align: i64
    space: bool

struct WebBlock:
    x: i64
    y: i64
    width: i64
    basis: i64
    fill: bool

unsafe fn browser_visual_free(visual: ptr<BrowserVisual>):
    browser_video_close(&visual.video)
    browser_images_free(&visual.images)
    browser_sheet_free(&visual.sheet)
    buffer_free(&visual.styles)

unsafe fn web_set_font(metrics: ptr<WebMetrics>, style: ptr<BrowserStyle>):
    if metrics.size == style.font and metrics.family == style.family and metrics.weight == style.weight and metrics.italic == style.italic: return
    # Use Noto Sans before the desktop alias, which can select a narrower UI face.
    let family: string = "Times New Roman, Liberation Serif, serif"
    if style.family == 1: family = "Arial, Liberation Sans, sans-serif"
    elif style.family == 2: family = "monospace"
    elif style.family == 3: family = "Noto Sans, sans-serif"
    pango_font_description_set_family(metrics.font, family as ptr<char>)
    pango_font_description_set_absolute_size(metrics.font, (style.font * PANGO_SCALE) as f64)
    pango_font_description_set_weight(metrics.font, style.weight)
    pango_font_description_set_style(metrics.font, style.italic)
    pango_layout_set_font_description(metrics.layout, metrics.font)
    metrics.size = style.font
    metrics.family = style.family
    metrics.weight = style.weight
    metrics.italic = style.italic

unsafe fn web_measure(metrics: ptr<WebMetrics>, style: ptr<BrowserStyle>, text: ptr<char>, length: i64) -> WebMeasure:
    web_set_font(metrics, style)
    pango_layout_set_text(metrics.layout, text, length as i32)
    let width: i32 = 0
    let natural: i32 = 0
    pango_layout_get_size(metrics.layout, &width, &natural)
    let pixels: i64 = ((natural as i64) + PANGO_SCALE - 1) / PANGO_SCALE
    let height: i64 = style.line_height
    if height >= WEB_LINE_RATIO: height = ((height - WEB_LINE_RATIO) * style.font + 50) / 100
    if height < 1: height = max(1, pixels)
    let natural_baseline: i64 = ((pango_layout_get_baseline(metrics.layout) as i64) + PANGO_SCALE / 2) / PANGO_SCALE
    let baseline: i64 = max(0, min(height, natural_baseline + (height - pixels) / 2))
    return WebMeasure(max(0, width as i64), height, baseline)

unsafe fn web_current(doc: ptr<WebLayout>) -> i64:
    if doc.transfer == (0 as ptr<HttpTransfer>): return 0
    return min(0, http_transfer_remaining(doc.transfer))

unsafe fn web_flush(doc: ptr<WebLayout>, flow: ptr<WebFlow>):
    let out: ptr<CssLayoutContext> = doc.output
    if flow.first < out.fragment_count:
        let pixels: i64 = (flow.used + PANGO_SCALE / 2) / PANGO_SCALE
        let shift: i64 = 0
        if flow.align == 1: shift = max(0, (flow.width - pixels) / 2)
        elif flow.align == 2: shift = max(0, flow.width - pixels)
        let i: i64 = flow.first
        while i < out.fragment_count:
            let run: ptr<CssFlowFragment> = &out.fragments[i]
            run.x += shift
            run.y += flow.ascent - run.baseline
            if run.byte_length == 0:
                out.boxes[run.node_index] = CssLayoutBox(run.x, run.y, run.advance, run.line_height, false)
            elif out.boxes[run.node_index].height == 0 and out.nodes[run.node_index].kind == HTML_TEXT_NODE:
                out.boxes[run.node_index].y = run.y
                out.boxes[run.node_index].height = run.line_height
            i += 1
        flow.y += max(1, flow.ascent + flow.descent)
        flow.margin = 0
    flow.first = out.fragment_count
    flow.used = 0
    flow.ascent = 0
    flow.descent = 0
    flow.space = false

unsafe fn web_fragment(doc: ptr<WebLayout>, flow: ptr<WebFlow>, node: i64, text: ptr<char>, length: i64, measure: WebMeasure) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    if out.fragment_count >= out.fragment_capacity or length > out.text_capacity - out.text_length: return -7
    let i: i64 = 0
    while i < length:
        out.text_bytes[out.text_length + i] = text[i]
        i += 1
    let start: i64 = (flow.used + PANGO_SCALE / 2) / PANGO_SCALE
    let end: i64 = (flow.used + measure.width + PANGO_SCALE / 2) / PANGO_SCALE
    out.fragments[out.fragment_count] = CssFlowFragment(node, out.text_length, length, flow.x + start, flow.y, doc.styles[node].color, flow.x, flow.y, flow.width, 2147483647, end - start, measure.height, measure.baseline)
    out.text_length += length
    out.fragment_count += 1
    flow.used += measure.width
    flow.ascent = max(flow.ascent, measure.baseline)
    flow.descent = max(flow.descent, measure.height - measure.baseline)
    return 0

unsafe fn web_word(doc: ptr<WebLayout>, flow: ptr<WebFlow>, node: i64, text: ptr<char>, length: i64) -> i64:
    let style: ptr<BrowserStyle> = &doc.styles[node]
    let measure: WebMeasure = web_measure(doc.metrics, style, text, length)
    let gap: WebMeasure
    if flow.space and flow.first < doc.output.fragment_count:
        gap = web_measure(doc.metrics, style, " " as ptr<char>, 1)
    if style.whitespace != 1 and style.whitespace != 2 and flow.first < doc.output.fragment_count and flow.used + gap.width + measure.width > flow.width * PANGO_SCALE:
        web_flush(doc, flow)
        gap.width = 0
    if gap.width > 0:
        let status: i64 = web_fragment(doc, flow, node, " " as ptr<char>, 1, gap)
        if status < 0: return status
    flow.space = false
    return web_fragment(doc, flow, node, text, length, measure)

unsafe fn web_text(doc: ptr<WebLayout>, flow: ptr<WebFlow>, node: i64, text: ptr<char>, length: i64) -> i64:
    let mode: i64 = doc.styles[node].whitespace
    let preserve: bool = mode == 2 or mode == 3
    let position: i64 = 0
    let next_check: i64 = 0
    while position < length:
        if position >= next_check:
            let remaining: i64 = web_current(doc)
            if remaining < 0: return remaining
            next_check = position + 1024
        if mode >= 2 and (text[position] == '\r' or text[position] == '\n'):
            if text[position] == '\r' and position + 1 < length and text[position + 1] == '\n': position += 1
            web_line_break(doc, flow, &doc.styles[node])
            position += 1
            continue
        if not preserve and css_space(text[position]):
            flow.space = true
            position += 1
            continue
        let start: i64 = position
        let gap: bool = css_space(text[position])
        # Bound shaping work per run and split at a scalar boundary.
        while position < length and position - start < 256:
            if text[position] == '\r' or text[position] == '\n': break
            if gap and not css_space(text[position]): break
            if not gap and css_space(text[position]): break
            utf8_next(text, &position, length)
        let status: i64 = web_word(doc, flow, node, text + start, position - start)
        if status < 0: return status
    return 0

unsafe fn web_line_break(doc: ptr<WebLayout>, flow: ptr<WebFlow>, style: ptr<BrowserStyle>):
    let before: i64 = flow.y
    web_flush(doc, flow)
    if before == flow.y: flow.y += web_measure(doc.metrics, style, " " as ptr<char>, 1).height
    flow.margin = 0

unsafe fn web_attr_pixels(doc: ptr<WebLayout>, node: i64, name: string) -> i64:
    let index: i64 = css_find_html_attribute(doc.output.html_source, &doc.output.nodes[node], doc.attrs, name)
    if index < 0 or not doc.attrs[index].has_value: return -1
    let p: ptr<char> = (doc.output.html_source as ptr<char>) + doc.attrs[index].value_start
    let n: i64 = doc.attrs[index].value_length
    let size: i64 = 0
    let i: i64 = 0
    while i < n:
        if p[i] < '0' or p[i] > '9': return -1
        size = size * 10 + (p[i] as i64 - 48)
        if size > 4096: return -1
        i += 1
    if n == 0: return -1
    return size

unsafe fn web_image(doc: ptr<WebLayout>, flow: ptr<WebFlow>, node: i64, block_height: i64) -> i64:
    let image: ptr<BrowserImage> = browser_image_at(doc.images, node)
    let out: ptr<CssLayoutContext> = doc.output
    if image == (0 as ptr<BrowserImage>):
        let index: i64 = css_find_html_attribute(out.html_source, &out.nodes[node], doc.attrs, "alt")
        if index < 0 or not doc.attrs[index].has_value: return 0
        let alt: ptr<HtmlAttribute> = &doc.attrs[index]
        let length: i64 = html_decode_range(out.html_source as ptr<char>, doc.source_length, alt.value_start, alt.value_length, doc.scratch, doc.scratch_capacity)
        if length <= 0: return 0
        return web_text(doc, flow, node, doc.scratch, length)
    let style: ptr<BrowserStyle> = &doc.styles[node]
    let width: i64 = web_pixels(style.width, flow.width, style.font)
    let height: i64 = web_pixels(style.height, flow.width, style.font)
    if width < 0 and not style.width_set: width = web_attr_pixels(doc, node, "width")
    if height < 0 and not style.height_set: height = web_attr_pixels(doc, node, "height")
    if width < 0 and height < 0: width = image.width
    if width < 0: width = max(1, height * image.width / image.height)
    let limit: i64 = web_pixels(style.max_width, flow.width, style.font)
    if limit >= 0: width = min(width, limit)
    width = min(flow.width, width)
    if block_height >= -1:
        width = flow.width
        height = block_height
    if height < 0: height = max(1, width * image.height / image.width)
    height = min(4096, height)
    if width <= 0 or height <= 0: return 0
    let gap: WebMeasure
    if flow.space and flow.first < out.fragment_count:
        gap = web_measure(doc.metrics, style, " " as ptr<char>, 1)
    if flow.first < out.fragment_count and flow.used + gap.width + width * PANGO_SCALE > flow.width * PANGO_SCALE:
        web_flush(doc, flow)
        gap.width = 0
    if gap.width > 0:
        let status: i64 = web_fragment(doc, flow, node, " " as ptr<char>, 1, gap)
        if status < 0: return status
    flow.space = false
    return web_fragment(doc, flow, node, 0 as ptr<char>, 0, WebMeasure(width * PANGO_SCALE, height, height))

unsafe fn web_margin(style: ptr<BrowserStyle>, side: i64, width: i64) -> i64:
    return max(0, web_pixels(style.margin[side], width, style.font))

unsafe fn web_align_row(doc: ptr<WebLayout>, first: i64, after: i64, bottom: i64, fragment: i64, basis: i64):
    let out: ptr<CssLayoutContext> = doc.output
    let parent: i64 = out.nodes[first].parent
    let node: i64 = first
    let at: i64 = fragment
    while node >= 0 and node != after:
        let box: ptr<CssLayoutBox> = &out.boxes[node]
        let style: ptr<BrowserStyle> = &doc.styles[node]
        let next: i64 = out.nodes[node].next_sibling
        let end: i64 = web_subtree_end(out, node)
        let shift: i64 = 0
        if out.nodes[node].kind == HTML_ELEMENT and not box.hidden:
            let align: i64 = doc.styles[parent].align_items
            if style.align_self != WEB_AUTO: align = style.align_self
            let width: i64 = box.width
            if basis > 0: width = basis
            let free: i64 = max(0, bottom - box.y - box.height - web_margin(style, 2, width))
            let replaced: bool = html_name_equal(out.html_source, &out.nodes[node], "img") or html_name_equal(out.html_source, &out.nodes[node], "video")
            if align == WEB_ALIGN_STRETCH and style.height == WEB_AUTO and not replaced:
                box.height += free
            elif align == WEB_ALIGN_CENTER: shift = free / 2
            elif align == WEB_ALIGN_END: shift = free
        if shift > 0:
            let i: i64 = node
            while i < end:
                if not out.boxes[i].hidden: out.boxes[i].y += shift
                i += 1
        while at < out.fragment_count and out.fragments[at].node_index < end:
            out.fragments[at].y += shift
            out.fragments[at].clip_y += shift
            at += 1
        node = next

unsafe fn web_subtree_end(out: ptr<CssLayoutContext>, index: i64) -> i64:
    let node: i64 = index
    while node > 0:
        if out.nodes[node].next_sibling >= 0: return out.nodes[node].next_sibling
        node = out.nodes[node].parent
    return out.node_count

unsafe fn web_intrinsic_text(doc: ptr<WebLayout>, node: i64, limit: i64) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    let style: ptr<BrowserStyle> = &doc.styles[node]
    let override: ptr<CssTextOverride> = css_text_override(doc.overrides, node)
    let width: i64 = 0
    if override != (0 as ptr<CssTextOverride>):
        width = web_measure(doc.metrics, style, &override.text[0], override.length).width
    else:
        let child: i64 = out.nodes[node].first_child
        while child >= 0:
            let item: ptr<HtmlNode> = &out.nodes[child]
            if doc.styles[child].display != 0:
                # shortcut: simple text-only fit-content boxes, including the default button.
                if item.kind != HTML_TEXT_NODE or item.text_length > 4096: return limit
                let length: i64 = html_decode_range(out.html_source as ptr<char>, doc.source_length, item.text_start, item.text_length, doc.scratch, doc.scratch_capacity)
                if length > 0: width += web_measure(doc.metrics, &doc.styles[child], doc.scratch, length).width
            child = item.next_sibling
        if width == 0 and out.nodes[node].first_child < 0: return 1
    return min(limit, (width + PANGO_SCALE - 1) / PANGO_SCALE)

unsafe fn web_hide_item(out: ptr<CssLayoutContext>, node: i64, depth: i64) -> i64:
    out.boxes[node].hidden = true
    return css_hide_subtree(out, node, depth + 1)

unsafe fn web_anonymous_item(out: ptr<CssLayoutContext>, node: i64) -> bool:
    let token: ptr<HtmlNode> = &out.nodes[node]
    if token.kind != HTML_TEXT_NODE: return false
    let text: ptr<char> = (out.html_source as ptr<char>) + token.text_start
    let i: i64 = 0
    while i < token.text_length and css_space(text[i]): i += 1
    return i < token.text_length

unsafe fn web_flex_size(doc: ptr<WebLayout>, child: i64, available: i64) -> WebFlexItem:
    let style: ptr<BrowserStyle> = &doc.styles[child]
    let edge: i64 = web_pixels(style.padding[1], available, style.font) + web_pixels(style.padding[3], available, style.font) + 2 * min(32, web_pixels(style.border, available, style.font))
    let margin: i64 = web_margin(style, 1, available) + web_margin(style, 3, available)
    let extra: i64 = edge
    if style.border_box: extra = 0
    let width: i64 = web_pixels(style.basis, available, style.font)
    if width < 0: width = web_pixels(style.width, available, style.font)
    if width < 0:
        let content: i64 = WEB_AUTO
        if html_name_equal(doc.output.html_source, &doc.output.nodes[child], "img"):
            if not style.width_set: content = web_attr_pixels(doc, child, "width")
            if content < 0:
                let image: ptr<BrowserImage> = browser_image_at(doc.images, child)
                if image != (0 as ptr<BrowserImage>): content = image.width
        if content < 0: content = web_intrinsic_text(doc, child, max(1, available - edge - margin))
        width = content + edge
    else: width += extra
    let low: i64 = max(edge, web_pixels(style.min_width, available, style.font) + extra) + margin
    let high: i64 = web_pixels(style.max_width, available, style.font)
    if high < 0: high = 2147483647
    else: high = max(low, high + extra + margin)
    width = max(low, min(high, width + margin))
    return WebFlexItem(width, low, high, width)

fn web_justify(mode: i64, space: i64, count: i64, index: i64) -> i64:
    if mode == WEB_ALIGN_CENTER: return space / 2
    if mode == WEB_ALIGN_END: return space
    if mode == WEB_JUSTIFY_BETWEEN and count > 1: return space * index / (count - 1)
    if mode == WEB_JUSTIFY_AROUND: return space * (index * 2 + 1) / (count * 2)
    if mode == WEB_JUSTIFY_EVENLY: return space * (index + 1) / (count + 1)
    return 0

fn web_flex_share(space: i64, weight: i64, total: i64) -> i64:
    if weight == 0: return 0
    if abs(space) <= 9223372036854775807 / weight: return space * weight / total
    # Large rows can exceed the integer product range, but not the pixel result.
    return (((space as f64) * (weight as f64)) / (total as f64)) as i64

unsafe fn web_flex_rows(doc: ptr<WebLayout>, node: i64, flow: ptr<WebFlow>, depth: i64, cross: i64) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    let style: ptr<BrowserStyle> = &doc.styles[node]
    if buffer_reserve(doc.flex_items, out.node_count) < 0: return -12
    let items: ptr<WebFlexItem> = buffer_data(doc.flex_items)
    let gap: i64 = min(flow.width, web_pixels(style.column_gap, flow.width, style.font))
    let row_gap: i64 = min(flow.width, web_pixels(style.row_gap, flow.width, style.font))
    let child: i64 = out.nodes[node].first_child
    let bottom: i64 = flow.y
    let started: bool = false
    while child >= 0:
        let remaining: i64 = web_current(doc)
        if remaining < 0: return remaining
        if doc.styles[child].display == 0:
            let hidden: i64 = web_hide_item(out, child, depth)
            if hidden < 0: return hidden
            child = out.nodes[child].next_sibling
            continue
        if out.nodes[child].kind != HTML_ELEMENT:
            if web_anonymous_item(out, child):
                flow.y = bottom
                if started: flow.y += row_gap
                let status: i64 = web_text_node(doc, flow, child)
                if status < 0: return status
                web_flush(doc, flow)
                bottom = flow.y
                started = true
            child = out.nodes[child].next_sibling
            continue
        let first: i64 = child
        let count: i64 = 0
        let used: i64 = 0
        let grow: i64 = 0
        let shrink: i64 = 0
        let scan: i64 = 0
        while child >= 0:
            if scan % 64 == 0:
                remaining = web_current(doc)
                if remaining < 0: return remaining
            scan += 1
            let item: ptr<BrowserStyle> = &doc.styles[child]
            if item.display == 0:
                let hidden: i64 = web_hide_item(out, child, depth)
                if hidden < 0: return hidden
            elif out.nodes[child].kind == HTML_ELEMENT:
                let size: WebFlexItem = web_flex_size(doc, child, flow.width)
                if style.flex_wrap and count > 0 and used + gap + size.basis > flow.width: break
                if count > 0: used += gap
                items[child] = size
                used += size.basis
                grow += item.grow
                shrink += item.shrink * size.basis
                count += 1
            elif web_anonymous_item(out, child): break
            child = out.nodes[child].next_sibling
        let after: i64 = child
        let space: i64 = flow.width - used
        let factor: i64 = max(100, grow)
        let shrinking: bool = space < 0
        if shrinking: factor = max(1, shrink)
        let weight: i64 = 0
        let allocated: i64 = (count - 1) * gap
        let item_index: i64 = first
        while item_index >= 0 and item_index != after:
            if doc.styles[item_index].display != 0 and out.nodes[item_index].kind == HTML_ELEMENT:
                let item: ptr<WebFlexItem> = &items[item_index]
                let share: i64 = doc.styles[item_index].grow
                if shrinking: share = doc.styles[item_index].shrink * item.basis
                let delta: i64 = web_flex_share(space, weight + share, factor) - web_flex_share(space, weight, factor)
                weight += share
                item.size = max(item.minimum, min(item.maximum, item.basis + delta))
                allocated += item.size
            item_index = out.nodes[item_index].next_sibling
        let y: i64 = bottom
        if started: y += row_gap
        let x: i64 = flow.x
        let index: i64 = 0
        let fragments: i64 = out.fragment_count
        let justify: i64 = max(0, flow.width - allocated)
        item_index = first
        while item_index >= 0 and item_index != after:
            if doc.styles[item_index].display != 0 and out.nodes[item_index].kind == HTML_ELEMENT:
                let width: i64 = items[item_index].size
                let left: i64 = x + web_justify(style.justify, justify, count, index)
                let next: i64 = web_block(doc, item_index, WebBlock(left, y, width, flow.width, true), depth + 1)
                if next < 0: return next
                bottom = max(bottom, next)
                x += width + gap
                index += 1
            item_index = out.nodes[item_index].next_sibling
        # A single flex line takes the container's definite content height.
        if not started and after < 0: bottom = max(bottom, y + cross)
        web_align_row(doc, first, after, bottom, fragments, flow.width)
        started = true
    flow.y = bottom
    flow.first = out.fragment_count
    return 0

# Distribute free space by weight; freeze tracks whose share falls below their minimum.
unsafe fn web_grid_sizes(style: ptr<BrowserStyle>, available: i64, gap: i64, columns: i64, sizes: ptr<i64>):
    let room: i64 = max(0, available - gap * (columns - 1))
    let weights: [8]i64
    let weight: i64 = 0
    let i: i64 = 0
    while i < columns:
        let track: i64 = style.tracks[i]
        if style.columns < 0: track = style.tracks[0]
        weights[i] = track / WEB_TRACK_SCALE
        weight += weights[i]
        sizes[i] = web_pixels(track % WEB_TRACK_SCALE, available, style.font)
        if weights[i] == 0: room -= sizes[i]
        i += 1
    let changed: bool = true
    while changed and weight > 0:
        changed = false
        i = 0
        while i < columns:
            if weights[i] > 0 and sizes[i] * weight > room * weights[i]:
                room -= sizes[i]
                weight -= weights[i]
                weights[i] = 0
                changed = true
            i += 1
    if weight > 0:
        let part: i64 = 0
        i = 0
        while i < columns:
            if weights[i] > 0:
                let end: i64 = part + weights[i]
                sizes[i] = (room * end + weight - 1) / weight - (room * part + weight - 1) / weight
                part = end
            i += 1

unsafe fn web_columns(doc: ptr<WebLayout>, node: i64, flow: ptr<WebFlow>, depth: i64, cross: i64) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    let style: ptr<BrowserStyle> = &doc.styles[node]
    if style.display == WEB_FLEX and not style.flex_column: return web_flex_rows(doc, node, flow, depth, cross)
    let grid: bool = style.display == WEB_GRID
    let table: bool = style.display == WEB_TABLE_ROW
    let gap: i64 = min(flow.width, web_pixels(style.column_gap, flow.width, style.font))
    let row_gap: i64 = min(flow.width, web_pixels(style.row_gap, flow.width, style.font))
    let child: i64 = out.nodes[node].first_child
    let count: i64 = 0
    if table or (grid and style.columns == -1):
        while child >= 0:
            if doc.styles[child].display != 0 and out.nodes[child].kind == HTML_ELEMENT: count += 1
            child = out.nodes[child].next_sibling
    let columns: i64 = 1
    let sizes: [8]i64
    if grid:
        columns = style.columns
        if columns < 0:
            let minimum: i64 = max(1, web_pixels(style.tracks[0] % WEB_TRACK_SCALE, flow.width, style.font))
            columns = max(1, min(8, (flow.width + gap) / (minimum + gap)))
            if style.columns == -1: columns = min(columns, max(1, count))
        web_grid_sizes(style, flow.width, gap, columns, &sizes[0])
    elif table:
        columns = max(doc.table_columns, min(128, count))
        gap = min(gap, max(0, (flow.width - columns) / max(1, columns - 1)))
    let track_width: i64 = max(1, flow.width - gap * (columns - 1))
    let x: i64 = flow.x
    let y: i64 = flow.y
    let bottom: i64 = y
    let column: i64 = 0
    let first: i64 = -1
    let fragments: i64 = out.fragment_count
    child = out.nodes[node].first_child
    while child >= 0:
        if child % 64 == 0:
            let remaining: i64 = web_current(doc)
            if remaining < 0: return remaining
        let item: ptr<HtmlNode> = &out.nodes[child]
        let child_style: ptr<BrowserStyle> = &doc.styles[child]
        if child_style.display == 0:
            let hidden: i64 = web_hide_item(out, child, depth)
            if hidden < 0: return hidden
        elif item.kind == HTML_ELEMENT:
            let width: i64 = max(1, track_width / columns)
            if grid: width = sizes[column]
            elif table and track_width >= columns and column % columns < track_width % columns: width += 1
            if first < 0:
                first = child
                fragments = out.fragment_count
            let next: i64 = web_block(doc, child, WebBlock(x, y, width, width, false), depth + 1)
            if next < 0: return next
            bottom = max(bottom, next)
            x += width + gap
            column += 1
            if not table and column == columns:
                if grid: web_align_row(doc, first, item.next_sibling, bottom, fragments, 0)
                first = -1
                y = bottom + row_gap
                x = flow.x
                column = 0
        elif web_anonymous_item(out, child):
            # shortcut: anonymous items occupy their own row until inline item sizing is supported.
            if first > 0 and (grid or table): web_align_row(doc, first, child, bottom, fragments, 0)
            first = -1
            flow.y = max(y, bottom)
            let status: i64 = web_text_node(doc, flow, child)
            if status < 0: return status
            web_flush(doc, flow)
            bottom = flow.y
            y = bottom + row_gap
            x = flow.x
            column = 0
        child = item.next_sibling
    if first > 0 and (grid or table): web_align_row(doc, first, -1, bottom, fragments, 0)
    flow.y = bottom
    flow.first = out.fragment_count
    return 0

unsafe fn web_table_tracks(doc: ptr<WebLayout>, table: i64) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    let row: i64 = out.nodes[table].first_child
    let group: i64 = -1
    let widest: i64 = 1
    while row >= 0:
        let item: ptr<HtmlNode> = &out.nodes[row]
        if doc.styles[row].display != 0 and item.kind == HTML_ELEMENT:
            if doc.styles[row].display == WEB_TABLE_ROW:
                let cells: i64 = 0
                let cell: i64 = item.first_child
                while cell >= 0 and cells < 128:
                    if out.nodes[cell].kind == HTML_ELEMENT and doc.styles[cell].display != 0: cells += 1
                    cell = out.nodes[cell].next_sibling
                widest = max(widest, cells)
            elif group < 0 and item.first_child >= 0 and item.name_start >= 0 and html_name_in(out.html_source, item.name_start, item.name_length, "tbody thead tfoot"):
                group = row
                row = item.first_child
                continue
        row = item.next_sibling
        if row < 0 and group >= 0:
            row = out.nodes[group].next_sibling
            group = -1
    return widest

unsafe fn web_block(doc: ptr<WebLayout>, node: i64, area: WebBlock, depth: i64) -> i64:
    if depth > 128: return -22
    let style: ptr<BrowserStyle> = &doc.styles[node]
    let out: ptr<CssLayoutContext> = doc.output
    let left: i64 = web_margin(style, 3, area.basis)
    let right: i64 = web_margin(style, 1, area.basis)
    let top: i64 = web_margin(style, 0, area.basis)
    let bottom: i64 = web_margin(style, 2, area.basis)
    let pad_left: i64 = web_pixels(style.padding[3], area.basis, style.font)
    let pad_right: i64 = web_pixels(style.padding[1], area.basis, style.font)
    let pad_top: i64 = web_pixels(style.padding[0], area.basis, style.font)
    let pad_bottom: i64 = web_pixels(style.padding[2], area.basis, style.font)
    let border: i64 = min(32, web_pixels(style.border, area.basis, style.font))
    let horizontal: i64 = pad_left + pad_right + border * 2
    let vertical: i64 = pad_top + pad_bottom + border * 2
    let available: i64 = max(0, area.width - left - right)
    let image_tag: bool = html_name_equal(out.html_source, &out.nodes[node], "img")
    let video_tag: bool = html_name_equal(out.html_source, &out.nodes[node], "video")
    let width: i64 = web_pixels(style.width, area.basis, style.font)
    if width >= 0 and not style.border_box: width += horizontal
    let image_height: i64 = WEB_AUTO
    if image_tag:
        if style.height < WEB_PERCENT or style.height >= WEB_EM: image_height = web_pixels(style.height, 0, style.font)
        if image_height >= 0 and style.border_box: image_height = max(0, image_height - vertical)
        if image_height < 0 and not style.height_set: image_height = web_attr_pixels(doc, node, "height")
        if width < 0:
            let requested: i64 = WEB_AUTO
            if not style.width_set: requested = web_attr_pixels(doc, node, "width")
            if requested >= 0: width = requested + horizontal
            else:
                let image: ptr<BrowserImage> = browser_image_at(doc.images, node)
                if image != (0 as ptr<BrowserImage>):
                    if image_height < 0: width = image.width + horizontal
                    else: width = image_height * image.width / image.height + horizontal
        if width >= 0: width = min(available, width)
    elif video_tag:
        if width < 0:
            let requested: i64 = WEB_AUTO
            if not style.width_set: requested = web_attr_pixels(doc, node, "width")
            if requested < 0:
                let poster: ptr<BrowserImage> = browser_image_at(doc.images, node)
                if poster != (0 as ptr<BrowserImage>): requested = poster.width
                else: requested = 300
            width = requested + horizontal
        # Auto-sized media follows the containing block on narrow screens.
        if not style.width_set or style.width == WEB_AUTO: width = min(available, width)
    elif width == WEB_FIT:
        width = web_intrinsic_text(doc, node, max(1, available - horizontal)) + horizontal
    if area.fill: width = available
    if width < 0: width = available
    let min_width: i64 = web_pixels(style.min_width, area.basis, style.font)
    let max_width: i64 = web_pixels(style.max_width, area.basis, style.font)
    if not style.border_box:
        min_width += horizontal
        if max_width >= 0: max_width += horizontal
    if max_width >= 0: width = min(width, max_width)
    width = max(horizontal, max(min_width, width))
    let x: i64 = area.x + left
    let extra: i64 = max(0, available - width)
    if style.margin[3] == WEB_AUTO:
        if style.margin[1] == WEB_AUTO: x += extra / 2
        else: x += extra
    let y: i64 = area.y + top
    out.boxes[node] = CssLayoutBox(x, y, width, 0, false)
    let inside: WebFlow = WebFlow(x + border + pad_left, y + border + pad_top, max(1, width - horizontal), 0, out.fragment_count, 0, 0, 0, style.align, false)
    let height: i64 = web_pixels(style.height, 0, style.font)
    if style.height >= WEB_PERCENT and style.height < WEB_EM: height = WEB_AUTO
    let minimum: i64 = web_pixels(style.min_height, 0, style.font)
    if not style.border_box:
        if height >= 0: height += vertical
        minimum += vertical
    let status: i64 = 0
    if image_tag:
        status = web_image(doc, &inside, node, image_height)
    elif video_tag:
        # Video is replaced content; its source/fallback nodes never produce runs.
        status = css_hide_subtree(out, node, depth)
    elif style.display == WEB_FLEX or style.display == WEB_GRID or style.display == WEB_TABLE_ROW:
        status = web_columns(doc, node, &inside, depth, max(0, max(height, minimum) - vertical))
    elif style.display == WEB_TABLE:
        let prior: i64 = doc.table_columns
        doc.table_columns = web_table_tracks(doc, node)
        status = web_contents(doc, node, &inside, depth)
        doc.table_columns = prior
    else:
        status = web_contents(doc, node, &inside, depth)
    if status < 0: return status
    web_flush(doc, &inside)
    let content: i64 = inside.y - (y + border + pad_top)
    if height < 0 and style.aspect > 0 and not image_tag:
        let size: i64 = max(0, width - horizontal)
        if style.border_box: size = width
        let preferred: i64 = min(4096, (size * 10000 + style.aspect / 2) / style.aspect)
        if not style.border_box: preferred += vertical
        height = max(preferred, content + vertical)
    if video_tag and height < 0:
        if not style.height_set: content = web_attr_pixels(doc, node, "height")
        else: content = WEB_AUTO
        if content < 0:
            let poster: ptr<BrowserImage> = browser_image_at(doc.images, node)
            content = max(1, (width - horizontal) / 2)
            if poster != (0 as ptr<BrowserImage>): content = max(1, (width - horizontal) * poster.height / poster.width)
    if height < 0: height = content + vertical
    height = max(vertical, max(height, minimum))
    out.boxes[node] = CssLayoutBox(x, y, width, height, false)
    if video_tag and width > horizontal and height > vertical:
        if out.fragment_count >= out.fragment_capacity: return -7
        let w: i64 = width - horizontal
        let h: i64 = height - vertical
        out.fragments[out.fragment_count] = CssFlowFragment(node, out.text_length, 0, inside.x, inside.y, 0, inside.x, inside.y, w, h, w, h, h)
        out.fragment_count += 1
    return max(y + height, inside.y) + bottom

unsafe fn web_text_node(doc: ptr<WebLayout>, flow: ptr<WebFlow>, node: i64) -> i64:
    let out: ptr<CssLayoutContext> = doc.output
    let token: ptr<HtmlNode> = &out.nodes[node]
    let length: i64 = html_decode_range(out.html_source as ptr<char>, doc.source_length, token.text_start, token.text_length, doc.scratch, doc.scratch_capacity)
    if length < 0: return length
    let start: i64 = 0
    if length > 0 and out.nodes[token.parent].first_child == node and html_name_equal(out.html_source, &out.nodes[token.parent], "pre"):
        if doc.scratch[0] == '\r': start += 1
        if start < length and doc.scratch[start] == '\n': start += 1
    return web_text(doc, flow, node, doc.scratch + start, length - start)

unsafe fn web_contents(doc: ptr<WebLayout>, node: i64, flow: ptr<WebFlow>, depth: i64) -> i64:
    if depth > 128: return -22
    let out: ptr<CssLayoutContext> = doc.output
    let override: ptr<CssTextOverride> = css_text_override(doc.overrides, node)
    if override != (0 as ptr<CssTextOverride>):
        let hidden: i64 = css_hide_subtree(out, node, depth)
        if hidden < 0: return hidden
        return web_text(doc, flow, node, &override.text[0], override.length)
    let child: i64 = out.nodes[node].first_child
    while child >= 0:
        if child % 64 == 0:
            let remaining: i64 = web_current(doc)
            if remaining < 0: return remaining
        let token: ptr<HtmlNode> = &out.nodes[child]
        let style: ptr<BrowserStyle> = &doc.styles[child]
        if style.display == 0:
            out.boxes[child].hidden = true
            let hidden: i64 = css_hide_subtree(out, child, depth + 1)
            if hidden < 0: return hidden
        elif token.kind == HTML_TEXT_NODE:
            let status: i64 = web_text_node(doc, flow, child)
            if status < 0: return status
        elif html_name_equal(out.html_source, token, "br"):
            web_line_break(doc, flow, style)
        elif style.display != WEB_INLINE or html_name_equal(out.html_source, token, "video"):
            web_flush(doc, flow)
            let top: i64 = web_margin(style, 0, flow.width)
            let next: i64 = web_block(doc, child, WebBlock(flow.x, flow.y - min(top, flow.margin), flow.width, flow.width, false), depth + 1)
            if next < 0: return next
            flow.y = next
            flow.margin = web_margin(style, 2, flow.width)
            flow.first = out.fragment_count
        elif html_name_equal(out.html_source, token, "img"):
            let status: i64 = web_image(doc, flow, child, -2)
            if status < 0: return status
        else:
            let first: i64 = out.fragment_count
            out.boxes[child].y = flow.y
            let status: i64 = web_contents(doc, child, flow, depth + 1)
            if status < 0: return status
            if out.fragment_count > first:
                let run: ptr<CssFlowFragment> = &out.fragments[first]
                out.boxes[child].y = run.y
        child = token.next_sibling
    return 0

struct BrowserVisualLayout:
    output: ptr<CssLayoutContext>
    visual: ptr<BrowserVisual>
    styles: ptr<BrowserStyle>
    attrs: ptr<HtmlAttribute>
    overrides: ptr<CssTextOverrides>
    transfer: ptr<HttpTransfer>

unsafe fn browser_visual_flow(ctx: ptr<BrowserVisualLayout>) -> i64:
    let out: ptr<CssLayoutContext> = ctx.output
    let fontmap: ptr<char> = pango_cairo_font_map_new()
    if fontmap == (0 as ptr<char>): return -12
    defer g_object_unref(fontmap)
    let context: ptr<char> = pango_font_map_create_context(fontmap)
    if context == (0 as ptr<char>): return -12
    defer g_object_unref(context)
    pango_context_set_round_glyph_positions(context, 0)
    let layout: ptr<char> = pango_layout_new(context)
    if layout == (0 as ptr<char>): return -12
    defer g_object_unref(layout)
    let font: ptr<char> = pango_font_description_new()
    if font == (0 as ptr<char>): return -12
    defer pango_font_description_free(font)
    pango_layout_set_single_paragraph_mode(layout, 1)
    let metrics: WebMetrics = WebMetrics(layout, font, 0, 0, 0 as i32, 0 as i32)
    let scratch: ByteBuffer
    defer bytes_free(&scratch)
    let flex_items: Buffer<WebFlexItem>
    defer buffer_free(&flex_items)
    let largest: i64 = 4096
    let i: i64 = 0
    while i < out.node_count:
        out.boxes[i] = CssLayoutBox(0, 0, 0, 0, false)
        largest = max(largest, out.nodes[i].text_length)
        i += 1
    if bytes_reserve(&scratch, largest + 1) < 0: return -12
    let doc: WebLayout = WebLayout(out, ctx.styles, &ctx.visual.images, ctx.attrs, &metrics, scratch.data as ptr<char>, largest + 1, __volt_strlen(out.html_source), ctx.overrides, ctx.transfer, 1, &flex_items)
    out.fragment_count = 0
    out.text_length = 0
    let flow: WebFlow = WebFlow(0, 0, out.viewport_width, 0, 0, 0, 0, 0, 0, false)
    let status: i64 = web_contents(&doc, 0, &flow, 0)
    if status < 0: return status
    web_flush(&doc, &flow)
    out.boxes[0] = CssLayoutBox(0, 0, out.viewport_width, flow.y, false)
    return out.node_count
