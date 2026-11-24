use css
use browser_colors
use http

const WEB_INLINE: i64 = 1
const WEB_BLOCK: i64 = 2
const WEB_FLEX: i64 = 3
const WEB_GRID: i64 = 4
const WEB_TABLE: i64 = 5
const WEB_TABLE_ROW: i64 = 6
const WEB_AUTO: i64 = -1
const WEB_FIT: i64 = -3
const WEB_CURRENT_COLOR: i64 = -3
const WEB_PERCENT: i64 = 1000000
const WEB_EM: i64 = 2000000
const WEB_REM: i64 = 3000000
const WEB_LINE_RATIO: i64 = 4000000
const WEB_VW: i64 = 5000000
const WEB_VH: i64 = 6000000
const WEB_TRACK_SCALE: i64 = 10000000

const WEB_ALIGN_STRETCH: i64 = 0
const WEB_ALIGN_START: i64 = 1
const WEB_ALIGN_CENTER: i64 = 2
const WEB_ALIGN_END: i64 = 3
const WEB_JUSTIFY_BETWEEN: i64 = 4
const WEB_JUSTIFY_AROUND: i64 = 5
const WEB_JUSTIFY_EVENLY: i64 = 6

struct BrowserStyleSheet:
    source: ByteBuffer
    rules: Buffer<CssRule>
    selectors: Buffer<CssSelector>
    declarations: Buffer<CssDeclaration>
    counts: CssParseCounts
    defaults: i64
    block_inline: bool
    viewport_units: bool

struct BrowserStyle:
    color: i64
    background: i64
    display: i64
    margin: [4]i64
    padding: [4]i64
    width: i64
    width_set: bool
    max_width: i64
    min_width: i64
    height: i64
    height_set: bool
    min_height: i64
    border: i64
    border_color: i64
    radius: i64
    font: i64
    family: i64
    weight: i32
    italic: i32
    line_height: i64
    align: i64
    underline: bool
    border_box: bool
    column_gap: i64
    row_gap: i64
    flex_column: bool
    flex_wrap: bool
    columns: i64
    tracks: [8]i64
    whitespace: i64
    align_items: i64
    align_self: i64
    justify: i64
    grow: i64
    shrink: i64
    basis: i64
    gradient: [5]i64
    shadow: [5]i64
    object_fit: i64
    aspect: i64

struct WebValue:
    field: i64
    values: [9]i64

struct WebWinner:
    rank: i64
    value: i64

struct WebSelector:
    specificity: i64
    compound: bool

# Margin/padding sides have separate cascade slots for their shorthand and longhands.
const WEB_FIELDS: i64 = 59
const WEB_PADDING_ALL: i64 = 64
const WEB_MARGIN_ALL: i64 = 65
const WEB_BORDER_ALL: i64 = 66
const WEB_FONT_ALL: i64 = 67
const WEB_BACKGROUND_ALL: i64 = 68
const WEB_GRADIENT_ALL: i64 = 69
const WEB_SHADOW_ALL: i64 = 70
const WEB_GRID_ALL: i64 = 71
const WEB_GAP_ALL: i64 = 72
const WEB_FLEX_ALL: i64 = 73
const WEB_IMPORTANT: i64 = 8589934592

unsafe fn browser_sheet_free(sheet: ptr<BrowserStyleSheet>):
    bytes_free(&sheet.source)
    buffer_free(&sheet.rules)
    buffer_free(&sheet.selectors)
    buffer_free(&sheet.declarations)

unsafe fn browser_sheet_reset(sheet: ptr<BrowserStyleSheet>) -> i64:
    if bytes_reserve(&sheet.source, CSS_STYLESHEET_LIMIT + 1) < 0: return -12
    if buffer_reserve(&sheet.rules, 1024) < 0 or buffer_reserve(&sheet.selectors, 4096) < 0 or buffer_reserve(&sheet.declarations, 8192) < 0: return -12
    sheet.source.len = 0
    sheet.source.data[0] = 0
    sheet.counts = CssParseCounts(0, 0, 0)
    sheet.defaults = 0
    sheet.block_inline = false
    sheet.viewport_units = false
    return 0

unsafe fn web_has_viewport_units(p: ptr<char>, length: i64) -> bool:
    let i: i64 = 1
    while i + 1 < length:
        if p[i - 1] >= '0' and p[i - 1] <= '9' and (p[i] == 'v' or p[i] == 'V'):
            if p[i + 1] == 'w' or p[i + 1] == 'W' or p[i + 1] == 'h' or p[i + 1] == 'H': return true
        i += 1
    return false

# Each source has its own parser boundary so a broken sheet cannot swallow the next.
unsafe fn browser_sheet_add(sheet: ptr<BrowserStyleSheet>, bytes: ptr<char>, length: i64, media: bool, bounds: CssMediaRange) -> i64:
    let start: i64 = sheet.source.len
    if length < 0 or length > CSS_STYLESHEET_LIMIT - start: return -7
    let target: ptr<char> = sheet.source.data as ptr<char>
    let i: i64 = 0
    while i < length:
        if bytes[i] == '\0':
            target[start] = '\0'
            return -22
        target[start + i] = bytes[i]
        i += 1
    target[start + length] = '\0'
    let counts: CssParseCounts = sheet.counts
    let tables: CssBuffers = CssBuffers(buffer_data(&sheet.rules), 1024, buffer_data(&sheet.selectors), 4096, buffer_data(&sheet.declarations), 8192)
    let first: i64 = start
    if length >= 3 and (bytes[0] as i64) == 239 and (bytes[1] as i64) == 187 and (bytes[2] as i64) == 191: first += 3
    let parsed: i64 = css_parse_range(target, first, start + length, &tables, &sheet.counts, media)
    if parsed < 0:
        target[start] = '\0'
        sheet.counts = counts
        return parsed
    sheet.source.len += length
    if not sheet.viewport_units: sheet.viewport_units = web_has_viewport_units(bytes, length)
    i = counts.rule_count
    while i < sheet.counts.rule_count:
        tables.rules[i].min_width = max(tables.rules[i].min_width, bounds.min_width)
        tables.rules[i].max_width = min(tables.rules[i].max_width, bounds.max_width)
        i += 1
    return 0

