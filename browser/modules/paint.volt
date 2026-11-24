# VOLT-owned bounded software painter: framebuffer is packed 0xAARRGGBB u32 pixels.
use html
use css
use utf8

const PAINT_OK: i64 = 0
const PAINT_INVALID: i64 = -22

struct PaintSurface:
    pixels: ptr<u32>
    width: i64
    height: i64
    stride: i64
    capacity: i64

unsafe fn paint_surface_valid(surface: ptr<PaintSurface>) -> bool:
    if surface == (0 as ptr<PaintSurface>): return false
    if surface.pixels == (0 as ptr<u32>) or surface.width < 1 or surface.width > 4096 or surface.height < 1 or surface.height > 4096: return false
    if surface.stride < surface.width or surface.stride > 4096: return false
    let total: i64 = surface.stride * surface.height
    return total > 0 and surface.capacity >= total

unsafe fn paint_pixel(surface: ptr<PaintSurface>, x: i64, y: i64, color: i64):
    if not paint_surface_valid(surface): return
    if x < 0 or y < 0 or x >= surface.width or y >= surface.height: return
    surface.pixels[y * surface.stride + x] = (0xff000000 | color) as u32

unsafe fn paint_fill(surface: ptr<PaintSurface>, x: i64, y: i64, w: i64, h: i64, color: i64):
    if not paint_surface_valid(surface) or w <= 0 or h <= 0: return
    if x >= surface.width or y >= surface.height: return
    if x <= 0 - w or y <= 0 - h: return
    if x < 0 and x < 0 - surface.width: return
    if y < 0 and y < 0 - surface.height: return
    let x0: i64 = 0
    let y0: i64 = 0
    let x1: i64 = surface.width
    let y1: i64 = surface.height
    if x >= 0: x0 = x
    if y >= 0: y0 = y
    # Compare size against remaining viewport before adding, avoiding signed overflow.
    if x >= 0 and w < surface.width - x: x1 = x + w
    if y >= 0 and h < surface.height - y: y1 = y + h
    if x < 0 and w - (0 - x) < surface.width: x1 = w - (0 - x)
    if y < 0 and h - (0 - y) < surface.height: y1 = h - (0 - y)
    let row: i64 = y0
    while row < y1:
        let col: i64 = x0
        while col < x1:
            surface.pixels[row * surface.stride + col] = (0xff000000 | color) as u32
            col += 1
        row += 1

unsafe fn paint_cyrillic_row(index: i64, row: i64) -> i64:
    # Columns are А..Я and Ё. Each base-32 digit encodes a five-pixel row.
    let rows: [7]string = [
        "evuvevlehah7hhevuevh4hihllohgeifa",
        "hghgaglhh4i9rhhhhh4hehihll8hghlh0",
        "hghgage1jhk9lhhhhg4hlaihll8hg1lhv",
        "vuugau46ljo9lvhhug4fl4iflletu7tfg",
        "hhhgige1plk9hhhhgg41eai1ll9lh1l5u",
        "hhhgvglhhpi9hhhhgh4h4hv1lv9lhhl9g",
        "huughvlehhhhhhehge4e4h11v1etueihv"]
    let glyph: ptr<char> = rows[row] as ptr<char>
    let bits: i64 = glyph[index] as i64
    if bits >= 97: return bits - 87
    return bits - 48

