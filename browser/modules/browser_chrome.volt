use browser_graphics
use browser_loader

const CHROME_START_WIDTH: i64 = 1120
const CHROME_START_HEIGHT: i64 = 744
const CHROME_MIN_WIDTH: i64 = 500
const CHROME_MIN_HEIGHT: i64 = 428
const CHROME_MAX_WIDTH: i64 = 2560
const CHROME_MAX_HEIGHT: i64 = 1800
const CHROME_COMPACT_WIDTH: i64 = 590
const CHROME_TOP: i64 = 88
const CHROME_FOOT: i64 = 34

const CHROME_BG: i64 = 0x0d141e
const CHROME_BAR: i64 = 0x151e2b
const CHROME_FIELD: i64 = 0x0e1722
const CHROME_PANEL: i64 = 0x172433
const CHROME_BORDER: i64 = 0x314153
const CHROME_HOVER: i64 = 0x253648
const CHROME_TEXT: i64 = 0xecf3fb
const CHROME_MUTED: i64 = 0xaabace
const CHROME_DISABLED: i64 = 0x64758a
const CHROME_ACCENT: i64 = 0x7ceac5
const CHROME_ERROR: i64 = 0xffadab

const CHROME_BACK: i64 = 1
const CHROME_FORWARD: i64 = 2
const CHROME_RELOAD: i64 = 3
const CHROME_HOME: i64 = 4
const CHROME_ADDRESS: i64 = 5
const CHROME_GO: i64 = 6
const CHROME_HISTORY: i64 = 7
const CHROME_ZOOM: i64 = 8
const CHROME_RETRY: i64 = 9
const CHROME_SHORTCUT: i64 = 10
const CHROME_STOP: i64 = 11
const CHROME_VIDEO: i64 = 12
const CHROME_YOUTUBE_CHECK: i64 = 13

struct BrowserControls:
    history: BrowserHistory
    address: [8193]char
    address_length: i64
    caret: i64
    selection: i64
    address_shift: i64
    focused: bool
    title: [513]char
    width: i64
    height: i64
    zoom: i64
    pointer_x: i64
    pointer_y: i64
    hover_url: [8193]char
    hover_action: i64
    scroll_grab: i64
    history_open: bool
    history_first: i64
    history_row: i64
    pending: bool
    retry: bool
    job: ptr<BrowserLoadJob>
    load: BrowserLoad
    status: string
    status_text: [32]char
    page_dirty: bool
    script_click: BrowserJsClick
    script_owner: ptr<BrowserPageStorage>
    script_href: [8193]char

unsafe fn chrome_panel(c: ptr<BrowserControls>) -> BrowserRect:
    return BrowserRect(12, CHROME_TOP, c.width - 24, c.height - CHROME_TOP - CHROME_FOOT)

unsafe fn chrome_page(c: ptr<BrowserControls>) -> BrowserRect:
    let panel: BrowserRect = chrome_panel(c)
    return BrowserRect(panel.x + 10, panel.y + 10, panel.w - 32, panel.h - 20)

fn chrome_nav(action: i64) -> BrowserRect:
    return BrowserRect(16 + (action - 1) * 40, 42, 36, 36)

unsafe fn chrome_nav_enabled(c: ptr<BrowserControls>, action: i64) -> bool:
    if c.pending: return action == CHROME_RELOAD
    if action == CHROME_BACK: return c.history.current > 0
    if action == CHROME_FORWARD: return c.history.current + 1 < c.history.count
    if action == CHROME_RELOAD: return c.history.current >= 0
    return true

unsafe fn chrome_history_button(c: ptr<BrowserControls>) -> BrowserRect:
    let width: i64 = 108
    if c.width < CHROME_COMPACT_WIDTH: width = 36
    return BrowserRect(c.width - width - 16, 42, width, 36)

unsafe fn chrome_address_box(c: ptr<BrowserControls>) -> BrowserRect:
    return BrowserRect(184, 41, chrome_history_button(c).x - 194, 38)

unsafe fn chrome_go_button(c: ptr<BrowserControls>) -> BrowserRect:
    let address: BrowserRect = chrome_address_box(c)
    return BrowserRect(address.x + address.w - 33, address.y + 5, 27, 28)