unsafe fn web_length(p: ptr<char>, begin: i64, end: i64) -> i64:
    let at: i64 = begin
    let whole: i64 = 0
    let digits: i64 = 0
    while at < end and p[at] >= '0' and p[at] <= '9':
        whole = whole * 10 + (p[at] as i64 - 48)
        if whole > 4096: return -2
        at += 1
        digits += 1
    let fraction: i64 = 0
    let scale: i64 = 1
    if at < end and p[at] == '.':
        at += 1
        while at < end and p[at] >= '0' and p[at] <= '9':
            if scale < 100:
                scale *= 10
                fraction = fraction * 10 + (p[at] as i64 - 48)
            at += 1
            digits += 1
    if digits == 0: return -2
    let hundredths: i64 = whole * 100 + fraction * (100 / scale)
    if whole == 0 and fraction == 0 and at == end: return 0
    if css_range_equal(p as string, at, end - at, "px"): return (hundredths + 50) / 100
    if css_range_equal(p as string, at, end - at, "%"): return WEB_PERCENT + hundredths
    if css_range_equal(p as string, at, end - at, "em"): return WEB_EM + hundredths
    if css_range_equal(p as string, at, end - at, "rem"): return WEB_REM + hundredths
    if css_range_equal(p as string, at, end - at, "vw"): return WEB_VW + hundredths
    if css_range_equal(p as string, at, end - at, "vh"): return WEB_VH + hundredths
    return -2

fn web_viewport_pixels(length: i64, width: i64, height: i64) -> i64:
    if length >= WEB_VH: return min(4096, (length - WEB_VH) * height / 10000)
    if length >= WEB_VW: return min(4096, (length - WEB_VW) * width / 10000)
    return length

fn web_pixels(length: i64, available: i64, font: i64) -> i64:
    if length < 0: return length
    if length >= WEB_REM: return min(4096, (length - WEB_REM) * 16 / 100)
    if length >= WEB_EM: return min(4096, (length - WEB_EM) * font / 100)
    if length >= WEB_PERCENT: return min(4096, (length - WEB_PERCENT) * available / 10000)
    return length

unsafe fn web_edges(p: ptr<char>, start: i64, end: i64, margin: bool, value: ptr<WebValue>) -> bool:
    let n: i64 = 0
    while start < end:
        if n == 4: return false
        let stop: i64 = start
        while stop < end and not css_space(p[stop]): stop += 1
        let dim: i64 = web_length(p, start, stop)
        if margin and css_range_equal(p as string, start, stop - start, "auto"): dim = WEB_AUTO
        if dim < WEB_AUTO: return false
        value.values[n] = dim
        n += 1
        start = css_trim_start(p, stop, end)
    if n == 0: return false
    if n == 1: value.values[1] = value.values[0]
    if n < 3: value.values[2] = value.values[0]
    if n < 4: value.values[3] = value.values[1]
    return true

unsafe fn web_border(source: string, decl: ptr<CssDeclaration>, value: ptr<WebValue>) -> bool:
    if css_value_equal(source, decl, "none"):
        value.values[0] = 0
        value.values[1] = WEB_CURRENT_COLOR
        return true
    let p: ptr<char> = source as ptr<char>
    let i: i64 = decl.value_start
    let end: i64 = i + decl.value_length
    let width: i64 = 3
    let color: i64 = WEB_CURRENT_COLOR
    let solid: bool = false
    while i < end:
        let stop: i64 = web_component_end(p, i, end)
        let part: CssDeclaration = CssDeclaration(0, 0, 0, i, stop - i, false)
        let dim: i64 = web_length(p, i, stop)
        if dim >= 0 and dim < WEB_PERCENT: width = dim
        elif css_value_equal(source, &part, "solid"): solid = true
        else:
            if css_value_equal(source, &part, "currentcolor"): color = WEB_CURRENT_COLOR
            else:
                color = web_color(source, &part)
                if color == -2: return false
        i = css_trim_start(p, stop, end)
    if not solid: return false
    value.values[0] = min(32, width)
    value.values[1] = color
    return true

unsafe fn web_track(p: ptr<char>, start: i64, end: i64) -> i64:
    if end - start > 2 and css_range_equal(p as string, end - 2, 2, "fr"):
        let i: i64 = start
        let weight: i64 = web_decimal(p, &i, end - 2)
        if i == end - 2 and weight > 0 and weight <= 6400: return weight * WEB_TRACK_SCALE
        return -2
    if end - start > 10 and p[end - 1] == ')' and css_range_equal(p as string, start, 7, "minmax("):
        let i: i64 = css_trim_start(p, start + 7, end - 1)
        let comma: i64 = i
        if css_find_delimiter(p, &comma, end - 1, ',', ',') < 0 or comma == end - 1: return -2
        let size: i64 = web_length(p, i, css_trim_end(p, i, comma))
        i = css_trim_start(p, comma + 1, end - 1)
        let right: i64 = css_trim_end(p, i, end - 1)
        if size < 0 or right - i <= 2 or not css_range_equal(p as string, right - 2, 2, "fr"): return -2
        let weight: i64 = web_decimal(p, &i, right - 2)
        if i != right - 2 or weight <= 0 or weight > 6400: return -2
        return weight * WEB_TRACK_SCALE + size
    return web_length(p, start, end)

