use browser_graphics
use browser_engine
use browser_shadows
use utf8

unsafe fn browser_draw_text_run(cr: ptr<char>, layout: ptr<char>, text: ptr<char>, length: i64, fragment: ptr<CssFlowFragment>, view: BrowserRect):
    let x: i64 = fragment.x
    let y: i64 = fragment.y - view.y
    let clip_y: i64 = fragment.clip_y - view.y
    let right: i64 = min(view.w, fragment.clip_x + fragment.clip_width)
    if x >= right or y >= view.h or y + 16 <= 0: return
    let top: i64 = max(0, max(y, clip_y))
    let bottom: i64 = min(view.h, min(y + 16, clip_y + fragment.clip_height))
    if top >= bottom: return
    let count: i64 = 0
    let bytes: i64 = 0
    while bytes < length and count * 6 < right - x:
        utf8_next(text, &bytes, length)
        count += 1
    if count == 0: return
    pango_layout_set_text(layout, text, bytes as i32)
    let measured: i32 = 0
    pango_layout_get_size(layout, &measured, 0 as ptr<i32>)
    if measured <= 0: return
    # Match the VOLT layout's six units per character, including font fallback.
    let advance: i64 = count * 6
    cairo_save(cr)
    cairo_rectangle(cr, x as f64, top as f64, min(right - x, advance) as f64, (bottom - top) as f64)
    cairo_clip(cr)
    chrome_color(cr, fragment.color_rgb)
    cairo_translate(cr, x as f64, (y + 1) as f64)
    cairo_scale(cr, ((advance * PANGO_SCALE) as f64) / (measured as f64), 1.0)
    cairo_move_to(cr, 0.0, 0.0)
    pango_cairo_show_layout(cr, layout)
    cairo_restore(cr)

unsafe fn browser_render_document(canvas: ptr<BrowserCanvas>, page: ptr<BrowserPage>, pane: BrowserRect, zoom: i64, offset: i64) -> i64:
    if canvas.document_surface == (0 as ptr<char>):
        canvas.document_surface = cairo_image_surface_create(CAIRO_ARGB32, pane.w as i32, pane.h as i32)
    return browser_draw_document(canvas.document_surface, page, BrowserRect(0, offset, pane.w / zoom, pane.h / zoom), zoom)

unsafe fn browser_draw_document(surface: ptr<char>, page: ptr<BrowserPage>, view: BrowserRect, zoom: i64) -> i64:
    if cairo_surface_status(surface) != 0: return -12
    let cr: ptr<char> = cairo_create(surface)
    defer cairo_destroy(cr)
    if cairo_status(cr) != 0: return -12
    chrome_color(cr, BROWSER_CANVAS_COLOR)
    cairo_paint(cr)
    cairo_scale(cr, zoom as f64, zoom as f64)
    cairo_rectangle(cr, 0.0, 0.0, view.w as f64, view.h as f64)
    cairo_clip(cr)
    let canvas_node: i64 = -1
    if page.visual:
        let styles: ptr<BrowserStyle> = buffer_data(&page.storage.visual.styles)
        canvas_node = browser_canvas_background(page, styles)
        if canvas_node > 0:
            let box: ptr<CssLayoutBox> = &page.boxes[canvas_node]
            let rect: BrowserRect = BrowserRect(box.x, box.y - view.y, max(1, box.width), max(1, box.height))
            browser_background(cr, &styles[canvas_node], rect)
    let layout: ptr<char> = pango_cairo_create_layout(cr)
    if layout == (0 as ptr<char>): return -12
    defer g_object_unref(layout)
    let font: ptr<char> = pango_font_description_new()
    if font == (0 as ptr<char>): return -12
    defer pango_font_description_free(font)
    pango_layout_set_single_paragraph_mode(layout, 1)
    if page.visual:
        pango_context_set_round_glyph_positions(pango_layout_get_context(layout), 0)
        let metrics: WebMetrics = WebMetrics(layout, font, 0, 0, 0 as i32, 0 as i32)
        browser_draw_visual(cr, &metrics, page, view, canvas_node)
        if cairo_status(cr) != 0: return -22
        return 0
    pango_font_description_set_family(font, "Noto Sans Mono, DejaVu Sans Mono, Monospace" as ptr<char>)
    pango_font_description_set_absolute_size(font, 10.5 * (PANGO_SCALE as f64))
    pango_layout_set_font_description(layout, font)

    # Preserve the VOLT painter's background/text order when boxes overlap.
    let node: i64 = 1
    let at: i64 = 0
    while node < page.node_count:
        let box: ptr<CssLayoutBox> = &page.boxes[node]
        let background: i64 = page.styles[node].background_rgb
        if not box.hidden and page.nodes[node].kind == HTML_ELEMENT and background >= 0:
            let top: i64 = max(0, box.y - view.y)
            let bottom: i64 = min(view.h, box.y - view.y + box.height)
            if top < bottom: chrome_box(cr, BrowserRect(box.x, top, box.width, bottom - top), 0, background, -1)
        while at < page.fragment_count and page.fragments[at].node_index == node:
            let first: ptr<CssFlowFragment> = &page.fragments[at]
            let last: ptr<CssFlowFragment> = first
            at += 1
            # Adjacent words on a text node's line share a color and clip box.
            while at < page.fragment_count and page.fragments[at].node_index == node and page.fragments[at].y == first.y:
                last = &page.fragments[at]
                at += 1
            if not box.hidden:
                let length: i64 = last.byte_start + last.byte_length - first.byte_start
                browser_draw_text_run(cr, layout, page.flow_text + first.byte_start, length, first, view)
        node += 1
    if cairo_status(cr) != 0: return -22
    return 0