# Fixed 5x7 Latin, Cyrillic and punctuation glyphs.
unsafe fn paint_glyph_row(c: i64, row: i64) -> i64:
    if row < 0 or row >= 7: return 0
    if c >= 97 and c <= 122: c -= 32
    if c >= 0x0430 and c <= 0x044f: c -= 32
    if c >= 0x0410 and c <= 0x042f: return paint_cyrillic_row(c - 0x0410, row)
    if c == 0x0401 or c == 0x0451: return paint_cyrillic_row(32, row)
    if c == 32 or c == 0xa0: return 0
    if c == 88: # X
        if row == 0 or row == 6: return 17
        if row == 1 or row == 5: return 10
        return 4
    if c == 79 or c == 48: # O / 0
        if row == 0 or row == 6: return 14
        return 17
    if c == 65: # A
        if row == 0: return 14
        if row == 3: return 31
        if row == 1 or row == 2: return 17
        return 17
    if c == 66: # B
        if row == 0 or row == 3 or row == 6: return 30
        return 17
    if c == 67: # C
        if row == 0 or row == 6: return 14
        return 16
    if c == 68: # D
        if row == 0 or row == 6: return 30
        return 17
    if c == 69: # E
        if row == 0 or row == 3 or row == 6: return 31
        return 16
    if c == 70: # F
        if row == 0: return 31
        if row == 3: return 30
        return 16
    if c == 71: # G
        if row == 0 or row == 6: return 14
        if row == 4: return 23
        if row == 5: return 17
        return 16
    if c == 72: # H
        if row == 3: return 31
        return 17
    if c == 73: # I
        if row == 0 or row == 6: return 14
        return 4
    if c == 74: # J
        if row == 0: return 7
        if row == 6: return 12
        return 2
    if c == 75: # K
        if row == 0 or row == 6: return 17
        if row == 3: return 28
        if row == 2 or row == 4: return 20
        return 18
    if c == 76: # L
        if row == 6: return 31
        return 16
    if c == 77: # M
        if row < 2: return 17
        if row == 2: return 27
        return 17
    if c == 78: # N
        if row == 0 or row == 6: return 17
        if row == 1: return 25
        if row == 2: return 21
        if row == 3: return 19
        if row == 4: return 17
        return 17
    if c == 80: # P
        if row == 0 or row == 3: return 30
        if row < 3: return 17
        return 16
    if c == 81: # Q
        if row == 0 or row == 6: return 14
        if row == 5: return 18
        return 17
    if c == 82: # R
        if row == 0 or row == 3: return 30
        if row < 3: return 17
        if row == 4: return 20
        if row == 5: return 18
        return 17
    if c == 83: # S
        if row == 0 or row == 6: return 15
        if row == 3: return 14
        if row < 3: return 16
        return 1
    if c == 84: # T
        if row == 0: return 31
        return 4
    if c == 85: # U
        if row == 6: return 14
        return 17
    if c == 86: # V
        if row < 5: return 17
        if row == 5: return 10
        return 4
    if c == 87: # W
        if row < 4: return 17
        if row == 4: return 21
        if row == 5: return 21
        return 10
    if c == 89: # Y
        if row < 2: return 17
        if row == 2: return 10
        return 4
    if c == 90: # Z
        if row == 0 or row == 6: return 31
        if row == 1: return 1
        if row == 2: return 2
        if row == 3: return 4
        if row == 4: return 8
        return 16
    if c == 49:
        if row == 0: return 4
        if row == 1: return 12
        if row == 6: return 14
        return 4
    if c == 50:
        if row == 0: return 14
        if row == 1: return 17
        if row == 2: return 1
        if row == 3: return 2
        if row == 4: return 4
        if row == 5: return 8
        return 31
    if c == 51:
        if row == 0 or row == 6: return 30
        if row == 3: return 14
        return 1
    if c == 52:
        if row == 0: return 2
        if row == 1: return 6
        if row == 2: return 10
        if row == 3: return 18
        if row == 4: return 31
        return 2
    if c == 53:
        if row == 0 or row == 6: return 31
        if row == 1 or row == 2: return 16
        if row == 3: return 30
        return 1
    if c == 54:
        if row == 0: return 14
        if row == 1 or row == 2: return 16
        if row == 3: return 30
        if row == 4 or row == 5: return 17
        return 14
    if c == 55:
        if row == 0: return 31
        if row == 1: return 1
        if row == 2: return 2
        if row == 3: return 4
        return 8
    if c == 56:
        if row == 0 or row == 3 or row == 6: return 14
        return 17
    if c == 57:
        if row == 0 or row == 6: return 14
        if row == 1 or row == 2: return 17
        if row == 3: return 15
        return 1
    if c == 46: # .
        if row == 5 or row == 6: return 12
        return 0
    if c == 44: # ,
        if row == 5: return 12
        if row == 6: return 8
        return 0
    if c == 33: # !
        if row == 5: return 0
        return 4
    if c == 63: # ? replacement glyph
        if row == 0: return 14
        if row == 1: return 17
        if row == 2: return 1
        if row == 3: return 2
        if row == 4: return 4
        if row == 5: return 0
        return 4
    if c == 45 or c == 0x2013 or c == 0x2014: # Dash
        if row == 3: return 31
        return 0
    if c == 58: # :
        if row == 2 or row == 5: return 4
        return 0
    if c == 47: # /
        return 1 << ((row * 4 + 3) / 6)
    if c == 60: # <
        if row >= 1 and row <= 5: return 8 >> abs(row - 3)
        return 0
    if c == 62: # >
        if row >= 1 and row <= 5: return 2 << abs(row - 3)
        return 0
    if c == 61: # =
        if row == 2 or row == 4: return 31
        return 0
    if c == 95: # _
        if row == 6: return 31
        return 0
    if c == 43: # +
        if row == 3: return 31
        if row >= 1 and row <= 5: return 4
        return 0
    if c == 38: # &
        let rows: [7]i64 = [12, 18, 20, 8, 21, 18, 13]
        return rows[row]
    if c == 37: # %
        let rows: [7]i64 = [17, 26, 2, 4, 8, 11, 17]
        return rows[row]
    # Unsupported code points use the same '?' fallback.
    if row == 0: return 14
    if row == 1: return 17
    if row == 2: return 1
    if row == 3: return 2
    if row == 4: return 4
    if row == 5: return 0
    return 4