unsafe fn web_grid_columns(p: ptr<char>, start: i64, end: i64, value: ptr<WebValue>) -> bool:
    let i: i64 = start
    value.field = WEB_GRID_ALL
    if css_range_equal(p as string, start, end - start, "none"):
        value.values[0] = 1
        value.values[1] = 100 * WEB_TRACK_SCALE
        return true
    if end - start >= 12 and css_range_equal(p as string, start, 7, "repeat(") and p[end - 1] == ')':
        i = css_trim_start(p, start + 7, end - 1)
        let comma: i64 = i
        if css_find_delimiter(p, &comma, end - 1, ',', ',') < 0 or comma == end - 1: return false
        let n: i64 = css_trim_end(p, i, comma) - i
        let left: i64 = css_trim_start(p, comma + 1, end - 1)
        let track: i64 = web_track(p, left, css_trim_end(p, left, end - 1))
        if track < 0: return false
        let mode: i64 = 0
        if css_range_equal(p as string, i, n, "auto-fit"): mode = -1
        elif css_range_equal(p as string, i, n, "auto-fill"): mode = -2
        if mode != 0:
            if track % WEB_TRACK_SCALE <= 0: return false
            value.values[0] = mode
            value.values[1] = track
            return true
        if n != 1 or p[i] < '1' or p[i] > '8': return false
        let count: i64 = p[i] as i64 - 48
        value.values[0] = count
        let column: i64 = 1
        while column <= count:
            value.values[column] = track
            column += 1
        return true
    let count: i64 = 0
    while i < end:
        if count == 8: return false
        let stop: i64 = web_component_end(p, i, end)
        let track: i64 = web_track(p, i, stop)
        if track < 0: return false
        count += 1
        value.values[count] = track
        i = css_trim_start(p, stop, end)
    value.values[0] = count
    return count > 0

unsafe fn web_font_size(p: ptr<char>, start: i64, end: i64) -> i64:
    let source: string = p as string
    if css_range_equal(source, start, end - start, "small"): return 13
    if css_range_equal(source, start, end - start, "medium"): return 16
    if css_range_equal(source, start, end - start, "large"): return 18
    return web_length(p, start, end)

unsafe fn web_font_family(p: ptr<char>, start: i64, end: i64) -> i64:
    let source: string = p as string
    let i: i64 = start
    while i < end:
        let comma: i64 = i
        if css_find_delimiter(p, &comma, end, ',', ',') < 0: return -2
        let left: i64 = css_trim_start(p, i, comma)
        let right: i64 = css_trim_end(p, left, comma)
        if left == right: return -2
        if right - left >= 2 and (p[left] == '\'' or p[left] == '"') and p[left] == p[right - 1]:
            left += 1
            right -= 1
        let n: i64 = right - left
        if css_range_equal(source, left, n, "monospace") or css_range_equal(source, left, n, "Courier New"): return 2
        if css_range_equal(source, left, n, "serif") or css_range_equal(source, left, n, "Times New Roman"): return 0
        if css_range_equal(source, left, n, "sans-serif") or css_range_equal(source, left, n, "Arial"): return 1
        if css_range_equal(source, left, n, "system-ui"): return 3
        i = comma + 1
    if start == end: return -2
    return 0

unsafe fn web_font_weight(p: ptr<char>, start: i64, end: i64) -> i64:
    if css_range_equal(p as string, start, end - start, "normal"): return 400
    if css_range_equal(p as string, start, end - start, "bold") or css_range_equal(p as string, start, end - start, "bolder"): return 700
    if end - start == 3 and p[start] >= '1' and p[start] <= '9' and p[start + 1] == '0' and p[start + 2] == '0': return (p[start] as i64 - 48) * 100
    return -2

unsafe fn web_line_height(p: ptr<char>, start: i64, end: i64) -> i64:
    if css_range_equal(p as string, start, end - start, "normal"): return WEB_AUTO
    let length: i64 = web_length(p, start, end)
    if length >= 0: return length
    let i: i64 = start
    let scale: i64 = 100
    let factor: i64 = 0
    let dot: bool = false
    while i < end:
        if p[i] == '.' and not dot: dot = true
        elif p[i] >= '0' and p[i] <= '9':
            if dot:
                scale /= 10
                factor += (p[i] as i64 - 48) * scale
            else:
                factor = factor * 10 + (p[i] as i64 - 48) * 100
                if factor > 1000: return -2
        else: return -2
        i += 1
    if factor > 0: return WEB_LINE_RATIO + factor
    return -2

