use css
use browser_graphics

const WEB_BAD_NUMBER: i64 = -10000001
const WEB_STOP_SCALE: i64 = 8589934592

# Hundredths keep color and angle parsing independent of locale and libc.
unsafe fn web_decimal(p: ptr<char>, at: ptr<i64>, end: i64) -> i64:
    let i: i64 = at[0]
    let negative: bool = i < end and p[i] == '-'
    if i < end and (p[i] == '+' or negative): i += 1
    let first: i64 = i
    let whole: i64 = 0
    while i < end and p[i] >= '0' and p[i] <= '9':
        whole = min(100000, whole * 10 + (p[i] as i64 - 48))
        i += 1
    let digits: i64 = i - first
    let value: i64 = whole * 100
    if i + 1 < end and p[i] == '.' and p[i + 1] >= '0' and p[i + 1] <= '9':
        i += 1
        let factor: i64 = 10
        while i < end and p[i] >= '0' and p[i] <= '9':
            value += (p[i] as i64 - 48) * factor
            factor /= 10
            digits += 1
            i += 1
    if digits == 0: return WEB_BAD_NUMBER
    at[0] = i
    if negative: return 0 - min(10000000, value)
    return min(10000000, value)

fn web_pack_color(rgb: i64, alpha: i64) -> i64:
    if alpha == 0: return -1
    if alpha == 255: return rgb
    return rgb | (alpha << 24)

fn web_alpha(color: i64) -> i64:
    if color < 0: return 0
    if color < 16777216: return 255
    return color >> 24

unsafe fn web_color_source(cr: ptr<char>, color: i64):
    cairo_set_source_rgba(cr, (((color >> 16) & 255) as f64) / 255.0, (((color >> 8) & 255) as f64) / 255.0, ((color & 255) as f64) / 255.0, (web_alpha(color) as f64) / 255.0)

unsafe fn web_color_part(p: ptr<char>, start: i64, end: i64) -> i64:
    let left: i64 = css_trim_start(p, start, end)
    let part: CssDeclaration = CssDeclaration(0, 0, 0, left, css_trim_end(p, left, end) - left, false)
    return web_color(p as string, &part)

unsafe fn web_color(source: string, decl: ptr<CssDeclaration>) -> i64:
    let p: ptr<char> = source as ptr<char>
    let start: i64 = decl.value_start
    let n: i64 = decl.value_length
    # shortcut: evaluate the light branch until the browser has a page color-scheme setting.
    if n > 13 and css_range_equal(source, start, 11, "light-dark(") and p[start + n - 1] == ')':
        let end: i64 = start + n - 1
        let comma: i64 = start + 11
        if css_find_delimiter(p, &comma, end, ',', ',') < 0 or comma == end: return -2
        let light: i64 = css_trim_start(p, start + 11, comma)
        let dark: i64 = css_trim_start(p, comma + 1, end)
        let first: CssDeclaration = CssDeclaration(0, 0, 0, light, css_trim_end(p, light, comma) - light, false)
        let second: CssDeclaration = CssDeclaration(0, 0, 0, dark, css_trim_end(p, dark, end) - dark, false)
        if web_simple_color(source, &second) == -2: return -2
        return web_simple_color(source, &first)
    return web_simple_color(source, decl)

unsafe fn web_hex_alpha(p: ptr<char>, start: i64, n: i64) -> i64:
    let packed: i64 = 0
    let i: i64 = 1
    while i < n:
        let high: i64 = css_hex_digit(p[start + i])
        if high < 0: return -2
        let byte: i64 = high * 17
        if n == 9:
            i += 1
            let low: i64 = css_hex_digit(p[start + i])
            if low < 0: return -2
            byte = high * 16 + low
        packed = packed * 256 + byte
        i += 1
    return web_pack_color(packed >> 8, packed & 255)