unsafe fn chrome_address_text(c: ptr<BrowserControls>) -> BrowserRect:
    let address: BrowserRect = chrome_address_box(c)
    let inset: i64 = 64
    if c.focused or c.pending: inset = 12
    return BrowserRect(address.x + inset, address.y + 9, address.w - inset - 40, 21)

unsafe fn chrome_zoom_button(c: ptr<BrowserControls>) -> BrowserRect:
    return BrowserRect(c.width - 78, c.height - 29, 62, 24)

unsafe fn chrome_retry_button(c: ptr<BrowserControls>) -> BrowserRect:
    return BrowserRect(c.width - 184, c.height - 29, 96, 24)

unsafe fn chrome_history_rows(c: ptr<BrowserControls>) -> i64:
    return max(1, min(c.history.count, min(8, (c.height - CHROME_TOP - CHROME_FOOT - 62) / 39)))

unsafe fn chrome_history_panel(c: ptr<BrowserControls>) -> BrowserRect:
    let width: i64 = min(400, c.width - 32)
    return BrowserRect(c.width - width - 16, 83, width, 51 + chrome_history_rows(c) * 39)

unsafe fn chrome_history_item(c: ptr<BrowserControls>, row: i64) -> BrowserRect:
    let panel: BrowserRect = chrome_history_panel(c)
    return BrowserRect(panel.x + 8, panel.y + 42 + row * 39, panel.w - 16, 36)

struct ChromeHome:
    x: i64
    y: i64
    width: i64
    compact: bool

unsafe fn chrome_home_layout(c: ptr<BrowserControls>) -> ChromeHome:
    let panel: BrowserRect = chrome_panel(c)
    let width: i64 = min(770, panel.w - 46)
    return ChromeHome(panel.x + (panel.w - width) / 2, panel.y + min(92, max(20, (panel.h - 310) / 3)), width, panel.h < 390)

fn chrome_home_address(home: ChromeHome) -> BrowserRect:
    let offset: i64 = 114
    if home.compact: offset = 86
    return BrowserRect(home.x, home.y + offset, home.width, 46)

fn chrome_home_card(home: ChromeHome, index: i64) -> BrowserRect:
    let width: i64 = (home.width - 20) / 3
    let offset: i64 = 224
    let height: i64 = 73
    if home.compact:
        offset = 177
        height = 58
    return BrowserRect(home.x + (width + 10) * index, home.y + offset, width, height)

fn chrome_home_target(index: i64) -> string:
    if index == 0: return "https://example.org/"
    if index == 1: return "https://www.iana.org/help/example-domains"
    return "https://www.rfc-editor.org/rfc/rfc1149.html"

unsafe fn chrome_is_home(page: ptr<BrowserPage>) -> bool:
    let address: ptr<char> = page.url as ptr<char>
    return page.resource_length == 10 and html_match(address, 0, __volt_strlen(page.url), "about:home")

unsafe fn chrome_scroll_track(c: ptr<BrowserControls>) -> BrowserRect:
    let pane: BrowserRect = chrome_page(c)
    return BrowserRect(pane.x + pane.w + 2, pane.y + 5, 8, pane.h - 10)

unsafe fn chrome_scroll_thumb(c: ptr<BrowserControls>, state: ptr<PaintScrollState>) -> BrowserRect:
    let track: BrowserRect = chrome_scroll_track(c)
    if state.max_offset <= 0: return BrowserRect(track.x, track.y, 0, 0)
    let page_height: i64 = chrome_page(c).h / c.zoom
    let height: i64 = max(25, track.h * page_height / (page_height + state.max_offset))
    return BrowserRect(track.x + 1, track.y + (track.h - height) * state.offset / state.max_offset, track.w - 2, height)