unsafe fn browser_canvas_background(page: ptr<BrowserPage>, styles: ptr<BrowserStyle>) -> i64:
    let node: i64 = page.nodes[0].first_child
    while node > 0:
        let html: bool = html_name_equal(page.source, &page.nodes[node], "html")
        if html or html_name_equal(page.source, &page.nodes[node], "body"):
            if not page.boxes[node].hidden and (styles[node].background >= 0 or styles[node].gradient[0] != 0): return node
            if html:
                node = page.nodes[node].first_child
                continue
        node = page.nodes[node].next_sibling
    return -1

unsafe fn browser_background(cr: ptr<char>, style: ptr<BrowserStyle>, rect: BrowserRect):
    if style.background >= 0:
        web_color_source(cr, style.background)
        cairo_paint(cr)
    let direction: i64 = style.gradient[0]
    if direction == 0: return
    let w: f64 = rect.w as f64
    let h: f64 = rect.h as f64
    let dx: f64 = 0.0
    let dy: f64 = 0.0
    if direction > 0:
        let angle: f64 = ((direction - 1) as f64) * 0.000174532925199433
        dx = sin(angle)
        dy = 0.0 - cos(angle)
    else:
        let length: f64 = sqrt(w * w + h * h)
        dx = h / length
        dy = w / length
        if direction == -3 or direction == -4: dx = 0.0 - dx
        if direction == -1 or direction == -4: dy = 0.0 - dy
    let span: f64 = (abs(dx) * w + abs(dy) * h) / 2.0
    let x: f64 = (rect.x as f64) + w / 2.0
    let y: f64 = (rect.y as f64) + h / 2.0
    let pattern: ptr<char> = cairo_pattern_create_linear(x - dx * span, y - dy * span, x + dx * span, y + dy * span)
    defer cairo_pattern_destroy(pattern)
    let i: i64 = 1
    while i <= 4 and style.gradient[i] != 0:
        let stop: i64 = style.gradient[i]
        let color: i64 = stop % WEB_STOP_SCALE
        if color == 4294967296: color = -1
        cairo_pattern_add_color_stop_rgba(pattern, ((stop / WEB_STOP_SCALE - 1) as f64) / 10000.0, (((color >> 16) & 255) as f64) / 255.0, (((color >> 8) & 255) as f64) / 255.0, ((color & 255) as f64) / 255.0, (web_alpha(color) as f64) / 255.0)
        i += 1
    cairo_set_source(cr, pattern)
    cairo_paint(cr)

unsafe fn browser_draw_visual_box(cr: ptr<char>, style: ptr<BrowserStyle>, box: ptr<CssLayoutBox>, view: BrowserRect, skip_background: bool, shadow_budget: ptr<i64>):
    let rect: BrowserRect = BrowserRect(box.x, box.y - view.y, box.width, box.height)
    if rect.w <= 0 or rect.h <= 0: return
    let border: i64 = min(32, web_pixels(style.border, box.width, style.font))
    let radius: i64 = web_pixels(style.radius, box.width, style.font)
    browser_shadow(cr, style, rect, radius, view, shadow_budget)
    if rect.y >= view.h or rect.y + rect.h <= 0 or rect.x >= view.w or rect.x + rect.w <= 0: return
    if not skip_background and (style.background >= 0 or style.gradient[0] != 0):
        cairo_save(cr)
        browser_box_path(cr, rect, radius)
        cairo_clip(cr)
        browser_background(cr, style, rect)
        cairo_restore(cr)
    if border > 0 and style.border_color != -1:
        let ink: i64 = style.border_color
        if ink == WEB_CURRENT_COLOR: ink = style.color
        if ink < 0: return
        cairo_save(cr)
        cairo_set_fill_rule(cr, CAIRO_FILL_EVEN_ODD)
        browser_box_path(cr, rect, radius)
        let inside: BrowserRect = BrowserRect(rect.x + border, rect.y + border, rect.w - border * 2, rect.h - border * 2)
        if inside.w > 0 and inside.h > 0: browser_box_path(cr, inside, max(0, radius - border))
        web_color_source(cr, ink)
        cairo_fill(cr)
        cairo_restore(cr)