fn web_hsl_rgb(hue: i64, s: i64, l: i64) -> i64:
    let h: i64 = (hue % 36000 + 36000) % 36000
    let light: f64 = (l as f64) / 10000.0
    let chroma: f64 = (1.0 - abs(2.0 * light - 1.0)) * (s as f64) / 10000.0
    let x: f64 = chroma * (1.0 - abs(((h % 12000) as f64) / 6000.0 - 1.0))
    let m: f64 = light - chroma / 2.0
    let r: f64 = 0.0
    let g: f64 = 0.0
    let b: f64 = 0.0
    if h < 6000:
        r = chroma
        g = x
    elif h < 12000:
        r = x
        g = chroma
    elif h < 18000:
        g = chroma
        b = x
    elif h < 24000:
        g = x
        b = chroma
    elif h < 30000:
        r = x
        b = chroma
    else:
        r = chroma
        b = x
    return ((((r + m) * 255.0 + 0.5) as i64) << 16) | ((((g + m) * 255.0 + 0.5) as i64) << 8) | (((b + m) * 255.0 + 0.5) as i64)

unsafe fn web_function_color(p: ptr<char>, start: i64, end: i64, hsl: bool) -> i64:
    let i: i64 = start
    let components: [3]i64
    let component: i64 = 0
    let commas: bool = false
    let first_percent: bool = false
    while component < 3:
        i = css_trim_start(p, i, end)
        let number: i64 = web_decimal(p, &i, end)
        if number == WEB_BAD_NUMBER: return -2
        let percent: bool = i < end and p[i] == '%'
        if percent: i += 1
        if hsl:
            if component == 0 and not percent:
                if i + 3 <= end and css_range_equal(p as string, i, 3, "deg"): i += 3
                components[component] = number
            elif component > 0 and percent: components[component] = max(0, min(10000, number))
            else: return -2
        else:
            if component == 0: first_percent = percent
            elif commas and ((percent and not first_percent) or (first_percent and not percent)): return -2
            if percent: components[component] = (max(0, min(10000, number)) * 255 + 5000) / 10000
            else: components[component] = (max(0, min(25500, number)) + 50) / 100
        let gap: i64 = i
        i = css_trim_start(p, i, end)
        if component < 2:
            let comma: bool = i < end and p[i] == ','
            if component == 0: commas = comma
            if commas:
                if not comma: return -2
                i += 1
            elif comma or i == gap: return -2
        component += 1
    let alpha: i64 = 255
    if i < end:
        if (commas and p[i] != ',') or (not commas and p[i] != '/'): return -2
        i = css_trim_start(p, i + 1, end)
        let number: i64 = web_decimal(p, &i, end)
        if number == WEB_BAD_NUMBER: return -2
        let scale: i64 = 100
        if i < end and p[i] == '%':
            scale = 10000
            i += 1
        alpha = (max(0, min(scale, number)) * 255 + scale / 2) / scale
        if css_trim_start(p, i, end) != end: return -2
    if hsl: return web_pack_color(web_hsl_rgb(components[0], components[1], components[2]), alpha)
    return web_pack_color((components[0] << 16) | (components[1] << 8) | components[2], alpha)

