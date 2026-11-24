# Cairo and Pango draw the window from the VOLT document layout.
use sdl

link "-lcairo -lpangocairo-1.0 -lpango-1.0 -lgobject-2.0"

unsafe extern fn cairo_image_surface_create(format: i32, width: i32, height: i32) -> ptr<char>
unsafe extern fn cairo_image_surface_create_for_data(data: ptr<char>, format: i32, width: i32, height: i32, stride: i32) -> ptr<char>
unsafe extern fn cairo_image_surface_get_data(surface: ptr<char>) -> ptr<char>
unsafe extern fn cairo_image_surface_get_stride(surface: ptr<char>) -> i32
unsafe extern fn cairo_surface_status(surface: ptr<char>) -> i32
unsafe extern fn cairo_surface_flush(surface: ptr<char>)
unsafe extern fn cairo_surface_destroy(surface: ptr<char>)
unsafe extern fn cairo_surface_mark_dirty(surface: ptr<char>)
unsafe extern fn cairo_surface_write_to_png(surface: ptr<char>, filename: ptr<char>) -> i32
unsafe extern fn cairo_create(surface: ptr<char>) -> ptr<char>
unsafe extern fn cairo_status(context: ptr<char>) -> i32
unsafe extern fn cairo_destroy(context: ptr<char>)
unsafe extern fn cairo_save(context: ptr<char>)
unsafe extern fn cairo_restore(context: ptr<char>)
unsafe extern fn cairo_set_source_rgb(context: ptr<char>, r: f64, g: f64, b: f64)
unsafe extern fn cairo_set_source_rgba(context: ptr<char>, r: f64, g: f64, b: f64, alpha: f64)
unsafe extern fn cairo_set_source_surface(context: ptr<char>, surface: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_get_source(context: ptr<char>) -> ptr<char>
unsafe extern fn cairo_pattern_create_linear(x0: f64, y0: f64, x1: f64, y1: f64) -> ptr<char>
unsafe extern fn cairo_pattern_add_color_stop_rgb(pattern: ptr<char>, offset: f64, r: f64, g: f64, b: f64)
unsafe extern fn cairo_pattern_add_color_stop_rgba(pattern: ptr<char>, offset: f64, r: f64, g: f64, b: f64, alpha: f64)
unsafe extern fn cairo_pattern_destroy(pattern: ptr<char>)
unsafe extern fn cairo_pattern_set_extend(pattern: ptr<char>, extend: i32)
unsafe extern fn cairo_set_source(context: ptr<char>, pattern: ptr<char>)
unsafe extern fn cairo_paint(context: ptr<char>)
unsafe extern fn cairo_mask_surface(context: ptr<char>, surface: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_move_to(context: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_line_to(context: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_arc(context: ptr<char>, x: f64, y: f64, radius: f64, a: f64, b: f64)
unsafe extern fn cairo_new_sub_path(context: ptr<char>)
unsafe extern fn cairo_close_path(context: ptr<char>)
unsafe extern fn cairo_rectangle(context: ptr<char>, x: f64, y: f64, width: f64, height: f64)
unsafe extern fn cairo_translate(context: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_scale(context: ptr<char>, x: f64, y: f64)
unsafe extern fn cairo_clip(context: ptr<char>)
unsafe extern fn cairo_set_fill_rule(context: ptr<char>, rule: i32)
unsafe extern fn cairo_fill(context: ptr<char>)
unsafe extern fn cairo_fill_preserve(context: ptr<char>)
unsafe extern fn cairo_stroke(context: ptr<char>)
unsafe extern fn cairo_set_line_width(context: ptr<char>, width: f64)
unsafe extern fn cairo_set_line_cap(context: ptr<char>, cap: i32)
unsafe extern fn cairo_set_line_join(context: ptr<char>, join: i32)
unsafe extern fn pango_cairo_create_layout(context: ptr<char>) -> ptr<char>
unsafe extern fn pango_cairo_show_layout(context: ptr<char>, layout: ptr<char>)
unsafe extern fn pango_cairo_font_map_new() -> ptr<char>
unsafe extern fn pango_font_map_create_context(map: ptr<char>) -> ptr<char>
unsafe extern fn pango_context_set_round_glyph_positions(context: ptr<char>, enabled: i32)
unsafe extern fn pango_layout_new(context: ptr<char>) -> ptr<char>
unsafe extern fn pango_layout_get_context(layout: ptr<char>) -> ptr<char>
unsafe extern fn pango_font_description_new() -> ptr<char>
unsafe extern fn pango_font_description_free(font: ptr<char>)
unsafe extern fn pango_font_description_set_family(font: ptr<char>, family: ptr<char>)
unsafe extern fn pango_font_description_set_weight(font: ptr<char>, weight: i32)
unsafe extern fn pango_font_description_set_style(font: ptr<char>, style: i32)
unsafe extern fn pango_font_description_set_absolute_size(font: ptr<char>, size: f64)
unsafe extern fn pango_layout_set_font_description(layout: ptr<char>, font: ptr<char>)
unsafe extern fn pango_layout_set_text(layout: ptr<char>, text: ptr<char>, length: i32)
unsafe extern fn pango_layout_get_size(layout: ptr<char>, width: ptr<i32>, height: ptr<i32>)
unsafe extern fn pango_layout_get_baseline(layout: ptr<char>) -> i32
unsafe extern fn pango_color_parse(color: ptr<u16>, spec: ptr<char>) -> i32
unsafe extern fn pango_layout_set_width(layout: ptr<char>, width: i32)
unsafe extern fn pango_layout_set_ellipsize(layout: ptr<char>, mode: i32)
unsafe extern fn pango_layout_set_auto_dir(layout: ptr<char>, enabled: i32)
unsafe extern fn pango_layout_set_single_paragraph_mode(layout: ptr<char>, enabled: i32)
unsafe extern fn pango_layout_get_cursor_pos(layout: ptr<char>, index: i32, strong: ptr<i32>, weak: ptr<i32>)
unsafe extern fn pango_layout_xy_to_index(layout: ptr<char>, x: i32, y: i32, index: ptr<i32>, trailing: ptr<i32>) -> i32
unsafe extern fn pango_attr_list_new() -> ptr<char>
unsafe extern fn pango_attr_list_insert(list: ptr<char>, attribute: ptr<char>)
unsafe extern fn pango_attr_list_unref(list: ptr<char>)
unsafe extern fn pango_attr_background_new(r: u16, g: u16, b: u16) -> ptr<char>
unsafe extern fn pango_layout_set_attributes(layout: ptr<char>, attributes: ptr<char>)
unsafe extern fn g_object_unref(object: ptr<char>)

const CAIRO_ARGB32: i32 = 0
const CAIRO_RGB24: i32 = 1
const CAIRO_A8: i32 = 2
const CAIRO_FILL_EVEN_ODD: i32 = 1
const CAIRO_EXTEND_PAD: i32 = 3
const PANGO_SCALE: i64 = 1024

struct BrowserRect:
    x: i64
    y: i64
    w: i64
    h: i64

fn browser_rect_contains(r: BrowserRect, x: i64, y: i64) -> bool:
    return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h

struct BrowserCanvas:
    texture: ptr<char>
    surface: ptr<char>
    cr: ptr<char>
    layout: ptr<char>
    font: ptr<char>
    document_surface: ptr<char>
    width: i64
    height: i64

unsafe fn browser_canvas_free(c: ptr<BrowserCanvas>):
    sdl_texture_destroy(c.texture)
    if c.layout != (0 as ptr<char>): g_object_unref(c.layout)
    if c.font != (0 as ptr<char>): pango_font_description_free(c.font)
    if c.cr != (0 as ptr<char>): cairo_destroy(c.cr)
    if c.surface != (0 as ptr<char>): cairo_surface_destroy(c.surface)
    if c.document_surface != (0 as ptr<char>): cairo_surface_destroy(c.document_surface)
    c[0] = BrowserCanvas(0 as ptr<char>, 0 as ptr<char>, 0 as ptr<char>, 0 as ptr<char>, 0 as ptr<char>, 0 as ptr<char>, 0, 0)

unsafe fn browser_canvas_resize(c: ptr<BrowserCanvas>, renderer: ptr<char>, width: i64, height: i64) -> i64:
    if c.width == width and c.height == height: return 0
    if width < 1 or height < 1 or width > 4096 or height > 4096: return -22
    browser_canvas_free(c)
    c.texture = sdl_texture_create_argb8888(renderer, width, height)
    if c.texture == (0 as ptr<char>): return -12
    c.surface = cairo_image_surface_create(CAIRO_ARGB32, width as i32, height as i32)
    if cairo_surface_status(c.surface) != 0: return -12
    c.cr = cairo_create(c.surface)
    if cairo_status(c.cr) != 0: return -12
    c.layout = pango_cairo_create_layout(c.cr)
    c.font = pango_font_description_new()
    if c.layout == (0 as ptr<char>) or c.font == (0 as ptr<char>): return -12
    pango_font_description_set_family(c.font, "Inter, Noto Sans, Sans" as ptr<char>)
    pango_layout_set_single_paragraph_mode(c.layout, 1)
    pango_layout_set_auto_dir(c.layout, 0)
    c.width = width
    c.height = height
    return 0

unsafe fn browser_canvas_present(c: ptr<BrowserCanvas>, renderer: ptr<char>) -> i64:
    if cairo_status(c.cr) != 0: return -22
    cairo_surface_flush(c.surface)
    let stride: i64 = (cairo_image_surface_get_stride(c.surface) as i64) / 4
    let pixels: ptr<u32> = cairo_image_surface_get_data(c.surface) as ptr<u32>
    let status: i64 = sdl_texture_update_argb8888(c.texture, pixels, c.width, c.height, stride, stride * c.height)
    if status < 0: return status
    status = sdl_texture_copy(renderer, c.texture)
    if status < 0: return status
    sdl_present(renderer)
    return 0

unsafe fn chrome_color(cr: ptr<char>, color: i64):
    cairo_set_source_rgb(cr, (((color >> 16) & 255) as f64) / 255.0, (((color >> 8) & 255) as f64) / 255.0, ((color & 255) as f64) / 255.0)

unsafe fn chrome_round(cr: ptr<char>, r: BrowserRect, radius: i64):
    let x: f64 = r.x as f64
    let y: f64 = r.y as f64
    let right: f64 = (r.x + r.w) as f64
    let bottom: f64 = (r.y + r.h) as f64
    let rad: f64 = min(radius, min(r.w, r.h) / 2) as f64
    cairo_new_sub_path(cr)
    cairo_arc(cr, right - rad, y + rad, rad, -1.570796327, 0.0)
    cairo_arc(cr, right - rad, bottom - rad, rad, 0.0, 1.570796327)
    cairo_arc(cr, x + rad, bottom - rad, rad, 1.570796327, 3.141592654)
    cairo_arc(cr, x + rad, y + rad, rad, 3.141592654, 4.712388980)
    cairo_close_path(cr)

unsafe fn chrome_box(cr: ptr<char>, r: BrowserRect, radius: i64, color: i64, border: i64):
    if r.w < 1 or r.h < 1: return
    if radius > 0: chrome_round(cr, r, radius)
    else: cairo_rectangle(cr, r.x as f64, r.y as f64, r.w as f64, r.h as f64)
    chrome_color(cr, color)
    if border < 0:
        cairo_fill(cr)
    else:
        cairo_fill_preserve(cr)
        chrome_color(cr, border)
        cairo_set_line_width(cr, 1.0)
        cairo_stroke(cr)

unsafe fn chrome_dot(cr: ptr<char>, x: i64, y: i64, radius: i64, color: i64):
    chrome_color(cr, color)
    cairo_new_sub_path(cr)
    cairo_arc(cr, x as f64, y as f64, radius as f64, 0.0, 6.283185307)
    cairo_fill(cr)

struct BrowserLabel:
    x: i64
    y: i64
    width: i64
    size: i64
    weight: i32
    color: i64

unsafe fn chrome_text_setup(c: ptr<BrowserCanvas>, text: string, size: i64, weight: i32, width: i64):
    pango_layout_set_attributes(c.layout, 0 as ptr<char>)
    pango_font_description_set_absolute_size(c.font, (size * PANGO_SCALE) as f64)
    pango_font_description_set_weight(c.font, weight)
    pango_layout_set_font_description(c.layout, c.font)
    if width > 0:
        pango_layout_set_width(c.layout, (width * PANGO_SCALE) as i32)
        pango_layout_set_ellipsize(c.layout, 3)
    else:
        pango_layout_set_width(c.layout, -1)
        pango_layout_set_ellipsize(c.layout, 0)
    pango_layout_set_text(c.layout, text as ptr<char>, -1)

unsafe fn chrome_label(c: ptr<BrowserCanvas>, text: string, label: BrowserLabel):
    if label.width < 1: return
    chrome_text_setup(c, text, label.size, label.weight, label.width)
    chrome_color(c.cr, label.color)
    cairo_move_to(c.cr, label.x as f64, label.y as f64)
    pango_cairo_show_layout(c.cr, c.layout)

unsafe fn chrome_caret_x(c: ptr<BrowserCanvas>, position: i64) -> i64:
    let caret: [4]i32
    pango_layout_get_cursor_pos(c.layout, position as i32, &caret[0], 0 as ptr<i32>)
    return (caret[0] as i64) / PANGO_SCALE

unsafe fn chrome_text_selection(c: ptr<BrowserCanvas>, start: i64, end: i64):
    let list: ptr<char> = pango_attr_list_new()
    let color: ptr<char> = pango_attr_background_new(14906, 25186, 33153)
    # PangoAttribute starts with a class pointer followed by two unsigned byte indices.
    let range: ptr<u32> = (color + 8) as ptr<u32>
    range[0] = start as u32
    range[1] = end as u32
    pango_attr_list_insert(list, color)
    pango_layout_set_attributes(c.layout, list)
    pango_attr_list_unref(list)