unsafe fn chrome_icon(cr: ptr<char>, icon: i64, x: i64, y: i64, color: i64):
    cairo_save(cr)
    cairo_translate(cr, x as f64, y as f64)
    chrome_color(cr, color)
    cairo_set_line_width(cr, 1.65)
    cairo_set_line_cap(cr, 1)
    cairo_set_line_join(cr, 1)
    if icon == CHROME_BACK or icon == CHROME_FORWARD:
        if icon == CHROME_FORWARD:
            cairo_translate(cr, 18.0, 0.0)
            cairo_scale(cr, -1.0, 1.0)
        cairo_move_to(cr, 9.0, 3.5)
        cairo_line_to(cr, 3.5, 9.0)
        cairo_line_to(cr, 9.0, 14.5)
        cairo_move_to(cr, 4.0, 9.0)
        cairo_line_to(cr, 15.0, 9.0)
    elif icon == CHROME_STOP:
        cairo_rectangle(cr, 4.5, 4.5, 9.0, 9.0)
    elif icon == CHROME_RELOAD:
        cairo_arc(cr, 9.0, 9.0, 5.6, -0.65, 4.65)
        cairo_move_to(cr, 14.8, 3.1)
        cairo_line_to(cr, 14.8, 7.0)
        cairo_line_to(cr, 10.8, 7.0)
    elif icon == CHROME_HOME:
        cairo_move_to(cr, 2.8, 8.1)
        cairo_line_to(cr, 9.0, 3.0)
        cairo_line_to(cr, 15.2, 8.1)
        cairo_move_to(cr, 4.5, 7.1)
        cairo_line_to(cr, 4.5, 14.9)
        cairo_line_to(cr, 13.5, 14.9)
        cairo_line_to(cr, 13.5, 7.1)
    elif icon == CHROME_HISTORY:
        cairo_arc(cr, 9.0, 9.0, 6.1, 0.0, 6.283185307)
        cairo_move_to(cr, 9.0, 5.4)
        cairo_line_to(cr, 9.0, 9.1)
        cairo_line_to(cr, 12.0, 10.7)
    elif icon == CHROME_ADDRESS:
        cairo_rectangle(cr, 3.0, 4.5, 12.0, 9.0)
        cairo_move_to(cr, 6.0, 9.0)
        cairo_line_to(cr, 12.0, 9.0)
    else:
        cairo_move_to(cr, 3.5, 9.0)
        cairo_line_to(cr, 14.0, 9.0)
        cairo_move_to(cr, 9.5, 4.5)
        cairo_line_to(cr, 14.0, 9.0)
        cairo_line_to(cr, 9.5, 13.5)
    cairo_stroke(cr)
    cairo_restore(cr)

unsafe fn chrome_mark(cr: ptr<char>, x: i64, y: i64, size: i64):
    chrome_box(cr, BrowserRect(x, y, size, size), size / 4, CHROME_ACCENT, -1)
    cairo_save(cr)
    cairo_translate(cr, x as f64, y as f64)
    cairo_scale(cr, (size as f64) / 24.0, (size as f64) / 24.0)
    chrome_color(cr, 0x102c2b)
    cairo_move_to(cr, 13.8, 4.4)
    cairo_line_to(cr, 7.0, 13.4)
    cairo_line_to(cr, 11.2, 13.4)
    cairo_line_to(cr, 10.2, 19.6)
    cairo_line_to(cr, 17.0, 10.6)
    cairo_line_to(cr, 12.8, 10.6)
    cairo_close_path(cr)
    cairo_fill(cr)
    cairo_restore(cr)