unsafe fn web_font_shorthand(p: ptr<char>, start: i64, end: i64, value: ptr<WebValue>) -> bool:
    let i: i64 = start
    let size: i64 = -2
    let weight: i64 = 400
    let italic: i64 = 0
    let line: i64 = WEB_AUTO
    let weight_seen: bool = false
    let position_seen: bool = false
    while i < end:
        let stop: i64 = i
        while stop < end and not css_space(p[stop]) and p[stop] != '/': stop += 1
        if stop == i: return false
        size = web_font_size(p, i, stop)
        if size >= 0:
            i = css_trim_start(p, stop, end)
            break
        if css_range_equal(p as string, i, stop - i, "italic") or css_range_equal(p as string, i, stop - i, "oblique"):
            if position_seen: return false
            position_seen = true
            italic = 2
            if css_range_equal(p as string, i, stop - i, "oblique"): italic = 1
        elif not css_range_equal(p as string, i, stop - i, "normal"):
            if weight_seen: return false
            weight = web_font_weight(p, i, stop)
            if weight < 0: return false
            weight_seen = true
        i = css_trim_start(p, stop, end)
    if size < 0 or i == end: return false
    if p[i] == '/':
        i = css_trim_start(p, i + 1, end)
        let stop: i64 = i
        while stop < end and not css_space(p[stop]): stop += 1
        line = web_line_height(p, i, stop)
        if line == -2: return false
        i = css_trim_start(p, stop, end)
    let family: i64 = web_font_family(p, i, end)
    if family < 0: return false
    value.field = WEB_FONT_ALL
    value.values[0] = size
    value.values[1] = family
    value.values[2] = weight
    value.values[3] = italic
    value.values[4] = line
    return true

unsafe fn web_background(source: string, decl: ptr<CssDeclaration>, value: ptr<WebValue>, kind: i64) -> bool:
    let p: ptr<char> = source as ptr<char>
    let start: i64 = decl.value_start
    let end: i64 = start + decl.value_length
    if kind != 1:
        if web_gradient(p, start, end, &value.values[0]):
            value.field = WEB_GRADIENT_ALL
            if kind == 0:
                value.field = WEB_BACKGROUND_ALL
                value.values[5] = -1
            return true
        if css_value_equal(source, decl, "none"):
            value.field = WEB_GRADIENT_ALL
            if kind == 0:
                value.field = WEB_BACKGROUND_ALL
                value.values[5] = -1
            return true
        if kind == 2: return false
        let stop: i64 = web_component_end(p, start, end)
        let next: i64 = css_trim_start(p, stop, end)
        if next < end:
            let color: i64 = -2
            if web_gradient(p, start, stop, &value.values[0]): color = web_color_part(p, next, end)
            elif web_gradient(p, next, end, &value.values[0]): color = web_color_part(p, start, stop)
            if color != -2:
                value.field = WEB_BACKGROUND_ALL
                value.values[5] = color
                return true
    let color: i64 = web_color(source, decl)
    if color == -2: return false
    value.field = 1
    if kind == 0:
        value.field = WEB_BACKGROUND_ALL
        value.values[5] = color
    else: value.values[0] = color
    return true

unsafe fn web_signed_pixels(p: ptr<char>, start: i64, end: i64) -> i64:
    let i: i64 = start
    let number: i64 = web_decimal(p, &i, end)
    if number == WEB_BAD_NUMBER or number < -25600 or number > 25600: return WEB_BAD_NUMBER
    if not (number == 0 and i == end) and not css_range_equal(p as string, i, end - i, "px"): return WEB_BAD_NUMBER
    if number < 0: return 0 - ((0 - number + 50) / 100)
    return (number + 50) / 100

unsafe fn web_shadow(source: string, decl: ptr<CssDeclaration>, value: ptr<WebValue>) -> bool:
    value.field = WEB_SHADOW_ALL
    if css_value_equal(source, decl, "none"): return true
    let p: ptr<char> = source as ptr<char>
    let i: i64 = decl.value_start
    let end: i64 = i + decl.value_length
    let count: i64 = 0
    let color_seen: bool = false
    let ink: i64 = WEB_CURRENT_COLOR
    while i < end:
        let stop: i64 = web_component_end(p, i, end)
        let length: i64 = web_signed_pixels(p, i, stop)
        if length == WEB_BAD_NUMBER:
            if color_seen: return false
            if css_range_equal(source, i, stop - i, "currentcolor"): ink = WEB_CURRENT_COLOR
            else: ink = web_color_part(p, i, stop)
            if ink == -2: return false
            color_seen = true
        else:
            if count == 4 or (count == 2 and length < 0): return false
            value.values[count + 1] = length
            count += 1
        i = css_trim_start(p, stop, end)
    if count < 2: return false
    if ink == WEB_CURRENT_COLOR: value.values[0] = -1
    elif ink >= 0: value.values[0] = ink + 1
    return true

unsafe fn web_box_align(source: string, decl: ptr<CssDeclaration>, justify: bool) -> i64:
    if css_value_equal(source, decl, "center"): return WEB_ALIGN_CENTER
    if css_value_equal(source, decl, "flex-end") or css_value_equal(source, decl, "end"): return WEB_ALIGN_END
    if css_value_equal(source, decl, "flex-start") or css_value_equal(source, decl, "start"): return WEB_ALIGN_START
    if css_value_equal(source, decl, "normal") or css_value_equal(source, decl, "stretch"): return WEB_ALIGN_STRETCH
    if justify:
        if css_value_equal(source, decl, "space-between"): return WEB_JUSTIFY_BETWEEN
        if css_value_equal(source, decl, "space-around"): return WEB_JUSTIFY_AROUND
        if css_value_equal(source, decl, "space-evenly"): return WEB_JUSTIFY_EVENLY
    return -2

unsafe fn web_flex_factor(p: ptr<char>, i: i64, stop: i64) -> i64:
    let at: i64 = i
    let weight: i64 = web_decimal(p, &at, stop)
    if at != stop or weight < 0 or weight > 6400: return -2
    return weight

unsafe fn web_flex_basis(p: ptr<char>, i: i64, stop: i64) -> i64:
    if css_range_equal(p as string, i, stop - i, "auto"): return WEB_AUTO
    return web_length(p, i, stop)