unsafe fn browser_draw_replaced(cr: ptr<char>, frame: BrowserVideoFrame, rect: BrowserRect, border: BrowserRect, style: ptr<BrowserStyle>, fit: i64):
    cairo_save(cr)
    defer cairo_restore(cr)
    cairo_rectangle(cr, rect.x as f64, rect.y as f64, rect.w as f64, rect.h as f64)
    cairo_clip(cr)
    let radius: i64 = web_pixels(style.radius, border.w, style.font)
    if radius > 0:
        browser_box_path(cr, border, radius)
        cairo_clip(cr)
    let width: f64 = rect.w as f64
    let height: f64 = rect.h as f64
    let sx: f64 = width / (frame.width as f64)
    let sy: f64 = height / (frame.height as f64)
    if fit != 0:
        let scale: f64 = min(sx, sy)
        if fit == 2: scale = max(sx, sy)
        elif fit == 3: scale = 1.0
        elif fit == 4: scale = min(1.0, scale)
        sx = scale
        sy = scale
    cairo_translate(cr, (rect.x as f64) + (width - (frame.width as f64) * sx) / 2.0, (rect.y as f64) + (height - (frame.height as f64) * sy) / 2.0)
    cairo_scale(cr, sx, sy)
    cairo_set_source_surface(cr, frame.surface, 0.0, 0.0)
    cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD)
    cairo_rectangle(cr, 0.0, 0.0, frame.width as f64, frame.height as f64)
    cairo_fill(cr)

unsafe fn browser_draw_video(cr: ptr<char>, metrics: ptr<WebMetrics>, page: ptr<BrowserPage>, run: ptr<CssFlowFragment>, style: ptr<BrowserStyle>, view: BrowserRect):
    let node: i64 = run.node_index
    let box: ptr<CssLayoutBox> = &page.boxes[node]
    let rect: BrowserRect = BrowserRect(box.x, box.y - view.y, box.width, box.height)
    let media: BrowserRect = BrowserRect(run.x, run.y - view.y, run.advance, run.line_height)
    if media.w <= 0 or media.h <= 0: return
    let video: ptr<BrowserVideo> = &page.storage.visual.video
    let phase: i64 = 0
    if video.node == node: phase = video.phase
    if phase > 0 and video.image.surface != (0 as ptr<char>):
        browser_draw_replaced(cr, video.image, media, rect, style, style.object_fit)
    else:
        let poster: ptr<BrowserImage> = browser_image_at(&page.storage.visual.images, node)
        if poster != (0 as ptr<BrowserImage>):
            browser_draw_replaced(cr, BrowserVideoFrame(poster.surface, poster.width, poster.height), media, rect, style, style.object_fit)
    if media.w < 34 or media.h < 28: return
    let label: string = "Смотреть видео"
    if phase == BROWSER_VIDEO_LOADING: label = "Загрузка…"
    elif phase == BROWSER_VIDEO_PLAYING: label = "Пауза"
    elif phase == BROWSER_VIDEO_PAUSED: label = "Продолжить"
    elif phase == BROWSER_VIDEO_ENDED: label = "Смотреть снова"
    elif phase == BROWSER_VIDEO_FAILED:
        label = "Видео недоступно"
        if video.message != "": label = video.message
    let badge: BrowserRect = BrowserRect(media.x + 8, media.y + media.h - 34, min(media.w - 16, 164), 26)
    if phase == 0 or phase == BROWSER_VIDEO_LOADING or phase == BROWSER_VIDEO_FAILED:
        badge = BrowserRect(media.x + (media.w - badge.w) / 2, media.y + (media.h - badge.h) / 2, badge.w, badge.h)
    cairo_save(cr)
    defer cairo_restore(cr)
    browser_box_path(cr, rect, web_pixels(style.radius, rect.w, style.font))
    cairo_clip(cr)
    if (phase == BROWSER_VIDEO_PLAYING or phase == BROWSER_VIDEO_PAUSED or phase == BROWSER_VIDEO_ENDED) and video.duration_ms > 0 and media.w > 64 and media.h >= 44:
        let track: BrowserRect = BrowserRect(media.x + 8, media.y + media.h - 6, media.w - 16, 3)
        browser_box_path(cr, track, 1)
        cairo_set_source_rgba(cr, 1.0, 1.0, 1.0, 0.42)
        cairo_fill(cr)
        track.w = min(video.position_ms, video.duration_ms) * track.w / video.duration_ms
        if track.w > 0:
            browser_box_path(cr, track, 1)
            chrome_color(cr, 0x79edd3)
            cairo_fill(cr)
    browser_box_path(cr, badge, 13)
    cairo_set_source_rgba(cr, 0.025, 0.043, 0.09, 0.84)
    cairo_fill(cr)
    let label_style: BrowserStyle
    label_style.font = 13
    label_style.family = 3
    label_style.weight = 600
    web_set_font(metrics, &label_style)
    pango_layout_set_text(metrics.layout, label as ptr<char>, -1)
    let width: i32 = 0
    let height: i32 = 0
    pango_layout_get_size(metrics.layout, &width, &height)
    let text_width: i64 = (width as i64) / PANGO_SCALE
    let text_height: i64 = (height as i64) / PANGO_SCALE
    cairo_rectangle(cr, badge.x as f64, badge.y as f64, badge.w as f64, badge.h as f64)
    cairo_clip(cr)
    chrome_color(cr, 0xffffff)
    cairo_move_to(cr, (badge.x + max(4, (badge.w - text_width) / 2)) as f64, (badge.y + (badge.h - text_height) / 2) as f64)
    pango_cairo_show_layout(cr, metrics.layout)