unsafe fn paint_text(source: string, node: ptr<HtmlNode>, box: ptr<CssLayoutBox>, color: i64, surface: ptr<PaintSurface>):
    if box == (0 as ptr<CssLayoutBox>) or node == (0 as ptr<HtmlNode>): return
    if box.width <= 0 or box.height <= 0 or box.width > 4096 or box.height > 4096: return
    let decoded: [4097]char
    let length: i64 = html_decode_node_text(source, node, &decoded[0], 4097)
    if length < 0: return
    let right: i64 = 0
    let bottom: i64 = 0
    if box.x > 0 and box.width > 9223372036854775807 - box.x: return
    if box.y > 0 and box.height > 9223372036854775807 - box.y: return
    right = box.x + box.width
    bottom = box.y + box.height
    if right <= 0 or bottom <= 0 or box.x >= surface.width or box.y >= surface.height: return
    let left: i64 = box.x
    let top: i64 = box.y
    if left < 0: left = 0
    if top < 0: top = 0
    if right > surface.width: right = surface.width
    if bottom > surface.height: bottom = surface.height
    if top > 9223372036854775807 - 4: return
    let x: i64 = left
    let y: i64 = box.y + 4
    if y < top: y = top
    if y >= bottom: return
    let i: i64 = 0
    while i < length:
        let c: i64 = utf8_next(&decoded[0], &i, length)
        let row: i64 = 0
        while row < 7:
            let mask: i64 = paint_glyph_row(c, row)
            let col: i64 = 0
            while col < 5:
                if (mask & (1 << (4 - col))) != 0:
                    let gx: i64 = x + col
                    let gy: i64 = y + row
                    if gx >= left and gx < right and gy >= top and gy < bottom:
                        paint_pixel(surface, gx, gy, color)
                col += 1
            row += 1
        # Stop before advancing if the next glyph starts outside the clipped box.
        if x >= right or right - x <= 6: return
        x += 6

struct PaintFlowContext:
    fragments: ptr<CssFlowFragment>
    fragment_count: i64
    text_bytes: ptr<char>
    text_length: i64

struct PaintGlyphContext:
    text: ptr<char>
    length: i64
    x_start: i64
    y_start: i64
    clip_x: i64
    clip_y: i64
    clip_width: i64
    clip_height: i64
    color: i64
    surface: ptr<PaintSurface>

struct PaintScrollState:
    offset: i64
    max_offset: i64

const SCROLL_KEY_UP: i64 = 1073741906
const SCROLL_KEY_DOWN: i64 = 1073741905
const SCROLL_KEY_PAGEUP: i64 = 1073741899
const SCROLL_KEY_PAGEDOWN: i64 = 1073741902
const SCROLL_KEY_HOME: i64 = 1073741898
const SCROLL_KEY_END: i64 = 1073741901

unsafe fn paint_scroll_max(document_height: i64, viewport_height: i64) -> i64:
    if document_height < 0 or viewport_height <= 0: return -22
    if document_height <= viewport_height: return 0
    return document_height - viewport_height

unsafe fn paint_scroll_update(state: ptr<PaintScrollState>, delta: i64) -> i64:
    if state == (0 as ptr<PaintScrollState>) or state.max_offset < 0 or state.offset < 0 or state.offset > state.max_offset: return -22
    let old: i64 = state.offset
    if delta > 0:
        if delta >= state.max_offset - state.offset: state.offset = state.max_offset
        else: state.offset += delta
    elif delta < 0:
        if delta == -9223372036854775807 or delta == -9223372036854775808: state.offset = 0
        elif -delta >= state.offset: state.offset = 0
        else: state.offset += delta
    return state.offset - old