unsafe fn web_flex(p: ptr<char>, start: i64, end: i64, value: ptr<WebValue>) -> bool:
    value.field = WEB_FLEX_ALL
    let source: string = p as string
    value.values[0] = 100
    value.values[1] = 100
    value.values[2] = WEB_AUTO
    if css_range_equal(source, start, end - start, "auto"): return true
    if css_range_equal(source, start, end - start, "none"):
        value.values[0] = 0
        value.values[1] = 0
        return true
    if css_range_equal(source, start, end - start, "initial"):
        value.values[0] = 0
        return true
    let stop: i64 = web_component_end(p, start, end)
    let grow: i64 = web_flex_factor(p, start, stop)
    let i: i64 = css_trim_start(p, stop, end)
    if grow < 0:
        if i != end: return false
        value.values[2] = web_flex_basis(p, start, stop)
        return value.values[2] >= WEB_AUTO
    value.values[0] = grow
    value.values[2] = 0
    if i == end: return true
    stop = web_component_end(p, i, end)
    let shrink: i64 = web_flex_factor(p, i, stop)
    if shrink < 0:
        value.values[2] = web_flex_basis(p, i, stop)
        return value.values[2] >= WEB_AUTO and css_trim_start(p, stop, end) == end
    value.values[1] = shrink
    i = css_trim_start(p, stop, end)
    if i == end: return true
    value.values[2] = web_flex_basis(p, i, end)
    return value.values[2] >= WEB_AUTO

unsafe fn web_aspect(p: ptr<char>, start: i64, end: i64) -> i64:
    if css_range_equal(p as string, start, end - start, "auto"): return 0
    let i: i64 = start
    let first: i64 = web_decimal(p, &i, end)
    if first <= 0: return -2
    i = css_trim_start(p, i, end)
    let second: i64 = 100
    if i < end and p[i] == '/':
        i = css_trim_start(p, i + 1, end)
        second = web_decimal(p, &i, end)
        i = css_trim_start(p, i, end)
    if i != end or second <= 0: return -2
    let ratio: i64 = (first * 10000 + second / 2) / second
    if ratio < 100 or ratio > 1000000: return -2
    return ratio

