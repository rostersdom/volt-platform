use browser_chrome
use browser_document
use browser_search_bar
use utf8

unsafe fn browser_focus_address(controls: ptr<BrowserControls>):
    if not controls.focused: sdl_text_input_start()
    controls.focused = true
    controls.caret = controls.address_length
    controls.selection = 0
    controls.address_shift = 0
    controls.history_open = false
    controls.status = ""
    controls.retry = false
    browser_place_text_input(controls)

unsafe fn browser_place_text_input(controls: ptr<BrowserControls>):
    let field: BrowserRect = chrome_address_text(controls)
    let rect: [4]i32 = [field.x as i32, field.y as i32, field.w as i32, field.h as i32]
    SDL_SetTextInputRect(&rect[0])

unsafe fn browser_reset_address(controls: ptr<BrowserControls>, url: string):
    if controls.focused: sdl_text_input_stop()
    controls.focused = false
    let display: [44]char
    controls.address_length = browser_copy_address(&controls.address[0], browser_youtube_display(url, &display[0]))
    controls.caret = controls.address_length
    controls.selection = controls.caret
    controls.address_shift = 0

unsafe fn browser_replace_address(c: ptr<BrowserControls>, start: i64, end: i64, input: ptr<char>, length: i64):
    let address: ptr<char> = &c.address[0]
    let delta: i64 = length - (end - start)
    if delta > 0:
        let i: i64 = c.address_length
        while i >= end:
            address[i + delta] = address[i]
            i -= 1
    else:
        let i: i64 = end
        while i <= c.address_length:
            address[i + delta] = address[i]
            i += 1
    let i: i64 = 0
    while i < length:
        address[start + i] = input[i]
        i += 1
    c.address_length += delta
    c.caret = start + length
    c.selection = c.caret
    c.status = ""

unsafe fn browser_insert_address(c: ptr<BrowserControls>, input: ptr<char>):
    let start: i64 = min(c.caret, c.selection)
    let end: i64 = max(c.caret, c.selection)
    let room: i64 = BROWSER_ADDRESS_LIMIT - c.address_length + end - start
    let length: i64 = 0
    while input[length] != 0 as char:
        if length >= room:
            c.status = "Адрес слишком длинный."
            return
        let byte: i64 = input[length] as i64
        if byte < 32 or byte == 127:
            c.status = "Адрес содержит управляющие символы."
            return
        length += 1
    if length > 0: browser_replace_address(c, start, end, input, length)

unsafe fn browser_paste_address(c: ptr<BrowserControls>):
    let text: ptr<char> = SDL_GetClipboardText()
    if text == (0 as ptr<char>): return
    browser_insert_address(c, text)
    SDL_free(text)

unsafe fn browser_copy_selection(c: ptr<BrowserControls>, cut: bool):
    let start: i64 = min(c.caret, c.selection)
    let end: i64 = max(c.caret, c.selection)
    if start == end: return
    let last: char = c.address[end]
    c.address[end] = 0 as char
    let status: i32 = SDL_SetClipboardText(&c.address[start])
    c.address[end] = last
    if cut and status == 0: browser_replace_address(c, start, end, 0 as ptr<char>, 0)

unsafe fn browser_previous_character(c: ptr<BrowserControls>, at: i64) -> i64:
    if at == 0: return 0
    at -= 1
    while at > 0 and ((c.address[at] as i64) & 0xc0) == 0x80: at -= 1
    return at

unsafe fn browser_next_character(c: ptr<BrowserControls>, at: i64) -> i64:
    utf8_next(&c.address[0], &at, c.address_length)
    return at

fn browser_error(status: i64) -> string:
    if status == -1001: return "Проверьте адрес страницы."
    if status == -1002: return "Не удалось прочитать локальный файл."
    if status == -1003: return "Замкнутая цепочка перенаправлений."
    if status == -1004: return "Слишком много перенаправлений."
    if status == -1005: return "Сжатие ответа не поддерживается."
    if status == -16: return "Предыдущие загрузки ещё завершаются."
    if status == -2: return "Домен не найден."
    if status == -90 or status == -7: return "Документ или адрес превышает допустимый размер."
    if status == -110: return "Сервер не ответил вовремя."
    return "Не удалось открыть страницу."