unsafe fn paint_scroll_key(state: ptr<PaintScrollState>, key: i64, viewport_height: i64) -> i64:
    if viewport_height <= 0: return -22
    if key == 0: return 0
    if viewport_height < 32: return -22
    let delta: i64 = 0
    if key == SCROLL_KEY_UP: delta = -32
    elif key == SCROLL_KEY_DOWN: delta = 32
    elif key == SCROLL_KEY_PAGEUP: delta = 0 - (viewport_height - 32)
    elif key == SCROLL_KEY_PAGEDOWN: delta = viewport_height - 32
    elif key == SCROLL_KEY_HOME:
        if state == (0 as ptr<PaintScrollState>) or state.max_offset < 0 or state.offset < 0 or state.offset > state.max_offset: return -22
        let change: i64 = 0 - state.offset
        state.offset = 0
        return change
    elif key == SCROLL_KEY_END:
        if state == (0 as ptr<PaintScrollState>) or state.max_offset < 0 or state.offset < 0 or state.offset > state.max_offset: return -22
        let change: i64 = state.max_offset - state.offset
        state.offset = state.max_offset
        return change
    else: return 0
    return paint_scroll_update(state, delta)

unsafe fn paint_text_run(context: ptr<PaintGlyphContext>):
    if context.length < 0 or context.length > HTML_DOCUMENT_LIMIT or context.clip_width <= 0 or context.clip_height <= 0 or context.x_start < 0 or context.y_start < -2147483647 or context.y_start > 9223372036854775796: return
    if context.clip_x > 9223372036854775807 - context.clip_width or context.clip_y > 9223372036854775807 - context.clip_height: return
    let clip_right: i64 = context.clip_x + context.clip_width
    let clip_bottom: i64 = context.clip_y + context.clip_height
    if context.clip_x >= context.surface.width or context.clip_y >= context.surface.height or clip_right <= 0 or clip_bottom <= 0: return
    let right: i64 = clip_right
    let bottom: i64 = clip_bottom
    if right > context.surface.width: right = context.surface.width
    if bottom > context.surface.height: bottom = context.surface.height
    if context.x_start >= right or context.y_start >= bottom: return
    let i: i64 = 0
    let gx: i64 = context.x_start
    while i < context.length and gx < right:
        let code: i64 = utf8_next(context.text, &i, context.length)
        let row: i64 = 0
        while row < 7:
            let gy: i64 = context.y_start + row + 4
            if gy >= context.clip_y and gy < bottom and code != 32:
                let col: i64 = 0
                let mask: i64 = paint_glyph_row(code, row)
                while col < 5:
                    let px: i64 = gx + col
                    if (mask & (1 << (4 - col))) != 0 and px >= context.clip_x and px < right:
                        paint_pixel(context.surface, px, gy, context.color)
                    col += 1
            row += 1
        gx += 6

# Consumes only validated DOM/style/layout output; framebuffer stride is in u32 pixels.
struct PaintDocumentContext:
    source: string
    nodes: ptr<HtmlNode>
    styles: ptr<CssResolvedStyle>
    boxes: ptr<CssLayoutBox>
    count: i64
    flow: ptr<PaintFlowContext>
    surface: ptr<PaintSurface>

unsafe fn paint_document_fragments(context: ptr<PaintDocumentContext>) -> i64:
    return paint_document_fragments_scrolled(context, 0)

unsafe fn paint_document_fragments_scrolled(context: ptr<PaintDocumentContext>, scroll_y: i64) -> i64:
    return paint_document_fragments_on(context, scroll_y, 0)