unsafe fn web_simple_color(source: string, decl: ptr<CssDeclaration>) -> i64:
    if css_value_equal(source, decl, "transparent"): return -1
    let basic: i64 = css_color_value(source, decl)
    if basic >= 0: return basic
    if css_value_equal(source, decl, "gray") or css_value_equal(source, decl, "grey"): return 0x808080
    if css_value_equal(source, decl, "purple"): return 0x800080
    if css_value_equal(source, decl, "maroon"): return 0x800000
    if css_value_equal(source, decl, "lime"): return 0x00ff00
    if css_value_equal(source, decl, "rebeccapurple"): return 0x663399
    let p: ptr<char> = source as ptr<char>
    let start: i64 = decl.value_start
    let n: i64 = decl.value_length
    if n < 1 or n > 80: return -2
    if p[start] == '#':
        if n == 5 or n == 9: return web_hex_alpha(p, start, n)
        return -2
    if n > 5 and p[start + n - 1] == ')':
        if css_range_equal(source, start, 4, "rgb("): return web_function_color(p, start + 4, start + n - 1, false)
        if css_range_equal(source, start, 5, "rgba("): return web_function_color(p, start + 5, start + n - 1, false)
        if css_range_equal(source, start, 4, "hsl("): return web_function_color(p, start + 4, start + n - 1, true)
        if css_range_equal(source, start, 5, "hsla("): return web_function_color(p, start + 5, start + n - 1, true)
        return -2
    let name: [81]char
    let i: i64 = 0
    while i < n:
        let c: char = p[start + i]
        if not ((c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z')): return -2
        name[i] = c
        i += 1
    let rgb: [3]u16
    if pango_color_parse(&rgb[0], &name[0]) == 0: return -2
    return ((rgb[0] as i64 / 257) << 16) | ((rgb[1] as i64 / 257) << 8) | (rgb[2] as i64 / 257)

unsafe fn web_component_end(p: ptr<char>, i: i64, end: i64) -> i64:
    let depth: i64 = 0
    while i < end:
        if depth == 0 and css_space(p[i]): break
        if p[i] == '(': depth += 1
        elif p[i] == ')' and depth > 0: depth -= 1
        i += 1
    return i

unsafe fn web_gradient_direction(p: ptr<char>, start: i64, end: i64) -> i64:
    let source: string = p as string
    let n: i64 = end - start
    if css_range_equal(source, start, n, "to top"): return 1
    if css_range_equal(source, start, n, "to right"): return 9001
    if css_range_equal(source, start, n, "to bottom"): return 18001
    if css_range_equal(source, start, n, "to left"): return 27001
    if css_range_equal(source, start, n, "to top right") or css_range_equal(source, start, n, "to right top"): return -1
    if css_range_equal(source, start, n, "to bottom right") or css_range_equal(source, start, n, "to right bottom"): return -2
    if css_range_equal(source, start, n, "to bottom left") or css_range_equal(source, start, n, "to left bottom"): return -3
    if css_range_equal(source, start, n, "to top left") or css_range_equal(source, start, n, "to left top"): return -4
    let i: i64 = start
    let number: i64 = web_decimal(p, &i, end)
    if number == WEB_BAD_NUMBER: return 0
    if number == 0 and i == end: return 1
    if not css_range_equal(source, i, end - i, "deg"): return 0
    return (number % 36000 + 36000) % 36000 + 1

unsafe fn web_gradient(p: ptr<char>, start: i64, end: i64, values: ptr<i64>) -> bool:
    if end - start < 20 or p[end - 1] != ')' or not css_range_equal(p as string, start, 16, "linear-gradient("): return false
    end -= 1
    let i: i64 = css_trim_start(p, start + 16, end)
    let comma: i64 = i
    if css_find_delimiter(p, &comma, end, ',', ',') < 0 or comma == end: return false
    let direction: i64 = web_gradient_direction(p, i, css_trim_end(p, i, comma))
    if direction != 0: i = css_trim_start(p, comma + 1, end)
    else: direction = 18001
    let offsets: [4]i64
    let colors: [4]i64
    let count: i64 = 0
    while i < end:
        if count == 4: return false
        comma = i
        if css_find_delimiter(p, &comma, end, ',', ',') < 0: return false
        let limit: i64 = css_trim_end(p, i, comma)
        let color_end: i64 = web_component_end(p, i, limit)
        let color: i64 = web_color_part(p, i, color_end)
        if color == -2: return false
        colors[count] = color
        offsets[count] = -1
        i = css_trim_start(p, color_end, limit)
        if i < limit:
            let number: i64 = web_decimal(p, &i, limit)
            if number < 0 or number > 10000 or i != limit - 1 or p[i] != '%': return false
            offsets[count] = number
        count += 1
        i = css_trim_start(p, comma + 1, end)
        if comma < end and i >= end: return false
    if count < 2: return false
    if offsets[0] < 0: offsets[0] = 0
    if offsets[count - 1] < 0: offsets[count - 1] = 10000
    let first: i64 = 0
    i = 1
    while i < count:
        if offsets[i] >= 0:
            offsets[i] = max(offsets[first], offsets[i])
            let j: i64 = first + 1
            while j < i:
                offsets[j] = offsets[first] + (offsets[i] - offsets[first]) * (j - first) / (i - first)
                j += 1
            first = i
        i += 1
    values[0] = direction
    i = 0
    while i < 4:
        values[i + 1] = 0
        if i < count:
            let color: i64 = colors[i]
            if color < 0: color = 4294967296
            values[i + 1] = (offsets[i] + 1) * WEB_STOP_SCALE + color
        i += 1
    return true