unsafe fn browser_draw_visual_run(cr: ptr<char>, metrics: ptr<WebMetrics>, page: ptr<BrowserPage>, run: ptr<CssFlowFragment>, style: ptr<BrowserStyle>, view: BrowserRect):
    let top: i64 = run.y - view.y
    let right: i64 = min(view.w, run.clip_x + run.clip_width)
    if top >= view.h or top + run.line_height <= 0 or run.x >= right: return
    if run.byte_length == 0:
        if html_name_equal(page.source, &page.nodes[run.node_index], "video"):
            browser_draw_video(cr, metrics, page, run, style, view)
            return
        let image: ptr<BrowserImage> = browser_image_at(&page.storage.visual.images, run.node_index)
        if image == (0 as ptr<BrowserImage>): return
        if run.advance <= 0: return
        cairo_save(cr)
        cairo_rectangle(cr, run.x as f64, top as f64, min(run.advance, right - run.x) as f64, run.line_height as f64)
        cairo_clip(cr)
        let box: ptr<CssLayoutBox> = &page.boxes[run.node_index]
        browser_draw_replaced(cr, BrowserVideoFrame(image.surface, image.width, image.height), BrowserRect(run.x, top, run.advance, run.line_height), BrowserRect(box.x, box.y - view.y, box.width, box.height), style, style.object_fit)
        cairo_restore(cr)
        return
    web_set_font(metrics, style)
    pango_layout_set_text(metrics.layout, page.flow_text + run.byte_start, run.byte_length as i32)
    let ascent: f64 = (pango_layout_get_baseline(metrics.layout) as f64) / (PANGO_SCALE as f64)
    let baseline: i64 = top + run.baseline
    let clipped: bool = run.x + run.advance > right
    if clipped:
        cairo_save(cr)
        cairo_rectangle(cr, run.x as f64, 0.0, (right - run.x) as f64, view.h as f64)
        cairo_clip(cr)
    web_color_source(cr, run.color_rgb)
    cairo_move_to(cr, run.x as f64, (baseline as f64) - ascent)
    pango_cairo_show_layout(cr, metrics.layout)
    if style.underline and run.advance > 0:
        cairo_rectangle(cr, run.x as f64, (baseline + 1) as f64, run.advance as f64, max(1, style.font / 18) as f64)
        cairo_fill(cr)
    if clipped: cairo_restore(cr)

unsafe fn browser_draw_visual(cr: ptr<char>, metrics: ptr<WebMetrics>, page: ptr<BrowserPage>, view: BrowserRect, canvas_node: i64):
    let styles: ptr<BrowserStyle> = buffer_data(&page.storage.visual.styles)
    let node: i64 = 1
    let at: i64 = 0
    let shadow_budget: i64 = 524288
    while node < page.node_count:
        let box: ptr<CssLayoutBox> = &page.boxes[node]
        if not box.hidden and page.nodes[node].kind == HTML_ELEMENT:
            browser_draw_visual_box(cr, &styles[node], box, view, node == canvas_node, &shadow_budget)
        while at < page.fragment_count and page.fragments[at].node_index == node:
            if not box.hidden: browser_draw_visual_run(cr, metrics, page, &page.fragments[at], &styles[node], view)
            at += 1
        node += 1