unsafe fn paint_document_fragments_on(context: ptr<PaintDocumentContext>, scroll_y: i64, background: i64) -> i64:
    if context == (0 as ptr<PaintDocumentContext>) or background < 0 or background > 0xffffff: return PAINT_INVALID
    let surface: ptr<PaintSurface> = context.surface
    let nodes: ptr<HtmlNode> = context.nodes
    let styles: ptr<CssResolvedStyle> = context.styles
    let boxes: ptr<CssLayoutBox> = context.boxes
    let count: i64 = context.count
    let flow: ptr<PaintFlowContext> = context.flow
    if not paint_surface_valid(surface) or count < 1 or count > HTML_NODE_LIMIT or scroll_y < 0 or scroll_y > 2147483647: return PAINT_INVALID
    if nodes == (0 as ptr<HtmlNode>) or styles == (0 as ptr<CssResolvedStyle>) or boxes == (0 as ptr<CssLayoutBox>) or flow == (0 as ptr<PaintFlowContext>) or flow.fragments == (0 as ptr<CssFlowFragment>) or flow.text_bytes == (0 as ptr<char>): return PAINT_INVALID
    if scroll_y > 0 and surface.height > 9223372036854775807 - scroll_y: return PAINT_INVALID
    if flow.fragment_count < 0 or flow.fragment_count > CSS_FRAGMENT_LIMIT or flow.text_length < 0 or flow.text_length > HTML_DOCUMENT_LIMIT: return PAINT_INVALID
    let fragments: ptr<CssFlowFragment> = flow.fragments
    let fragment_count: i64 = flow.fragment_count
    let text_bytes: ptr<char> = flow.text_bytes
    let text_length: i64 = flow.text_length
    let i: i64 = 0
    while i < fragment_count:
        let fragment: ptr<CssFlowFragment> = &fragments[i]
        if fragment.node_index < 0 or fragment.node_index >= count or fragment.byte_start < 0 or fragment.byte_length < 0 or fragment.byte_start > text_length or fragment.byte_length > text_length - fragment.byte_start or fragment.clip_width <= 0 or fragment.clip_height <= 0 or fragment.x < fragment.clip_x or fragment.y < fragment.clip_y or fragment.color_rgb < 0 or fragment.color_rgb > 16777215: return PAINT_INVALID
        if fragment.clip_x > 9223372036854775807 - fragment.clip_width or fragment.clip_y > 9223372036854775807 - fragment.clip_height: return PAINT_INVALID
        i += 1
    let total: i64 = surface.stride * surface.height
    i = 0
    while i < total:
        surface.pixels[i] = (0xff000000 | background) as u32
        i += 1
    # Draw each node's background then its text to retain preorder overlap.
    let node_index: i64 = 1
    let fragment_index: i64 = 0
    while node_index < count:
        if not boxes[node_index].hidden:
            if nodes[node_index].kind == HTML_ELEMENT and styles[node_index].background_rgb >= 0:
                let background_y: i64 = boxes[node_index].y - scroll_y
                let background_height: i64 = boxes[node_index].height
                if background_y < 0:
                    if background_height <= -background_y: background_height = 0
                    else: background_height += background_y
                    background_y = 0
                if background_y < surface.height and background_height > 0 and background_height <= surface.height - background_y:
                    paint_fill(surface, boxes[node_index].x, background_y, boxes[node_index].width, background_height, styles[node_index].background_rgb)
                elif background_y < surface.height and background_height > 0:
                    paint_fill(surface, boxes[node_index].x, background_y, boxes[node_index].width, surface.height - background_y, styles[node_index].background_rgb)
            while fragment_index < fragment_count and fragments[fragment_index].node_index == node_index:
                let fragment: ptr<CssFlowFragment> = &fragments[fragment_index]
                let translated_y: i64 = fragment.y - scroll_y
                let translated_clip_y: i64 = fragment.clip_y - scroll_y
                if translated_y >= -10 and translated_y < surface.height and translated_clip_y < surface.height and translated_clip_y + fragment.clip_height > 0:
                    let glyph: PaintGlyphContext = PaintGlyphContext(&text_bytes[fragment.byte_start], fragment.byte_length, fragment.x, translated_y, fragment.clip_x, translated_clip_y, fragment.clip_width, fragment.clip_height, fragment.color_rgb, surface)
                    paint_text_run(&glyph)
                fragment_index += 1
        node_index += 1
    if fragment_index != fragment_count: return PAINT_INVALID
    return PAINT_OK

unsafe fn paint_document(source: string, nodes: ptr<HtmlNode>, styles: ptr<CssResolvedStyle>, boxes: ptr<CssLayoutBox>, count: i64, surface: ptr<PaintSurface>) -> i64:
    if not paint_surface_valid(surface) or count < 1 or count > 4096: return PAINT_INVALID
    if nodes == (0 as ptr<HtmlNode>) or styles == (0 as ptr<CssResolvedStyle>) or boxes == (0 as ptr<CssLayoutBox>): return PAINT_INVALID
    let total: i64 = surface.stride * surface.height
    let i: i64 = 0
    while i < total:
        surface.pixels[i] = 0xff000000 as u32
        i += 1
    i = 1
    while i < count:
        if not boxes[i].hidden:
            if nodes[i].kind == HTML_ELEMENT and styles[i].background_rgb >= 0:
                paint_fill(surface, boxes[i].x, boxes[i].y, boxes[i].width, boxes[i].height, styles[i].background_rgb)
            elif nodes[i].kind == HTML_TEXT_NODE:
                let parent: i64 = nodes[i].parent
                let color: i64 = 0
                if parent >= 0 and parent < count: color = styles[parent].color_rgb
                paint_text(source, &nodes[i], &boxes[i], color, surface)
        i += 1
    return PAINT_OK
