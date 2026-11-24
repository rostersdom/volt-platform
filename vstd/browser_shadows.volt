use browser_styles

unsafe fn browser_box_path(cr: ptr<char>, rect: BrowserRect, radius: i64):
    if radius > 0: chrome_round(cr, rect, radius)
    else: cairo_rectangle(cr, rect.x as f64, rect.y as f64, rect.w as f64, rect.h as f64)

struct WebBlurGrid:
    line: i64
    across: i64
    pixels: i64
    lines: i64
    radius: i64

# Sliding sums keep the work proportional to the mask, not to its blur radius.
unsafe fn browser_shadow_blur(input: ptr<u8>, output: ptr<u8>, grid: WebBlurGrid):
    let line: i64 = 0
    let width: i64 = grid.radius * 2 + 1
    while line < grid.lines:
        let first: i64 = line * grid.line
        let sum: i64 = 0
        let pixel: i64 = 0
        while pixel < min(grid.radius, grid.pixels):
            sum += input[first + pixel * grid.across] as i64
            pixel += 1
        pixel = 0
        while pixel < grid.pixels:
            if pixel + grid.radius < grid.pixels: sum += input[first + (pixel + grid.radius) * grid.across] as i64
            output[first + pixel * grid.across] = ((sum + width / 2) / width) as u8
            if pixel >= grid.radius: sum -= input[first + (pixel - grid.radius) * grid.across] as i64
            pixel += 1
        line += 1

unsafe fn browser_shadow_mask(cr: ptr<char>, base: BrowserRect, radius: i64, blur: i64, view: BrowserRect, budget: ptr<i64>):
    let extent: i64 = blur * 3 / 2 + 12
    let left: i64 = max(0 - extent, base.x - extent)
    let top: i64 = max(0 - extent, base.y - extent)
    let right: i64 = min(view.w + extent, base.x + base.w + extent)
    let bottom: i64 = min(view.h + extent, base.y + base.h + extent)
    let factor: i64 = max(1, blur / 8)
    let w: i64 = (right - left + factor - 1) / factor
    let h: i64 = (bottom - top + factor - 1) / factor
    while w * h > 98304:
        factor *= 2
        w = (right - left + factor - 1) / factor
        h = (bottom - top + factor - 1) / factor
    # shortcut: skip excessive shadow masks until the painter has a persistent image cache.
    if w <= 0 or h <= 0 or w * h > budget[0]: return
    budget[0] -= w * h
    let surface: ptr<char> = cairo_image_surface_create(CAIRO_A8, w as i32, h as i32)
    defer cairo_surface_destroy(surface)
    if cairo_surface_status(surface) != 0: return
    let mask: ptr<char> = cairo_create(surface)
    defer cairo_destroy(mask)
    if cairo_status(mask) != 0: return
    cairo_scale(mask, 1.0 / (factor as f64), 1.0 / (factor as f64))
    cairo_translate(mask, (0 - left) as f64, (0 - top) as f64)
    cairo_set_source_rgba(mask, 1.0, 1.0, 1.0, 1.0)
    browser_box_path(mask, base, radius)
    cairo_fill(mask)
    cairo_surface_flush(surface)
    let data: ptr<u8> = cairo_image_surface_get_data(surface) as ptr<u8>
    let stride: i64 = cairo_image_surface_get_stride(surface) as i64
    let temp: ByteBuffer
    defer bytes_free(&temp)
    if bytes_reserve(&temp, stride * h) < 0: return
    let steps: i64 = max(1, (blur + factor) / (2 * factor))
    let pass: i64 = 0
    while pass < 3:
        browser_shadow_blur(data, temp.data, WebBlurGrid(stride, 1, w, h, steps))
        browser_shadow_blur(temp.data, data, WebBlurGrid(1, stride, h, w, steps))
        pass += 1
    cairo_surface_mark_dirty(surface)
    cairo_save(cr)
    cairo_translate(cr, left as f64, top as f64)
    cairo_scale(cr, factor as f64, factor as f64)
    cairo_mask_surface(cr, surface, 0.0, 0.0)
    cairo_restore(cr)

unsafe fn browser_shadow(cr: ptr<char>, style: ptr<BrowserStyle>, rect: BrowserRect, radius: i64, view: BrowserRect, budget: ptr<i64>):
    if style.shadow[0] == 0: return
    let color: i64 = style.shadow[0] - 1
    if style.shadow[0] == -1: color = style.color
    if web_alpha(color) == 0: return
    let spread: i64 = style.shadow[4]
    let base: BrowserRect = BrowserRect(rect.x + style.shadow[1] - spread, rect.y + style.shadow[2] - spread, rect.w + spread * 2, rect.h + spread * 2)
    let blur: i64 = style.shadow[3]
    let extent: i64 = blur * 3 / 2 + 12
    if base.w <= 0 or base.h <= 0 or base.y - extent >= view.h or base.y + base.h + extent <= 0 or base.x - extent >= view.w or base.x + base.w + extent <= 0: return
    cairo_save(cr)
    defer cairo_restore(cr)
    # Outer shadows never show through the element itself.
    cairo_set_fill_rule(cr, CAIRO_FILL_EVEN_ODD)
    cairo_rectangle(cr, 0.0, 0.0, view.w as f64, view.h as f64)
    browser_box_path(cr, rect, radius)
    cairo_clip(cr)
    web_color_source(cr, color)
    if blur == 0:
        browser_box_path(cr, base, max(0, radius + spread))
        cairo_fill(cr)
    else: browser_shadow_mask(cr, base, max(0, radius + spread), blur, view, budget)