unsafe fn browser_set_title(c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    let text: string = page.url
    let decoded: [2049]char
    if chrome_is_home(page): text = "Стартовая страница"
    else:
        let address: ptr<char> = page.url as ptr<char>
        let start: i64 = browser_web_prefix(page.url)
        if start > 0:
            let end: i64 = start
            while end < page.resource_length and address[end] != '/' and address[end] != '?': end += 1
            let length: i64 = end - start
            let j: i64 = 0
            while j < length:
                decoded[j] = address[start + j]
                j += 1
            decoded[length] = 0 as char
            text = (&decoded[0]) as string
        else:
            let end: i64 = __volt_strlen(page.url)
            let j: i64 = page.resource_length
            while j > 0 and address[j - 1] != '/': j -= 1
            if j < end: text = (address + j) as string
        let title_text: [2049]char
        let i: i64 = 1
        while i < page.node_count:
            let node: ptr<HtmlNode> = &page.nodes[i]
            if node.kind == HTML_ELEMENT and html_name_equal(page.source, node, "title") and node.first_child >= 0:
                let title_length: i64 = html_decode_node_text(page.source, &page.nodes[node.first_child], &title_text[0], 2049)
                let k: i64 = 0
                while k < title_length and html_space(title_text[k]): k += 1
                if k < title_length: text = (&title_text[k]) as string
                break
            i += 1
    let input: ptr<char> = text as ptr<char>
    let end: i64 = __volt_strlen(text)
    let i: i64 = 0
    let length: i64 = 0
    while i < end and length < 512:
        let code: i64 = utf8_next(input, &i, end)
        if code < 32 or code == 127: code = 32
        if code == 32 and (length == 0 or c.title[length - 1] == ' '): continue
        let written: i64 = utf8_write(code, &c.title[length], 512 - length)
        if written < 0: break
        length += written
    c.title[length] = 0 as char

unsafe fn browser_view_height(c: ptr<BrowserControls>) -> i64:
    return chrome_page(c).h / c.zoom

unsafe fn browser_viewport(c: ptr<BrowserControls>, zoom: i64) -> BrowserViewport:
    let pane: BrowserRect = chrome_page(c)
    return BrowserViewport(pane.w / zoom, pane.h / zoom)

struct BrowserReadingPosition:
    node: i64
    word: i64
    inset: i64

unsafe fn browser_is_word(page: ptr<BrowserPage>, fragment: ptr<CssFlowFragment>) -> bool:
    return fragment.byte_length > 0 and (fragment.byte_length != 1 or page.flow_text[fragment.byte_start] != ' ')

unsafe fn browser_reading_position(page: ptr<BrowserPage>, offset: i64) -> BrowserReadingPosition:
    let node: i64 = -1
    let word: i64 = 0
    let i: i64 = 0
    while i < page.fragment_count:
        let fragment: ptr<CssFlowFragment> = &page.fragments[i]
        if fragment.node_index != node:
            node = fragment.node_index
            word = 0
        if browser_is_word(page, fragment):
            let height: i64 = fragment.line_height
            if height == 0: height = 16
            if fragment.y + height > offset: return BrowserReadingPosition(node, word, offset - fragment.y)
            word += 1
        i += 1
    return BrowserReadingPosition(-1, 0, 0)

unsafe fn browser_reading_offset(page: ptr<BrowserPage>, position: BrowserReadingPosition, fallback: i64) -> i64:
    let word: i64 = position.word
    let i: i64 = 0
    while i < page.fragment_count:
        let fragment: ptr<CssFlowFragment> = &page.fragments[i]
        if fragment.node_index > position.node: break
        if fragment.node_index == position.node and browser_is_word(page, fragment):
            if word == 0: return fragment.y + position.inset
            word -= 1
        i += 1
    return fallback

unsafe fn browser_fit_page(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, zoom: i64, jump: bool):
    let page: ptr<BrowserPage> = controller.active_page
    let scroll: ptr<PaintScrollState> = controller.scroll
    if chrome_is_home(page):
        scroll.offset = 0
        scroll.max_offset = 0
    else:
        let reflow_error: string = "Не удалось изменить ширину страницы."
        let offset: i64 = scroll.offset
        let anchor: i64 = -1
        if not jump: anchor = browser_fragment_y(page)
        let at_anchor: bool = anchor >= 0 and offset == min(anchor, scroll.max_offset)
        let at_end: bool = offset > 0 and offset == scroll.max_offset
        let view: BrowserViewport = browser_viewport(c, zoom)
        if browser_reflow_needed(page, view):
            let position: BrowserReadingPosition = BrowserReadingPosition(-1, 0, 0)
            if not jump and not at_anchor and not at_end and offset > 0:
                position = browser_reading_position(page, offset)
            if browser_reflow_page(page, controller.candidate_page, view) < 0:
                if not c.retry: c.status = reflow_error
                if zoom != c.zoom: return
            elif position.node >= 0:
                offset = browser_reading_offset(page, position, offset)
        if not browser_reflow_needed(page, view) and c.status == reflow_error: c.status = ""
        c.zoom = zoom
        scroll.max_offset = paint_scroll_max(page.document_height, browser_view_height(c))
        scroll.offset = max(0, min(offset, scroll.max_offset))
        if at_end: scroll.offset = scroll.max_offset
        if jump or at_anchor: browser_scroll_to_fragment(page, scroll)
    c.page_dirty = true
    browser_hover(c, controller, c.pointer_x, c.pointer_y)

unsafe fn browser_queue(c: ptr<BrowserControls>, target: string, index: i64, resource_length: i64, reload: bool) -> bool:
    if target == "" or browser_copy_address(&c.load.target[0], target) < 0: return false
    c.load.history_index = index
    c.load.resource_length = resource_length
    c.load.reload = reload
    c.load.youtube_lookup = false
    c.history_open = false
    c.pending = true
    c.retry = false
    c.status = ""
    c.script_href[0] = '\0'
    return true

unsafe fn browser_queue_address(c: ptr<BrowserControls>, target: string, index: i64, resource_length: i64) -> bool:
    let view: [26]char
    if browser_youtube_address(target, &view[0]):
        return browser_queue(c, (&view[0]) as string, index, -1, false)
    let search: [8193]char
    let converted: i64 = browser_search_address(target, &search[0], BROWSER_SEARCH_URL_BYTES + 1)
    if converted > 0:
        return browser_queue(c, (&search[0]) as string, index, -1, false)
    if converted < 0: return false
    return browser_queue(c, target, index, resource_length, false)

unsafe fn browser_finish_load(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, result: i64):
    c.pending = false
    browser_reset_address(c, controller.active_page.url)
    if result == 0:
        c.status = ""
        browser_history_store(&c.history, c.load.history_index, controller.active_page.url, controller.active_page.resource_length)
        browser_set_title(c, controller.active_page)
        browser_fit_page(c, controller, c.zoom, true)
    else:
        c.status = browser_error(result)
        if browser_is_http_status(result):
            browser_copy_address(&c.status_text[0], "HTTP 000")
            browser_http_status_digits(result, &c.status_text[5])
            c.status = (&c.status_text[0]) as string
        c.retry = true

unsafe fn browser_stop_load(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    browser_load_job_abandon(c.job)
    c.job = 0 as ptr<BrowserLoadJob>
    c.pending = false
    c.retry = false
    browser_reset_address(c, controller.active_page.url)
    c.status = "Загрузка остановлена."
    browser_hover(c, controller, c.pointer_x, c.pointer_y)

unsafe fn browser_start_load(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>):
    let target: string = (&c.load.target[0]) as string
    if not c.load.reload and browser_update_fragment(controller.active_page, target, c.load.resource_length):
        browser_finish_load(c, controller, 0)
        return
    browser_reset_address(c, controller.active_page.url)
    controller.request_count += 1
    let started: i64 = browser_load_job_start(&c.load, browser_viewport(c, c.zoom), controller.active_page, &c.job)
    if started < 0: browser_finish_load(c, controller, started)

unsafe fn browser_poll_load(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>) -> bool:
    let job: ptr<BrowserLoadJob> = c.job
    let remaining: i64 = http_remaining_ms(job.deadline)
    if remaining < 0:
        browser_load_job_abandon(job)
        c.job = 0 as ptr<BrowserLoadJob>
        browser_finish_load(c, controller, remaining)
        return true
    if SDL_AtomicGet(&job.state) != BROWSER_LOAD_READY: return false
    let result: i64 = job.result
    if result == 0:
        result = browser_reflow_page(&job.page, controller.candidate_page, browser_viewport(c, c.zoom))
        if result == 0: result = min(0, http_remaining_ms(job.deadline))
        if result == 0:
            browser_swap_page(controller, &job.page, &job.source)
            controller.scroll.offset = 0
    browser_load_job_free(job)
    c.job = 0 as ptr<BrowserLoadJob>
    browser_finish_load(c, controller, result)
    return true

unsafe fn browser_go(c: ptr<BrowserControls>, index: i64, reload: bool) -> bool:
    return browser_queue(c, browser_history_at(&c.history, index), index, browser_history_resource_length(&c.history, index), reload)

unsafe fn browser_zoom(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, zoom: i64) -> bool:
    if chrome_is_home(controller.active_page) or zoom < 1 or zoom > 3 or zoom == c.zoom: return false
    browser_fit_page(c, controller, zoom, false)
    return true

unsafe fn browser_toggle_history(c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    browser_reset_address(c, page.url)
    c.history_open = not c.history_open
    c.history_first = max(0, min(c.history.count - chrome_history_rows(c), c.history.count - 1 - c.history.current))
    c.history_row = c.history.count - 1 - c.history.current - c.history_first

unsafe fn browser_edit_key(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, key: i64, shift: bool) -> bool:
    let start: i64 = min(c.caret, c.selection)
    let end: i64 = max(c.caret, c.selection)
    if key == 13 or key == SDL_KEY_KP_ENTER: return browser_queue_address(c, (&c.address[0]) as string, -1, -1)
    if key == 27:
        browser_reset_address(c, controller.active_page.url)
        c.status = ""
    elif key == SDL_KEY_SELECT_ALL:
        c.caret = c.address_length
        c.selection = 0
    elif key == SDL_KEY_COPY or key == SDL_KEY_CUT:
        browser_copy_selection(c, key == SDL_KEY_CUT)
    elif key == SDL_KEY_PASTE:
        browser_paste_address(c)
    elif key == 8 or key == 127:
        if start == end:
            if key == 8: start = browser_previous_character(c, start)
            else: end = browser_next_character(c, end)
        browser_replace_address(c, start, end, 0 as ptr<char>, 0)
    elif key == SDL_KEY_LEFT or key == SDL_KEY_RIGHT or key == SDL_KEY_HOME or key == SDL_KEY_END:
        if key == SDL_KEY_HOME: c.caret = 0
        elif key == SDL_KEY_END: c.caret = c.address_length
        elif key == SDL_KEY_LEFT:
            if not shift and start != end: c.caret = start
            else: c.caret = browser_previous_character(c, c.caret)
        else:
            if not shift and start != end: c.caret = end
            else: c.caret = browser_next_character(c, c.caret)
        if not shift: c.selection = c.caret
    else: return false
    return true

unsafe fn browser_handle_key(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, key: i64, shift: bool) -> bool:
    if key == SDL_KEY_ADDRESS:
        browser_focus_address(c)
        return true
    if key == SDL_KEY_HISTORY:
        browser_toggle_history(c, controller.active_page)
        return true
    if key == SDL_KEY_BACK: return browser_go(c, c.history.current - 1, false)
    if key == SDL_KEY_FORWARD: return browser_go(c, c.history.current + 1, false)
    if key == SDL_KEY_START: return browser_queue(c, "about:home", -1, -1, false)
    if key == SDL_KEY_RELOAD or key == SDL_KEY_F5: return browser_go(c, c.history.current, true)
    if key == SDL_KEY_ZOOM_IN: return browser_zoom(c, controller, c.zoom + 1)
    if key == SDL_KEY_ZOOM_OUT: return browser_zoom(c, controller, c.zoom - 1)
    if key == SDL_KEY_ZOOM_RESET: return browser_zoom(c, controller, 1)
    if c.history_open:
        let rows: i64 = chrome_history_rows(c)
        if key == 27: c.history_open = false
        elif key == 13 or key == SDL_KEY_KP_ENTER:
            return browser_go(c, c.history.count - 1 - c.history_first - c.history_row, false)
        elif key == SDL_KEY_UP:
            if c.history_row > 0: c.history_row -= 1
            elif c.history_first > 0: c.history_first -= 1
        elif key == SDL_KEY_DOWN:
            if c.history_row < rows - 1: c.history_row += 1
            elif c.history_first + rows < c.history.count: c.history_first += 1
        else: return false
        return true
    if c.focused: return browser_edit_key(c, controller, key, shift)
    if key == 32 and controller.active_page.visual and controller.active_page.storage != (0 as ptr<BrowserPageStorage>):
        if browser_video_pause(&controller.active_page.storage.visual.video):
            c.page_dirty = true
            return true
    if key == 114: return browser_go(c, c.history.current, true)
    if key == 91: return browser_go(c, c.history.current - 1, false)
    if key == 93: return browser_go(c, c.history.current + 1, false)
    if paint_scroll_key(controller.scroll, key, browser_view_height(c)) == 0: return false
    c.page_dirty = true
    browser_hover(c, controller, c.pointer_x, c.pointer_y)
    return true

unsafe fn browser_toolbar_action(c: ptr<BrowserControls>, page: ptr<BrowserPage>, x: i64, y: i64) -> i64:
    if browser_rect_contains(chrome_history_button(c), x, y): return CHROME_HISTORY
    if browser_rect_contains(chrome_go_button(c), x, y): return CHROME_GO
    if browser_rect_contains(chrome_address_box(c), x, y): return CHROME_ADDRESS
    if c.retry and browser_rect_contains(chrome_retry_button(c), x, y): return CHROME_RETRY
    if not chrome_is_home(page) and browser_rect_contains(chrome_zoom_button(c), x, y): return CHROME_ZOOM
    let i: i64 = CHROME_BACK
    while i <= CHROME_HOME:
        if chrome_nav_enabled(c, i) and browser_rect_contains(chrome_nav(i), x, y): return i
        i += 1
    return 0

unsafe fn browser_is_youtube_check(page: ptr<BrowserPage>, href: string) -> bool:
    return href == "#check" and browser_youtube_view_id(page.url) != ""

unsafe fn browser_hover(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, x: i64, y: i64):
    c.pointer_x = x
    c.pointer_y = y
    c.hover_url[0] = 0 as char
    if c.pending:
        c.hover_action = 0
        if browser_rect_contains(chrome_nav(CHROME_RELOAD), x, y): c.hover_action = CHROME_RELOAD
        return
    let page: ptr<BrowserPage> = controller.active_page
    c.hover_action = browser_toolbar_action(c, page, x, y)
    if c.history_open or c.hover_action != 0: return
    if chrome_is_home(page):
        let home: ChromeHome = chrome_home_layout(c)
        if browser_rect_contains(chrome_home_address(home), x, y): c.hover_action = CHROME_ADDRESS
        let i: i64 = 0
        while i < 3:
            if browser_rect_contains(chrome_home_card(home, i), x, y):
                c.hover_action = CHROME_SHORTCUT
                browser_copy_address(&c.hover_url[0], chrome_home_target(i))
            i += 1
        return
    let pane: BrowserRect = chrome_page(c)
    if browser_rect_contains(pane, x, y):
        let px: i64 = (x - pane.x) / c.zoom
        let py: i64 = (y - pane.y) / c.zoom
        if browser_video_hit(page, px, py + controller.scroll.offset) > 0:
            c.hover_action = CHROME_VIDEO
            return
        let href: [8193]char
        let hit: i64 = browser_hit_test_view(page, controller.scroll.offset, px, py, browser_view_height(c), &href[0])
        if hit > 0:
            let target: string = (&href[0]) as string
            if browser_is_youtube_check(page, target):
                c.hover_action = CHROME_YOUTUBE_CHECK
                return
            let known: i64 = -1
            if browser_resolve_href(page, target, &c.hover_url[0], &known) < 0: c.hover_url[0] = 0 as char

unsafe fn browser_scroll_drag(c: ptr<BrowserControls>, scroll: ptr<PaintScrollState>, y: i64) -> bool:
    let track: BrowserRect = chrome_scroll_track(c)
    let thumb: BrowserRect = chrome_scroll_thumb(c, scroll)
    let range: i64 = track.h - thumb.h
    if range <= 0: return false
    let position: i64 = max(0, min(y - track.y - c.scroll_grab, range))
    let offset: i64 = (position * scroll.max_offset + range / 2) / range
    if offset == scroll.offset: return false
    scroll.offset = offset
    c.page_dirty = true
    return true

unsafe fn browser_click_address(c: ptr<BrowserControls>, canvas: ptr<BrowserCanvas>, x: i64, y: i64):
    let text: BrowserRect = chrome_address_text(c)
    if not c.focused or not browser_rect_contains(text, x, y):
        browser_focus_address(c)
        return
    chrome_text_setup(canvas, (&c.address[0]) as string, 14, 400, 0)
    let index: i32 = 0
    let trailing: i32 = 0
    pango_layout_xy_to_index(canvas.layout, ((x - text.x + c.address_shift) * PANGO_SCALE) as i32, (8 * PANGO_SCALE) as i32, &index, &trailing)
    let at: i64 = index as i64
    while trailing > 0:
        at = browser_next_character(c, at)
        trailing -= 1
    c.caret = at
    c.selection = at

unsafe fn browser_queue_link(c: ptr<BrowserControls>, page: ptr<BrowserPage>, href: string) -> bool:
    if browser_is_youtube_check(page, href):
        if not browser_queue(c, page.url, c.history.current, -1, true): return false
        c.load.youtube_lookup = true
        return true
    let target: [8193]char
    let limit: i64 = -1
    if browser_resolve_href(page, href, &target[0], &limit) <= 0: return false
    let resolved: string = (&target[0]) as string
    if browser_web_prefix(resolved) > 0: return browser_queue_address(c, resolved, -1, limit)
    return browser_queue(c, resolved, -1, limit, false)

unsafe fn browser_script_follow_link(c: ptr<BrowserControls>, page: ptr<BrowserPage>):
    if not c.pending and c.script_href[0] != '\0': browser_queue_link(c, page, (&c.script_href[0]) as string)

unsafe fn browser_script_click(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, x: i64, y: i64, href: string) -> bool:
    let page: ptr<BrowserPage> = controller.active_page
    if page.storage == (0 as ptr<BrowserPageStorage>): return false
    let js: ptr<BrowserJs> = &page.storage.js
    if js.pid <= 0: return false
    let click: ptr<BrowserJsClick> = &c.script_click
    if click.pid > 0: return true
    let deadline: i64 = http_deadline_after(BROWSER_JS_CLICK_MS)
    if deadline < 0: return false
    let count: i64 = 0
    let node: i64 = browser_find_hit(page, controller.scroll.offset, x, y, browser_view_height(c), 0 as ptr<char>)
    if node < 0:
        # Block buttons also receive clicks on their background, not only their glyphs.
        let i: i64 = js.target_count
        while i > 0:
            i -= 1
            let target: i64 = js.targets[i]
            let box: CssLayoutBox = page.boxes[target]
            if not box.hidden and browser_rect_contains(BrowserRect(box.x, box.y, box.width, box.height), x, y + controller.scroll.offset) and html_name_equal(page.source, &page.nodes[target], "button"):
                node = target
                break
    while node > 0 and count < 128:
        count += 1
        let temp: i64 = browser_js_temp_for_node(js, node)
        if temp > 0: click.request[count] = 0 - temp
        else: click.request[count] = node
        node = page.nodes[node].parent
    click.request[0] = count
    click.pid = js.pid
    click.deadline = deadline
    click.sent = 0
    click.received = 0
    click.length = 0
    click.phase = 0
    click.fetch_deadline = 0
    click.frame.len = 0
    c.script_owner = page.storage
    browser_copy_address(&c.script_href[0], href)
    return true

unsafe fn browser_poll_script_click(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>) -> bool:
    let click: ptr<BrowserJsClick> = &c.script_click
    if click.pid <= 0: return false
    let page: ptr<BrowserPage> = controller.active_page
    if page.storage != c.script_owner or page.storage.js.pid != click.pid:
        click.pid = 0
        return false
    let js: ptr<BrowserJs> = &page.storage.js
    let reply: BrowserJsReply
    let result: i64 = browser_js_poll_click(js, click, &reply)
    if result == 0: return false
    click.pid = 0
    if result < 0:
        browser_js_stop(js)
        js.notice = 2
        browser_script_follow_link(c, page)
        return true
    if reply.dom.len > 0:
        let applied: i64 = browser_dom_apply(page, &reply.dom, &reply.text)
        if applied < 0:
            browser_js_text_free(reply.text)
            bytes_free(&reply.dom)
            browser_js_stop(js)
            js.notice = 2
            if not reply.prevent_default: browser_script_follow_link(c, page)
            return true
    if reply.text != (0 as ptr<CssTextOverrides>) or reply.dom.len > 0:
        let view: BrowserViewport = BrowserViewport(page.layout_width, page.layout_height)
        if browser_relayout(page, controller.candidate_page, view, reply.text) < 0:
            browser_js_text_free(reply.text)
            bytes_free(&reply.dom)
            browser_js_stop(js)
            js.notice = 2
            if not reply.prevent_default: browser_script_follow_link(c, page)
            return true
        browser_js_text_free(js.text)
        js.text = reply.text
        browser_fit_page(c, controller, c.zoom, false)
    bytes_free(&reply.dom)
    if reply.script_error: js.notice = 1
    if not reply.prevent_default: browser_script_follow_link(c, page)
    return true

unsafe fn browser_handle_click(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>, event: SdlInputEvent) -> bool:
    if event.button != SDL_BUTTON_LEFT: return false
    let x: i64 = event.mouse_x
    let y: i64 = event.mouse_y
    let page: ptr<BrowserPage> = controller.active_page
    let action: i64 = browser_toolbar_action(c, page, x, y)
    if action == CHROME_HISTORY:
        browser_toggle_history(c, page)
        return true
    if c.history_open:
        let row: i64 = 0
        while row < chrome_history_rows(c):
            if browser_rect_contains(chrome_history_item(c, row), x, y): return browser_go(c, c.history.count - 1 - c.history_first - row, false)
            row += 1
        if browser_rect_contains(chrome_history_panel(c), x, y): return false
        c.history_open = false
        if action == 0: return true
    if action == CHROME_BACK: return browser_go(c, c.history.current - 1, false)
    if action == CHROME_FORWARD: return browser_go(c, c.history.current + 1, false)
    if action == CHROME_RELOAD: return browser_go(c, c.history.current, true)
    if action == CHROME_HOME: return browser_queue(c, "about:home", -1, -1, false)
    if action == CHROME_GO:
        if c.focused: return browser_queue_address(c, (&c.address[0]) as string, -1, -1)
        browser_focus_address(c)
        return true
    if action == CHROME_ADDRESS:
        browser_click_address(c, canvas, x, y)
        return true
    if action == CHROME_ZOOM: return browser_zoom(c, controller, c.zoom % 3 + 1)
    if action == CHROME_RETRY:
        c.pending = true
        c.retry = false
        c.status = ""
        c.script_href[0] = '\0'
        return true
    if chrome_is_home(page):
        let home: ChromeHome = chrome_home_layout(c)
        if browser_rect_contains(chrome_home_address(home), x, y):
            browser_focus_address(c)
            return true
        let i: i64 = 0
        while i < 3:
            if browser_rect_contains(chrome_home_card(home, i), x, y): return browser_queue(c, chrome_home_target(i), -1, -1, false)
            i += 1
    else:
        let pane: BrowserRect = chrome_page(c)
        if browser_rect_contains(pane, x, y):
            let px: i64 = (x - pane.x) / c.zoom
            let py: i64 = (y - pane.y) / c.zoom
            if browser_video_click(page, px, py + controller.scroll.offset):
                if c.focused: browser_reset_address(c, page.url)
                c.page_dirty = true
                return true
            let href: [8193]char
            let hit: i64 = browser_hit_test_view(page, controller.scroll.offset, px, py, browser_view_height(c), &href[0])
            if hit <= 0: href[0] = '\0'
            if browser_script_click(c, controller, px, py, (&href[0]) as string): return true
            if hit > 0 and browser_queue_link(c, page, (&href[0]) as string): return true
        if controller.scroll.max_offset > 0 and browser_rect_contains(chrome_scroll_track(c), x, y):
            let thumb: BrowserRect = chrome_scroll_thumb(c, controller.scroll)
            if y >= thumb.y and y < thumb.y + thumb.h:
                c.scroll_grab = y - thumb.y
                SDL_CaptureMouse(1)
            else:
                let delta: i64 = browser_view_height(c)
                if y < thumb.y: delta = -delta
                paint_scroll_update(controller.scroll, delta)
                c.page_dirty = true
                browser_hover(c, controller, x, y)
            return true
    if not c.focused: return false
    browser_reset_address(c, page.url)
    c.status = ""
    return true

fn browser_reload_slot_click(event: SdlInputEvent) -> bool:
    return event.kind == SDL_INPUT_EVENT_BUTTON and event.button == SDL_BUTTON_LEFT and browser_rect_contains(chrome_nav(CHROME_RELOAD), event.mouse_x, event.mouse_y)

unsafe fn browser_handle_event(c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, canvas: ptr<BrowserCanvas>, event: SdlInputEvent, text: ptr<char>) -> bool:
    if c.pending:
        if (event.kind == SDL_INPUT_EVENT_KEY and event.key == 27) or browser_reload_slot_click(event):
            browser_stop_load(c, controller)
            return true
        if event.kind == SDL_INPUT_EVENT_KEY:
            if paint_scroll_key(controller.scroll, event.key, browser_view_height(c)) == 0: return false
            c.page_dirty = true
            browser_hover(c, controller, c.pointer_x, c.pointer_y)
            return true
        if event.kind == SDL_INPUT_EVENT_BUTTON or event.kind == SDL_INPUT_EVENT_TEXT: return false
    if event.kind == SDL_INPUT_EVENT_KEY: return browser_handle_key(c, controller, event.key, event.button != 0)
    if event.kind == SDL_INPUT_EVENT_TEXT and c.focused:
        browser_insert_address(c, text)
        return true
    if event.kind == SDL_INPUT_EVENT_WHEEL:
        if c.history_open:
            c.history_first = max(0, min(c.history_first - event.wheel_y, c.history.count - chrome_history_rows(c)))
            return true
        if paint_scroll_update(controller.scroll, -event.wheel_y * 32) == 0: return false
        c.page_dirty = true
        browser_hover(c, controller, c.pointer_x, c.pointer_y)
        return true
    if event.kind == SDL_INPUT_EVENT_BUTTON: return browser_handle_click(c, controller, canvas, event)
    if event.kind == SDL_INPUT_EVENT_MOTION:
        if c.scroll_grab >= 0: browser_scroll_drag(c, controller.scroll, event.mouse_y)
        browser_hover(c, controller, event.mouse_x, event.mouse_y)
        return true
    if event.kind == SDL_INPUT_EVENT_LEAVE:
        browser_hover(c, controller, -1, -1)
        return true
    if event.kind == SDL_INPUT_EVENT_BLUR or (event.kind == SDL_INPUT_EVENT_RELEASE and event.button == SDL_BUTTON_LEFT):
        if c.scroll_grab < 0: return false
        c.scroll_grab = -1
        SDL_CaptureMouse(0)
        return true
    return event.kind == SDL_INPUT_EVENT_REDRAW

unsafe fn browser_draw_page(canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>) -> i64:
    let cr: ptr<char> = canvas.cr
    let pane: BrowserRect = chrome_page(c)
    if c.page_dirty:
        let painted: i64 = browser_render_document(canvas, controller.active_page, pane, c.zoom, controller.scroll.offset)
        if painted < 0: return painted
        c.page_dirty = false
    chrome_box(cr, chrome_panel(c), 13, 0xffffff, CHROME_BORDER)
    cairo_save(cr)
    cairo_set_source_surface(cr, canvas.document_surface, pane.x as f64, pane.y as f64)
    cairo_rectangle(cr, pane.x as f64, pane.y as f64, pane.w as f64, pane.h as f64)
    cairo_fill(cr)
    cairo_restore(cr)
    if controller.scroll.max_offset > 0:
        chrome_box(cr, chrome_scroll_track(c), 4, 0xe7edf4, -1)
        chrome_box(cr, chrome_scroll_thumb(c, controller.scroll), 4, 0x6b839a, -1)
    return 0

unsafe fn browser_draw_frame(renderer: ptr<char>, canvas: ptr<BrowserCanvas>, controller: ptr<BrowserNavigationController>, c: ptr<BrowserControls>) -> i64:
    let page: ptr<BrowserPage> = controller.active_page
    chrome_color(canvas.cr, CHROME_BG)
    cairo_paint(canvas.cr)
    if chrome_is_home(page): chrome_draw_home(canvas, c)
    else:
        let painted: i64 = browser_draw_page(canvas, c, controller)
        if painted < 0: return painted
    chrome_draw_toolbar(canvas, c, page)
    chrome_draw_status(canvas, c, page)
    chrome_draw_history(canvas, c)
    return browser_canvas_present(canvas, renderer)

unsafe fn browser_controls_init(c: ptr<BrowserControls>, page: ptr<BrowserPage>, width: i64, height: i64):
    browser_history_init(&c.history)
    browser_history_store(&c.history, -1, page.url, page.resource_length)
    c.width = width
    c.height = height
    c.zoom = 2
    if page.visual: c.zoom = 1
    c.pointer_x = -1
    c.pointer_y = -1
    c.scroll_grab = -1
    c.status = ""
    c.retry = false
    c.pending = false
    c.job = 0 as ptr<BrowserLoadJob>
    c.script_click.pid = 0
    c.history_open = false
    c.hover_url[0] = 0 as char
    c.hover_action = 0
    c.page_dirty = true
    browser_reset_address(c, page.url)
    browser_set_title(c, page)

unsafe fn browser_resize(window: ptr<char>, renderer: ptr<char>, canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>) -> i64:
    let width: i32 = 0
    let height: i32 = 0
    SDL_GetWindowSize(window, &width, &height)
    if width <= 0 or height <= 0: return 0
    let w: i64 = max(CHROME_MIN_WIDTH, min(CHROME_MAX_WIDTH, width as i64))
    let h: i64 = max(CHROME_MIN_HEIGHT, min(CHROME_MAX_HEIGHT, height as i64))
    if w == canvas.width and h == canvas.height: return 0
    let status: i64 = browser_canvas_resize(canvas, renderer, w, h)
    if status < 0: return status
    c.width = w
    c.height = h
    browser_fit_page(c, controller, c.zoom, false)
    c.history_first = max(0, min(c.history_first, c.history.count - chrome_history_rows(c)))
    c.history_row = min(c.history_row, chrome_history_rows(c) - 1)
    if c.focused: browser_place_text_input(c)
    return 0

unsafe fn browser_dispatch_batch(window: ptr<char>, renderer: ptr<char>, canvas: ptr<BrowserCanvas>, c: ptr<BrowserControls>, controller: ptr<BrowserNavigationController>, events: ptr<SdlInputSummary>) -> i64:
    let dirty: i64 = 0
    let i: i64 = 0
    let was_loading: bool = c.pending
    let toolbar_changed: bool = false
    while i < events.event_count:
        let event: SdlInputEvent = events.events[i]
        if event.kind == SDL_INPUT_EVENT_RESIZE:
            let status: i64 = browser_resize(window, renderer, canvas, c, controller)
            if status < 0: return status
            dirty = 1
        elif not (toolbar_changed and browser_reload_slot_click(event)):
            if browser_handle_event(c, controller, canvas, event, &events.text[i][0]): dirty = 1
        # A click still belongs to the toolbar displayed before this event batch.
        if (was_loading and not c.pending) or (not was_loading and c.pending): toolbar_changed = true
        i += 1
    return dirty

unsafe fn browser_cursor(c: ptr<BrowserControls>, hand: ptr<char>, text: ptr<char>):
    let cursor: ptr<char> = SDL_GetDefaultCursor()
    if c.hover_url[0] != 0 as char or (c.hover_action != 0 and c.hover_action != CHROME_ADDRESS) or c.scroll_grab >= 0:
        if hand != (0 as ptr<char>): cursor = hand
    elif browser_rect_contains(chrome_address_text(c), c.pointer_x, c.pointer_y):
        if text != (0 as ptr<char>): cursor = text
    if cursor != (0 as ptr<char>): SDL_SetCursor(cursor)

unsafe fn browser_free_cursors(hand: ptr<char>, text: ptr<char>):
    let cursor: ptr<char> = SDL_GetDefaultCursor()
    if cursor != (0 as ptr<char>): SDL_SetCursor(cursor)
    if text != (0 as ptr<char>): SDL_FreeCursor(text)
    if hand != (0 as ptr<char>): SDL_FreeCursor(hand)

unsafe fn browser_run_window(controller: ptr<BrowserNavigationController>, initial: string) -> i64:
    if sdl_init() != 0: return 1
    defer sdl_quit()
    let window: ptr<char> = sdl_window_with_flags("Браузер VOLT", CHROME_START_WIDTH, CHROME_START_HEIGHT, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE)
    if window == (0 as ptr<char>): return 1
    defer sdl_window_destroy(window)
    SDL_SetWindowMinimumSize(window, CHROME_MIN_WIDTH as i32, CHROME_MIN_HEIGHT as i32)
    SDL_SetWindowMaximumSize(window, CHROME_MAX_WIDTH as i32, CHROME_MAX_HEIGHT as i32)
    let renderer: ptr<char> = sdl_renderer_create(window)
    if renderer == (0 as ptr<char>): return 1
    defer sdl_renderer_destroy(renderer)
    let canvas: BrowserCanvas
    defer browser_canvas_free(&canvas)
    let hand: ptr<char> = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_HAND)
    let text_cursor: ptr<char> = SDL_CreateSystemCursor(SDL_SYSTEM_CURSOR_IBEAM)
    defer browser_free_cursors(hand, text_cursor)
    defer sdl_text_input_stop()
    sdl_text_input_stop()
    let c: BrowserControls
    browser_controls_init(&c, controller.active_page, CHROME_START_WIDTH, CHROME_START_HEIGHT)
    defer bytes_free(&c.script_click.frame)
    defer browser_load_job_abandon(c.job)
    defer browser_video_close(&controller.active_page.storage.visual.video)
    if browser_resize(window, renderer, &canvas, &c, controller) < 0: return 1
    # The command-line target is literal (YouTube links are converted by the app);
    # only address-bar text may become a web search.
    if initial != "about:home": browser_queue(&c, initial, 0, -1, false)
    if browser_draw_frame(renderer, &canvas, controller, &c) < 0: return 1
    while true:
        browser_js_reap()
        let events: SdlInputSummary = sdl_poll_events()
        if events.quit: return 0
        let handled: i64 = browser_dispatch_batch(window, renderer, &canvas, &c, controller, &events)
        if handled < 0: return 1
        let dirty: bool = handled > 0
        if browser_poll_script_click(&c, controller): dirty = true
        if c.pending:
            # Finish only after draining the input that belonged to the displayed page.
            if c.job == (0 as ptr<BrowserLoadJob>):
                browser_start_load(&c, controller)
                browser_hover(&c, controller, c.pointer_x, c.pointer_y)
                dirty = true
            elif browser_poll_load(&c, controller): dirty = true
            if not c.pending: SDL_SetWindowTitle(window, &c.title[0])
        if controller.active_page.visual and browser_video_poll(&controller.active_page.storage.visual.video):
            c.page_dirty = true
            dirty = true
        if dirty:
            browser_cursor(&c, hand, text_cursor)
            if browser_draw_frame(renderer, &canvas, controller, &c) < 0: return 1
        elif events.event_count == 0:
            sdl_delay(16)
    return 0