unsafe fn chrome_draw_address(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    let cr: ptr<char> = canvas.cr
    let box: BrowserRect = chrome_address_box(c)
    let border: i64 = CHROME_BORDER
    if c.focused: border = CHROME_ACCENT
    chrome_box(cr, box, 12, CHROME_FIELD, border)
    let text: BrowserRect = chrome_address_text(c)
    let address: string = (&c.address[0]) as string
    if c.focused:
        chrome_text_setup(canvas, address, 14, 400, 0)
        let caret_x: i64 = chrome_caret_x(canvas, c.caret)
        let extent: i64 = max(1, text.w - 2)
        c.address_shift = max(0, min(c.address_shift, caret_x))
        if caret_x - c.address_shift > extent: c.address_shift = caret_x - extent
        if c.caret != c.selection: chrome_text_selection(canvas, min(c.caret, c.selection), max(c.caret, c.selection))
        cairo_save(cr)
        cairo_rectangle(cr, text.x as f64, text.y as f64, text.w as f64, text.h as f64)
        cairo_clip(cr)
        chrome_color(cr, CHROME_TEXT)
        cairo_move_to(cr, (text.x - c.address_shift) as f64, text.y as f64)
        pango_cairo_show_layout(cr, canvas.layout)
        if c.caret == c.selection: chrome_box(cr, BrowserRect(text.x + caret_x - c.address_shift, text.y + 1, 1, 18), 0, CHROME_ACCENT, -1)
        cairo_restore(cr)
    elif c.pending:
        let display: [44]char
        let pending: string = browser_youtube_display((&c.load.target[0]) as string, &display[0])
        chrome_label(canvas, pending, BrowserLabel(text.x, text.y, text.w, 14, 400, CHROME_TEXT))
    else:
        let scheme: string = "ФАЙЛ"
        let chip_color: i64 = CHROME_MUTED
        let protocol: i64 = browser_web_prefix(page.url)
        if chrome_is_home(page):
            scheme = "СТАРТ"
            address = "Введите URL или путь к файлу"
            if c.width < CHROME_COMPACT_WIDTH: address = "Введите адрес"
        elif browser_youtube_view_id(page.url) != "":
            scheme = "VOLT"
            chip_color = CHROME_ACCENT
        elif protocol == 8:
            scheme = "HTTPS"
            chip_color = CHROME_ACCENT
        elif protocol == 7: scheme = "HTTP"
        chrome_box(cr, BrowserRect(box.x + 8, box.y + 8, 48, 22), 6, CHROME_PANEL, -1)
        chrome_label(canvas, scheme, BrowserLabel(box.x + 14, box.y + 11, 42, 10, 700, chip_color))
        chrome_label(canvas, address, BrowserLabel(text.x, text.y, text.w, 14, 400, CHROME_TEXT))
    let go: BrowserRect = chrome_go_button(c)
    let fill: i64 = CHROME_PANEL
    if c.hover_action == CHROME_GO: fill = CHROME_HOVER
    if c.focused and c.address_length > 0: fill = CHROME_ACCENT
    chrome_box(cr, go, 7, fill, -1)
    let ink: i64 = CHROME_TEXT
    if fill == CHROME_ACCENT: ink = 0x102c2b
    chrome_icon(cr, CHROME_GO, go.x + 5, go.y + 5, ink)

unsafe fn chrome_draw_toolbar(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    let cr: ptr<char> = canvas.cr
    chrome_box(cr, BrowserRect(0, 0, c.width, CHROME_TOP - 4), 0, CHROME_BAR, -1)
    chrome_box(cr, BrowserRect(0, CHROME_TOP - 5, c.width, 1), 0, CHROME_BORDER, -1)
    chrome_mark(cr, 18, 9, 22)
    chrome_label(canvas, "VOLT", BrowserLabel(48, 9, 58, 15, 800, CHROME_TEXT))
    chrome_box(cr, BrowserRect(103, 11, 1, 18), 0, CHROME_BORDER, -1)
    chrome_label(canvas, (&c.title[0]) as string, BrowserLabel(118, 10, c.width - 136, 13, 500, CHROME_MUTED))
    let action: i64 = CHROME_BACK
    while action <= CHROME_HOME:
        let button: BrowserRect = chrome_nav(action)
        let ink: i64 = CHROME_DISABLED
        if chrome_nav_enabled(c, action):
            ink = CHROME_TEXT
            if c.hover_action == action: chrome_box(cr, button, 9, CHROME_HOVER, -1)
        let icon: i64 = action
        if c.pending and action == CHROME_RELOAD: icon = CHROME_STOP
        chrome_icon(cr, icon, button.x + 9, button.y + 9, ink)
        action += 1
    chrome_draw_address(canvas, c, page)
    let history: BrowserRect = chrome_history_button(c)
    let fill: i64 = CHROME_PANEL
    if c.history_open or c.hover_action == CHROME_HISTORY: fill = CHROME_HOVER
    chrome_box(cr, history, 9, fill, CHROME_BORDER)
    chrome_icon(cr, CHROME_HISTORY, history.x + 9, history.y + 9, CHROME_MUTED)
    if c.width >= CHROME_COMPACT_WIDTH:
        chrome_label(canvas, "История", BrowserLabel(history.x + 33, history.y + 9, 72, 13, 600, CHROME_TEXT))
    if c.pending: chrome_box(cr, BrowserRect(0, CHROME_TOP - 5, c.width, 2), 0, CHROME_ACCENT, -1)

unsafe fn chrome_draw_home(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>):
    let cr: ptr<char> = canvas.cr
    let panel: BrowserRect = chrome_panel(c)
    cairo_save(cr)
    chrome_round(cr, panel, 14)
    cairo_clip(cr)
    let gradient: ptr<char> = cairo_pattern_create_linear(panel.x as f64, panel.y as f64, (panel.x + panel.w) as f64, (panel.y + panel.h) as f64)
    cairo_pattern_add_color_stop_rgb(gradient, 0.0, 0.075, 0.117, 0.171)
    cairo_pattern_add_color_stop_rgb(gradient, 1.0, 0.060, 0.151, 0.164)
    cairo_set_source(cr, gradient)
    cairo_paint(cr)
    cairo_pattern_destroy(gradient)
    cairo_set_source_rgba(cr, 0.49, 0.92, 0.77, 0.045)
    cairo_set_line_width(cr, 1.0)
    let ring: i64 = 0
    while ring < 5:
        cairo_new_sub_path(cr)
        cairo_arc(cr, (panel.x + panel.w - 7) as f64, (panel.y + 22) as f64, (83 + ring * 29) as f64, 0.0, 6.283185307)
        cairo_stroke(cr)
        ring += 1
    let home: ChromeHome = chrome_home_layout(c)
    let title_size: i64 = 48
    let caption_y: i64 = home.y + 69
    if home.compact:
        title_size = 34
        caption_y = home.y + 51
    chrome_label(canvas, "Куда перейти?", BrowserLabel(home.x, home.y, home.width, title_size, 800, CHROME_TEXT))
    chrome_label(canvas, "Введите URL или путь к локальному HTML-файлу.", BrowserLabel(home.x, caption_y, home.width, 15, 400, CHROME_MUTED))
    let field: BrowserRect = chrome_home_address(home)
    let field_color: i64 = CHROME_FIELD
    if browser_rect_contains(field, c.pointer_x, c.pointer_y): field_color = CHROME_HOVER
    chrome_box(cr, field, 12, field_color, CHROME_BORDER)
    chrome_icon(cr, CHROME_ADDRESS, field.x + 15, field.y + 14, CHROME_ACCENT)
    chrome_label(canvas, "Перейти по адресу", BrowserLabel(field.x + 44, field.y + 12, field.w - 124, 15, 500, CHROME_TEXT))
    chrome_box(cr, BrowserRect(field.x + field.w - 75, field.y + 10, 61, 26), 6, CHROME_PANEL, CHROME_BORDER)
    chrome_label(canvas, "Ctrl + L", BrowserLabel(field.x + field.w - 65, field.y + 14, 54, 12, 600, CHROME_MUTED))
    let first: BrowserRect = chrome_home_card(home, 0)
    chrome_label(canvas, "Быстрый доступ", BrowserLabel(home.x, first.y - 29, home.width, 14, 650, CHROME_MUTED))
    let names: [3]string = ["Example.org", "IANA", "RFC Editor"]
    let hosts: [3]string = ["example.org", "iana.org", "rfc-editor.org"]
    let i: i64 = 0
    while i < 3:
        let card: BrowserRect = chrome_home_card(home, i)
        let fill: i64 = CHROME_PANEL
        if browser_rect_contains(card, c.pointer_x, c.pointer_y): fill = CHROME_HOVER
        chrome_box(cr, card, 10, fill, CHROME_BORDER)
        chrome_label(canvas, names[i], BrowserLabel(card.x + 12, card.y + 10, card.w - 40, 14, 650, CHROME_TEXT))
        chrome_label(canvas, hosts[i], BrowserLabel(card.x + 12, card.y + 34, card.w - 22, 11, 400, CHROME_MUTED))
        chrome_icon(cr, CHROME_GO, card.x + card.w - 26, card.y + 11, CHROME_ACCENT)
        i += 1
    cairo_restore(cr)

unsafe fn chrome_draw_status(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    let cr: ptr<char> = canvas.cr
    let text: string = "Ctrl+L — адрес · Ctrl+H — история · F5 — обновить"
    let state_color: i64 = CHROME_MUTED
    let dot: i64 = CHROME_ACCENT
    let width: i64 = c.width - 116
    if c.pending:
        text = "Загрузка страницы… · Esc — стоп"
        if c.load.youtube_lookup: text = "Проверка доступности на YouTube… · Esc — стоп"
    elif c.status != "":
        text = c.status
        if c.status != "Загрузка остановлена.":
            state_color = CHROME_ERROR
            dot = CHROME_ERROR
        if c.retry:
            let retry: BrowserRect = chrome_retry_button(c)
            width = retry.x - 42
            let retry_color: i64 = CHROME_PANEL
            if c.hover_action == CHROME_RETRY: retry_color = CHROME_HOVER
            chrome_box(cr, retry, 6, retry_color, CHROME_BORDER)
            chrome_label(canvas, "Повторить", BrowserLabel(retry.x + 12, retry.y + 4, retry.w - 20, 12, 650, CHROME_TEXT))
    elif c.focused: text = "Enter — открыть · Esc — отменить"
    elif page.storage != (0 as ptr<BrowserPageStorage>) and page.storage.js.notice > 0:
        text = "Ошибка сценария JavaScript."
        if page.storage.js.notice == 2: text = "JavaScript остановлен или недоступен; страница открыта."
        elif page.storage.js.notice == BROWSER_JS_POLICY: text = "JavaScript отключён: политика безопасности страницы."
        state_color = CHROME_ERROR
        dot = CHROME_ERROR
    elif c.hover_url[0] != 0 as char: text = (&c.hover_url[0]) as string
    elif c.hover_action == CHROME_BACK: text = "Назад · Alt+←"
    elif c.hover_action == CHROME_FORWARD: text = "Вперёд · Alt+→"
    elif c.hover_action == CHROME_RELOAD: text = "Обновить страницу · F5"
    elif c.hover_action == CHROME_HOME: text = "Стартовая страница · Alt+Home"
    elif c.hover_action == CHROME_HISTORY: text = "Открыть историю · Ctrl+H"
    elif c.hover_action == CHROME_ZOOM: text = "Масштаб страницы · Ctrl+плюс / Ctrl+минус"
    elif c.hover_action == CHROME_YOUTUBE_CHECK: text = "Проверить доступность на YouTube"
    chrome_dot(cr, 23, c.height - 17, 3, dot)
    chrome_label(canvas, text, BrowserLabel(35, c.height - 25, width, 12, 450, state_color))
    if not chrome_is_home(page):
        let zoom: BrowserRect = chrome_zoom_button(c)
        let fill: i64 = CHROME_PANEL
        if c.hover_action == CHROME_ZOOM: fill = CHROME_HOVER
        chrome_box(cr, zoom, 6, fill, CHROME_BORDER)
        let label: string = "200%"
        if c.zoom == 1: label = "100%"
        elif c.zoom == 3: label = "300%"
        chrome_label(canvas, label, BrowserLabel(zoom.x + 13, zoom.y + 3, 45, 12, 650, CHROME_TEXT))

unsafe fn chrome_draw_history(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>):
    if not c.history_open: return
    let cr: ptr<char> = canvas.cr
    let panel: BrowserRect = chrome_history_panel(c)
    cairo_save(cr)
    chrome_round(cr, BrowserRect(panel.x - 3, panel.y + 4, panel.w + 6, panel.h + 1), 13)
    cairo_set_source_rgba(cr, 0.0, 0.0, 0.0, 0.32)
    cairo_fill(cr)
    cairo_restore(cr)
    chrome_box(cr, panel, 12, CHROME_BAR, CHROME_BORDER)
    chrome_label(canvas, "История сеанса", BrowserLabel(panel.x + 15, panel.y + 12, panel.w - 30, 15, 750, CHROME_TEXT))
    let row: i64 = 0
    while row < chrome_history_rows(c):
        let index: i64 = c.history.count - 1 - c.history_first - row
        let rect: BrowserRect = chrome_history_item(c, row)
        let display: [44]char
        let url: string = browser_youtube_display(browser_history_at(&c.history, index), &display[0])
        let color: i64 = CHROME_TEXT
        if index == c.history.current:
            color = CHROME_ACCENT
            chrome_dot(cr, rect.x + 12, rect.y + 18, 3, CHROME_ACCENT)
        if row == c.history_row or browser_rect_contains(rect, c.pointer_x, c.pointer_y):
            chrome_box(cr, rect, 7, CHROME_HOVER, -1)
            if index == c.history.current: chrome_dot(cr, rect.x + 12, rect.y + 18, 3, CHROME_ACCENT)
        chrome_label(canvas, url, BrowserLabel(rect.x + 23, rect.y + 8, rect.w - 36, 13, 450, color))
        row += 1