unsafe fn web_property(source: string, decl: ptr<CssDeclaration>, value: ptr<WebValue>) -> bool:
    let p: ptr<char> = source as ptr<char>
    let start: i64 = decl.value_start
    let end: i64 = start + decl.value_length
    let field: i64 = -1
    let result: i64 = -2
    let length: bool = false
    if css_property_equal(source, decl, "color"):
        field = 0
        result = web_color(source, decl)
    elif css_property_equal(source, decl, "background"): return web_background(source, decl, value, 0)
    elif css_property_equal(source, decl, "background-color"): return web_background(source, decl, value, 1)
    elif css_property_equal(source, decl, "background-image"): return web_background(source, decl, value, 2)
    elif css_property_equal(source, decl, "box-shadow"): return web_shadow(source, decl, value)
    elif css_property_equal(source, decl, "display"):
        field = 2
        if css_value_equal(source, decl, "none"): result = 0
        elif css_value_equal(source, decl, "inline") or css_value_equal(source, decl, "inline-block"): result = WEB_INLINE
        elif css_value_equal(source, decl, "block") or css_value_equal(source, decl, "list-item") or css_value_equal(source, decl, "flow-root"): result = WEB_BLOCK
        elif css_value_equal(source, decl, "flex"): result = WEB_FLEX
        elif css_value_equal(source, decl, "grid"): result = WEB_GRID
        elif css_value_equal(source, decl, "table"): result = WEB_TABLE
        elif css_value_equal(source, decl, "table-row"): result = WEB_TABLE_ROW
        elif css_value_equal(source, decl, "table-cell") or css_value_equal(source, decl, "table-row-group") or css_value_equal(source, decl, "table-header-group") or css_value_equal(source, decl, "table-footer-group"): result = WEB_BLOCK
    elif css_property_equal(source, decl, "margin") or css_property_equal(source, decl, "padding"):
        let margin: bool = css_property_equal(source, decl, "margin")
        value.field = WEB_PADDING_ALL
        if margin: value.field = WEB_MARGIN_ALL
        return web_edges(p, start, end, margin, value)
    elif css_property_equal(source, decl, "margin-top"): field = 3
    elif css_property_equal(source, decl, "margin-right"): field = 4
    elif css_property_equal(source, decl, "margin-bottom"): field = 5
    elif css_property_equal(source, decl, "margin-left"): field = 6
    elif css_property_equal(source, decl, "padding-top"): field = 7
    elif css_property_equal(source, decl, "padding-right"): field = 8
    elif css_property_equal(source, decl, "padding-bottom"): field = 9
    elif css_property_equal(source, decl, "padding-left"): field = 10
    elif css_property_equal(source, decl, "width"): field = 11
    elif css_property_equal(source, decl, "max-width"): field = 12
    elif css_property_equal(source, decl, "min-width"): field = 13
    elif css_property_equal(source, decl, "height"): field = 14
    elif css_property_equal(source, decl, "min-height"): field = 15
    elif css_property_equal(source, decl, "border"):
        value.field = WEB_BORDER_ALL
        return web_border(source, decl, value)
    elif css_property_equal(source, decl, "border-width"): field = 16
    elif css_property_equal(source, decl, "border-color"):
        field = 17
        if css_value_equal(source, decl, "currentcolor"): result = WEB_CURRENT_COLOR
        else: result = web_color(source, decl)
    elif css_property_equal(source, decl, "border-radius"): field = 18
    elif css_property_equal(source, decl, "font"):
        return web_font_shorthand(p, start, end, value)
    elif css_property_equal(source, decl, "font-size"):
        field = 19
        result = web_font_size(p, start, end)
    elif css_property_equal(source, decl, "font-family"):
        field = 20
        result = web_font_family(p, start, end)
    elif css_property_equal(source, decl, "font-weight"):
        field = 21
        result = web_font_weight(p, start, end)
    elif css_property_equal(source, decl, "font-style"):
        field = 22
        if css_value_equal(source, decl, "normal"): result = 0
        elif css_value_equal(source, decl, "italic"): result = 2
        elif css_value_equal(source, decl, "oblique"): result = 1
    elif css_property_equal(source, decl, "line-height"):
        field = 23
        result = web_line_height(p, start, end)
    elif css_property_equal(source, decl, "text-align"):
        field = 24
        if css_value_equal(source, decl, "left") or css_value_equal(source, decl, "start"): result = 0
        elif css_value_equal(source, decl, "center"): result = 1
        elif css_value_equal(source, decl, "right") or css_value_equal(source, decl, "end"): result = 2
    elif css_property_equal(source, decl, "text-decoration") or css_property_equal(source, decl, "text-decoration-line"):
        field = 25
        if css_value_equal(source, decl, "none"): result = 0
        elif css_value_equal(source, decl, "underline"): result = 1
    elif css_property_equal(source, decl, "box-sizing"):
        field = 26
        if css_value_equal(source, decl, "content-box"): result = 0
        elif css_value_equal(source, decl, "border-box"): result = 1
    elif css_property_equal(source, decl, "gap"):
        value.field = WEB_GAP_ALL
        let stop: i64 = web_component_end(p, start, end)
        value.values[0] = web_length(p, start, stop)
        value.values[1] = value.values[0]
        let next: i64 = css_trim_start(p, stop, end)
        if next < end: value.values[1] = web_length(p, next, end)
        return value.values[0] >= 0 and value.values[1] >= 0
    elif css_property_equal(source, decl, "column-gap"): field = 27
    elif css_property_equal(source, decl, "row-gap"): field = 32
    elif css_property_equal(source, decl, "flex-direction"):
        field = 28
        if css_value_equal(source, decl, "row"): result = 0
        elif css_value_equal(source, decl, "column"): result = 1
    elif css_property_equal(source, decl, "flex-wrap"):
        field = 29
        if css_value_equal(source, decl, "nowrap"): result = 0
        elif css_value_equal(source, decl, "wrap"): result = 1
    elif css_property_equal(source, decl, "grid-template-columns"):
        return web_grid_columns(p, start, end, value)
    elif css_property_equal(source, decl, "white-space"):
        field = 31
        if css_value_equal(source, decl, "normal"): result = 0
        elif css_value_equal(source, decl, "nowrap"): result = 1
        elif css_value_equal(source, decl, "pre"): result = 2
        elif css_value_equal(source, decl, "pre-wrap"): result = 3
        elif css_value_equal(source, decl, "pre-line"): result = 4
    elif css_property_equal(source, decl, "align-items"):
        field = 33
        result = web_box_align(source, decl, false)
    elif css_property_equal(source, decl, "align-self"):
        field = 34
        if css_value_equal(source, decl, "auto"): result = WEB_AUTO
        else: result = web_box_align(source, decl, false)
    elif css_property_equal(source, decl, "justify-content"):
        field = 35
        result = web_box_align(source, decl, true)
    elif css_property_equal(source, decl, "flex"): return web_flex(p, start, end, value)
    elif css_property_equal(source, decl, "flex-grow"):
        field = 36
        result = web_flex_factor(p, start, end)
    elif css_property_equal(source, decl, "flex-shrink"):
        field = 37
        result = web_flex_factor(p, start, end)
    elif css_property_equal(source, decl, "flex-basis"):
        field = 38
        result = web_flex_basis(p, start, end)
    elif css_property_equal(source, decl, "object-fit"):
        field = 57
        if css_value_equal(source, decl, "fill"): result = 0
        elif css_value_equal(source, decl, "contain"): result = 1
        elif css_value_equal(source, decl, "cover"): result = 2
        elif css_value_equal(source, decl, "none"): result = 3
        elif css_value_equal(source, decl, "scale-down"): result = 4
    elif css_property_equal(source, decl, "aspect-ratio"):
        field = 58
        result = web_aspect(p, start, end)
    if (field >= 3 and field <= 16) or field == 18 or field == 27 or field == 32: length = true
    if length:
        result = web_length(p, start, end)
        if (field <= 6 or field == 11 or field == 14) and css_value_equal(source, decl, "auto"): result = WEB_AUTO
        if field == 12 and css_value_equal(source, decl, "none"): result = WEB_AUTO
        if field == 11 and css_value_equal(source, decl, "fit-content"): result = WEB_FIT
    if field < 0 or result == -2: return false
    value.field = field
    value.values[0] = result
    return true

unsafe fn web_win(winners: ptr<WebWinner>, field: i64, rank: i64, value: i64):
    if rank >= winners[field].rank: winners[field] = WebWinner(rank, value)

unsafe fn web_win_series(winners: ptr<WebWinner>, value: ptr<WebValue>, rank: i64, first: i64, count: i64):
    let i: i64 = 0
    while i < count:
        web_win(winners, first + i, rank, value.values[i])
        i += 1

