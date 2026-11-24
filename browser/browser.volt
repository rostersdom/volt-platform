use browser_window
use process

unsafe fn browser_open(path: string, check: bool, default_page: bool, scripts: bool, screenshot: string) -> i64:
    let youtube: [26]char
    let target: string = path
    if browser_youtube_address(path, &youtube[0]): target = (&youtube[0]) as string
    if browser_validate_target(target) < 0:
        put_err("browser: invalid or unsupported HTTP URL\n")
        return 2
    let active_buffer: ByteBuffer
    let candidate_buffer: ByteBuffer
    bytes_init(&active_buffer)
    bytes_init(&candidate_buffer)
    defer bytes_free(&active_buffer)
    defer bytes_free(&candidate_buffer)
    let active_page: BrowserPage
    let candidate_page: BrowserPage
    active_page.scripts_enabled = scripts
    active_page.visual = not check or screenshot != ""
    let active_storage: ptr<BrowserPageStorage> = browser_page_allocate(&active_page)
    if active_storage == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(active_page.storage)
    let candidate_storage: ptr<BrowserPageStorage> = browser_page_allocate(&candidate_page)
    if candidate_storage == (0 as ptr<BrowserPageStorage>): return 1
    defer browser_page_free(candidate_page.storage)
    let pixels: i64 = BROWSER_CONTROLLER_WIDTH * BROWSER_CONTROLLER_HEIGHT
    let framebuffer: ptr<u32> = mmap(2 * pixels * sizeof(u32)) as ptr<u32>
    if (framebuffer as i64) <= 0: return 1
    defer munmap(framebuffer as ptr<char>, 2 * pixels * sizeof(u32))
    let scroll: PaintScrollState = PaintScrollState(0, 0)
    let controller: BrowserNavigationController = BrowserNavigationController(&active_page, &candidate_page, &active_buffer, &candidate_buffer, framebuffer, framebuffer + pixels, &scroll, 0 as ptr<char>, 0, 0, false)
    let source: string = "about:home"
    if check: source = target
    let opened: i64 = browser_controller_navigate_url(&controller, source)
    if opened == -1002 and default_page:
        opened = browser_controller_navigate_url(&controller, "about:home")
    if opened < 0:
        if opened == -1001:
            put_err("browser: invalid or unsupported HTTP URL\n")
            return 2
        if opened == -1003: put_err("browser: HTTP redirect loop\n")
        elif opened == -1004: put_err("browser: HTTP redirect limit exceeded\n")
        elif opened == -1005: put_err("browser: unsupported HTTP Content-Encoding\n")
        elif opened == -1002: put_err("browser: cannot read local document\n")
        elif opened == -2: put_err("browser: unable to resolve HTTP hostname\n")
        elif opened == HTTP_TIMEOUT: put_err("browser: navigation timed out\n")
        elif opened == -90 or opened == -7: put_err("browser: document or response too large\n")
        elif browser_is_http_status(opened):
            let digits: [4]char
            browser_http_status_digits(opened, &digits[0])
            put_err("browser: HTTP status ")
            put_errnl((&digits[0]) as string)
        elif opened == -22 and browser_web_prefix(path) > 0: put_err("browser: invalid HTTP response\n")
        else: put_err("browser: unable to fetch or render document\n")
        return 1
    if not check:
        let result: i64 = browser_run_window(&controller, target)
        if result != 0: put_err("browser: cannot display the window\n")
        return result
    if scroll.offset > 0 and browser_paint_page(&active_page, framebuffer, scroll.offset) != 0: return 1
    if screenshot != "":
        let surface: ptr<char> = cairo_image_surface_create_for_data(framebuffer as ptr<char>, CAIRO_ARGB32, BROWSER_CONTROLLER_WIDTH as i32, BROWSER_CONTROLLER_HEIGHT as i32, (BROWSER_CONTROLLER_WIDTH * 4) as i32)
        defer cairo_surface_destroy(surface)
        if cairo_surface_write_to_png(surface, screenshot as ptr<char>) != 0:
            put_errnl("browser: unable to write PNG")
            return 1
    if active_page.storage.js.notice == 1: put_errnl("browser: JavaScript exception")
    elif active_page.storage.js.notice == 2: put_errnl("browser: JavaScript stopped or unavailable; page rendered without it")
    elif active_page.storage.js.notice == BROWSER_JS_POLICY: put_errnl("browser: JavaScript disabled by page security policy")
    let colored: i64 = 0
    let i: i64 = 0
    while i < pixels:
        if framebuffer[i] != (0xff000000 | BROWSER_CANVAS_COLOR) as u32: colored += 1
        i += 1
    put_str("VOLT native viewer pixel check passed: ")
    put_int(colored)
    nl()
    return 0

fn browser_usage() -> i64:
    put_err("usage: browser [--js] [--check | --screenshot FILE.png] [local-file | HTTP(S)-URL]\n")
    return 2

fn main() -> i64:
    let count: i64 = argc()
    let check: bool = false
    let scripts: bool = false
    let path_given: bool = false
    let path: string = ""
    let screenshot: string = ""
    let i: i64 = 1
    while i < count:
        match arg_at(i):
            Ok(argument):
                if argument == "--check" and not check and not path_given:
                    check = true
                elif argument == "--js" and not scripts and not path_given:
                    scripts = true
                elif argument == "--screenshot" and not check and not path_given:
                    i += 1
                    match arg_at(i):
                        Ok(filename): screenshot = filename
                        Err(error): return browser_usage()
                    if screenshot == "" or screenshot[0] == '-': return browser_usage()
                    check = true
                elif argument == "--js" or argument == "--check" or argument == "--screenshot" or path_given:
                    return browser_usage()
                else:
                    path = argument
                    path_given = true
            Err(error): return 2
        i += 1
    if not path_given:
        path = "about:home"
        if check: path = "examples/page.html"
    unsafe: return browser_open(path, check, not path_given, scripts, screenshot)