unsafe fn web_choose(winners: ptr<WebWinner>, value: ptr<WebValue>, rank: i64):
    if value.field == WEB_PADDING_ALL or value.field == WEB_MARGIN_ALL:
        let side: i64 = 0
        let start: i64 = 7
        if value.field == WEB_MARGIN_ALL: start = 3
        while side < 4:
            web_win(winners, start + side, rank, value.values[side])
            side += 1
    elif value.field == WEB_BORDER_ALL: web_win_series(winners, value, rank, 16, 2)
    elif value.field == WEB_FONT_ALL: web_win_series(winners, value, rank, 19, 5)
    elif value.field == WEB_GRADIENT_ALL or value.field == WEB_BACKGROUND_ALL:
        web_win_series(winners, value, rank, 39, 5)
        if value.field == WEB_BACKGROUND_ALL: web_win(winners, 1, rank, value.values[5])
    elif value.field == WEB_SHADOW_ALL: web_win_series(winners, value, rank, 44, 5)
    elif value.field == WEB_GRID_ALL:
        web_win(winners, 30, rank, value.values[0])
        let i: i64 = 0
        while i < 8:
            web_win(winners, 49 + i, rank, value.values[i + 1])
            i += 1
    elif value.field == WEB_GAP_ALL:
        web_win(winners, 32, rank, value.values[0])
        web_win(winners, 27, rank, value.values[1])
    elif value.field == WEB_FLEX_ALL: web_win_series(winners, value, rank, 36, 3)
    else: web_win(winners, value.field, rank, value.values[0])

unsafe fn web_inline_style(cascade: ptr<CssCascadeContext>, winners: ptr<WebWinner>, html_size: i64, viewport_units: ptr<bool>):
    let node: ptr<HtmlNode> = &cascade.nodes[cascade.node_index]
    let index: i64 = css_find_html_attribute(cascade.html_source, node, cascade.attributes, "style")
    if index < 0 or not cascade.attributes[index].has_value: return
    let bytes: [4097]char
    let attr: ptr<HtmlAttribute> = &cascade.attributes[index]
    let length: i64 = html_decode_range(cascade.html_source as ptr<char>, html_size, attr.value_start, attr.value_length, &bytes[0], 4097)
    if not viewport_units[0]: viewport_units[0] = web_has_viewport_units(&bytes[0], length)
    let source: string = (&bytes[0]) as string
    let i: i64 = 0
    while i < length:
        css_skip_space(&bytes[0], &i, length)
        if i == length: break
        let comment: i64 = css_skip_comment(&bytes[0], &i, length)
        if comment < 0: break
        if comment > 0: continue
        if bytes[i] == ';':
            i += 1
            continue
        let start: i64 = i
        let decl: CssDeclaration
        let result: i64 = css_read_declaration(&bytes[0], &i, length, &decl)
        if result < 0 or i <= start: break
        if result == 0:
            let value: WebValue
            if web_property(source, &decl, &value):
                let rank: i64 = 4294967296
                if decl.important: rank += WEB_IMPORTANT
                web_choose(winners, &value, rank)

unsafe fn web_inherited(style: ptr<BrowserStyle>, parent: ptr<BrowserStyle>):
    style.color = 0
    style.font = 16
    style.weight = 400
    style.line_height = WEB_AUTO
    if parent != (0 as ptr<BrowserStyle>):
        style.color = parent.color
        style.font = parent.font
        style.family = parent.family
        style.weight = parent.weight
        style.italic = parent.italic
        style.line_height = parent.line_height
        style.align = parent.align
        style.underline = parent.underline
        style.whitespace = parent.whitespace
    style.background = -1
    style.border_color = WEB_CURRENT_COLOR
    style.display = WEB_INLINE
    style.width = WEB_AUTO
    style.max_width = WEB_AUTO
    style.height = WEB_AUTO
    style.columns = 1
    style.tracks[0] = 100 * WEB_TRACK_SCALE
    style.align_self = WEB_AUTO
    style.shrink = 100
    style.basis = WEB_AUTO

unsafe fn web_apply(style: ptr<BrowserStyle>, winners: ptr<WebWinner>, width: i64, height: i64):
    let field: i64 = 0
    while field < WEB_FIELDS:
        let item: WebWinner = winners[field]
        if item.rank > 0:
            let v: i64 = item.value
            if (field >= 3 and field <= 16) or field == 18 or field == 19 or field == 23 or field == 27 or field == 32 or field == 38:
                v = web_viewport_pixels(v, width, height)
            if field == 0: style.color = v
            elif field == 1: style.background = v
            elif field == 2: style.display = v
            elif field <= 6: style.margin[field - 3] = v
            elif field <= 10: style.padding[field - 7] = v
            elif field == 11:
                style.width = v
                style.width_set = true
            elif field == 12: style.max_width = v
            elif field == 13: style.min_width = v
            elif field == 14:
                style.height = v
                style.height_set = true
            elif field == 15: style.min_height = v
            elif field == 16: style.border = v
            elif field == 17: style.border_color = v
            elif field == 18: style.radius = v
            elif field == 19: style.font = max(1, min(128, web_pixels(v, style.font, style.font)))
            elif field == 20: style.family = v
            elif field == 21: style.weight = v as i32
            elif field == 22: style.italic = v as i32
            elif field == 23:
                if v >= WEB_LINE_RATIO: style.line_height = v
                else: style.line_height = web_pixels(v, style.font, style.font)
            elif field == 24: style.align = v
            elif field == 25: style.underline = v == 1
            elif field == 26: style.border_box = v == 1
            elif field == 27: style.column_gap = v
            elif field == 28: style.flex_column = v == 1
            elif field == 29: style.flex_wrap = v == 1
            elif field == 30: style.columns = v
            elif field == 31: style.whitespace = v
            elif field == 32: style.row_gap = v
            elif field == 33: style.align_items = v
            elif field == 34: style.align_self = v
            elif field == 35: style.justify = v
            elif field == 36: style.grow = v
            elif field == 37: style.shrink = v
            elif field == 38: style.basis = v
            elif field <= 43: style.gradient[field - 39] = v
            elif field <= 48: style.shadow[field - 44] = v
            elif field <= 56: style.tracks[field - 49] = v / WEB_TRACK_SCALE * WEB_TRACK_SCALE + web_viewport_pixels(v % WEB_TRACK_SCALE, width, height)
            elif field == 57: style.object_fit = v
            elif field == 58: style.aspect = v
        field += 1

unsafe fn browser_visual_styles(sheet: ptr<BrowserStyleSheet>, layout: ptr<CssLayoutContext>, attributes: ptr<HtmlAttribute>, styles: ptr<BrowserStyle>, height: i64, transfer: ptr<HttpTransfer>) -> i64:
    let rules: ptr<CssRule> = buffer_data(&sheet.rules)
    let selectors: ptr<CssSelector> = buffer_data(&sheet.selectors)
    let declarations: ptr<CssDeclaration> = buffer_data(&sheet.declarations)
    let source: string = sheet.source.data as ptr<char> as string
    let html_size: i64 = __volt_strlen(layout.html_source)
    let values: Buffer<WebValue>
    let matches: Buffer<WebSelector>
    defer buffer_free(&values)
    defer buffer_free(&matches)
    if buffer_reserve(&values, sheet.counts.declaration_count) < 0 or buffer_reserve(&matches, sheet.counts.selector_count) < 0: return -12
    let parsed: ptr<WebValue> = buffer_data(&values)
    let i: i64 = 0
    while i < sheet.counts.declaration_count:
        if not web_property(source, &declarations[i], &parsed[i]): parsed[i].field = -1
        i += 1
    let preflight: ptr<WebSelector> = buffer_data(&matches)
    let bytes: ptr<char> = source as ptr<char>
    i = 0
    while i < sheet.counts.selector_count:
        let selector: ptr<CssSelector> = &selectors[i]
        let at: i64 = selector.start
        let stop: i64 = at + selector.length
        let simple: bool = css_compound_end(bytes, at, stop) == stop
        preflight[i] = WebSelector(css_specificity_range(bytes, selector.start, stop), simple)
        i += 1
    let cascade: CssCascadeContext = CssCascadeContext(source, rules, sheet.counts.rule_count, selectors, sheet.counts.selector_count, declarations, sheet.counts.declaration_count, layout.html_source, layout.nodes, attributes, layout.node_count, 0)
    i = 0
    while i < layout.node_count:
        if transfer != (0 as ptr<HttpTransfer>) and i % 64 == 0:
            let remaining: i64 = http_transfer_remaining(transfer)
            if remaining < 0: return remaining
        let style: BrowserStyle
        let parent: ptr<BrowserStyle> = 0 as ptr<BrowserStyle>
        if i > 0: parent = &styles[layout.nodes[i].parent]
        web_inherited(&style, parent)
        if layout.nodes[i].kind == HTML_ELEMENT:
            let winners: [59]WebWinner
            let r: i64 = 0
            while r < sheet.counts.rule_count:
                let rule: ptr<CssRule> = &rules[r]
                let index: i64 = r
                r += 1
                if layout.viewport_width < rule.min_width or layout.viewport_width > rule.max_width: continue
                let specificity: i64 = -1
                let s: i64 = rule.selector_start
                while s < rule.selector_start + rule.selector_count:
                    let selector: ptr<CssSelector> = &selectors[s]
                    let match_style: bool = false
                    if preflight[s].compound:
                        match_style = css_match_compound(source, selector.start, selector.length, layout.html_source, &layout.nodes[i], attributes)
                    else:
                        let match_context: CssMatchContext = CssMatchContext(source, selector, layout.html_source, layout.nodes, attributes, layout.node_count, i)
                        match_style = css_selector_matches_tree_range(&match_context, sheet.source.len)
                    if match_style: specificity = max(specificity, preflight[s].specificity)
                    s += 1
                if specificity >= 0:
                    let rank: i64 = specificity + 1
                    if index >= sheet.defaults: rank += 2147483648
                    let d: i64 = rule.declaration_start
                    while d < rule.declaration_start + rule.declaration_count:
                        if parsed[d].field >= 0:
                            let priority: i64 = rank
                            if declarations[d].important: priority += WEB_IMPORTANT
                            web_choose(&winners[0], &parsed[d], priority)
                        d += 1
            cascade.node_index = i
            if not sheet.block_inline: web_inline_style(&cascade, &winners[0], html_size, &sheet.viewport_units)
            web_apply(&style, &winners[0], layout.viewport_width, height)
            if html_name_equal(layout.html_source, &layout.nodes[i], "script") or html_name_equal(layout.html_source, &layout.nodes[i], "style") or html_name_equal(layout.html_source, &layout.nodes[i], "template"):
                style.display = 0
        styles[i] = style
        i += 1
    return 0

unsafe fn browser_media_changed(sheet: ptr<BrowserStyleSheet>, previous: i64, width: i64) -> bool:
    if width == previous: return false
    let rules: ptr<CssRule> = buffer_data(&sheet.rules)
    let i: i64 = 0
    while i < sheet.counts.rule_count:
        let rule: ptr<CssRule> = &rules[i]
        let before: bool = previous >= rule.min_width and previous <= rule.max_width
        let after: bool = width >= rule.min_width and width <= rule.max_width
        if (before and not after) or (after and not before): return true
        i += 1
    return false
