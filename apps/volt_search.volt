use browser_search
use fs
use process

unsafe native fn volt_search_getcwd(output: ptr<char>, capacity: i64) -> i64:
{
    mov eax, 79
    syscall
}

unsafe fn volt_search_absolute(path: string, output: ptr<char>) -> i64:
    let input: ptr<char> = path as ptr<char>
    let length: i64 = __volt_strlen(path)
    if length == 0 or length > BROWSER_SEARCH_PATH_BYTES: return -22
    let prefix: i64 = 0
    if input[0] != '/':
        let at: i64 = 0
        while at < length and input[at] != '/':
            if input[at] == ':': return -22
            at += 1
        let size: i64 = volt_search_getcwd(output, BROWSER_SEARCH_PATH_BYTES + 1)
        if size < 0: return size
        if size < 2 or output[0] != '/': return -22
        prefix = size - 1
        if output[prefix - 1] != '/':
            output[prefix] = '/'
            prefix += 1
    if length > BROWSER_SEARCH_PATH_BYTES - prefix: return -7
    for i in 0..(length + 1): output[prefix + i] = input[i]
    if output[1] == '/': return -22
    return 0

unsafe fn volt_search_read(path: string, out: ptr<ByteBuffer>) -> i64:
    # O_CLOEXEC | O_NONBLOCK | O_NOCTTY; do not read pipes, devices or directories.
    let fd: i64 = open(path, 0x80900, 0)
    if fd < 0: return fd
    defer close(fd)
    let stat: [32]u64
    let status: i64 = __volt_fs_statx(fd, "" as ptr<char>, 0x1000, 0x201, &stat[0])
    if status < 0: return status
    if (stat[0] & 0x201) != 0x201 or ((stat[3] >> 32) & 0xf000) != 0x8000: return -22
    if stat[5] > BROWSER_SEARCH_FILE_BYTES as u64: return -7
    out.len = 0
    while true:
        let room: i64 = bytes_read_room(out, BROWSER_SEARCH_FILE_BYTES)
        if room < 0: return room
        let n: i64 = read(fd, out.data + out.len, room)
        if n == -4: continue
        if n < 0: return n
        if n == 0:
            out.data[out.len] = 0 as u8
            if __volt_strlen(out.data as ptr<char> as string) != out.len: return -22
            return 0
        out.len += n
        if out.len > BROWSER_SEARCH_FILE_BYTES: return -7
    return 0

unsafe fn volt_search_is_html(path: string) -> bool:
    let end: i64 = __volt_strlen(path)
    return (end >= 5 and html_name_in(path, end - 5, 5, ".html")) or (end >= 4 and html_name_in(path, end - 4, 4, ".htm"))

unsafe fn volt_search_escape(text: string):
    let p: ptr<char> = text as ptr<char>
    let at: i64 = 0
    while p[at] != '\0':
        if p[at] == '&': put_str("&amp;")
        elif p[at] == '<': put_str("&lt;")
        elif p[at] == '>': put_str("&gt;")
        elif p[at] == '"': put_str("&quot;")
        elif p[at] == '\'': put_str("&#39;")
        else: put_char(p[at])
        at += 1

unsafe fn volt_search_href(path: ptr<char>):
    # VOLT resolves absolute local paths and percent-decodes them, but has no file: scheme.
    let href: [6145]char
    let hex: ptr<char> = "0123456789ABCDEF" as ptr<char>
    let used: i64 = 0
    let at: i64 = 0
    while path[at] != '\0':
        let c: i64 = path[at] as i64
        if (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 45 or c == 46 or c == 47 or c == 95 or c == 126:
            href[used] = path[at]
            used += 1
        else:
            href[used] = '%'
            href[used + 1] = hex[c >> 4]
            href[used + 2] = hex[c & 15]
            used += 3
        at += 1
    href[used] = '\0'
    put_str((&href[0]) as string)

unsafe fn volt_search_page(index: ptr<BrowserSearchIndex>, query: string, hits: ptr<BrowserSearchHit>, count: i64):
    put_str("<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>Локальный поиск VOLT</title><style>body { color:#18232b; background:#fff; } main { margin:16px; } li { margin:12px 0; } a { color:#164e63; } p { margin:4px 0; }</style></head><body><main><h1>Локальный поиск VOLT</h1><p>Только явно указанные файлы: ")
    put_int(index.document_count)
    put_str("</p><p>Запрос: ")
    let shown: [644]char
    browser_search_preview(query as ptr<char>, __volt_strlen(query), &shown[0])
    volt_search_escape((&shown[0]) as string)
    put_str("</p>")
    if count == 0:
        put_str("<p>Ничего не найдено.</p>")
    else:
        put_str("<ol>")
        for i in 0..count:
            let doc: ptr<BrowserSearchDocument> = &index.documents[hits[i].document]
            put_str("<li><a href=\"")
            volt_search_href(&doc.path[0])
            put_str("\">")
            if doc.title[0] == '\0': put_str("Без названия")
            else: volt_search_escape((&doc.title[0]) as string)
            put_str("</a><p>")
            volt_search_escape((&doc.preview[0]) as string)
            put_str("</p><small>Слов запроса: ")
            put_int(hits[i].matched)
            put_str("; в заголовке: ")
            put_int(hits[i].in_title)
            put_str("</small></li>")
        put_str("</ol>")
    put_str("</main></body></html>\n")

unsafe fn volt_search_run(query: string) -> i64:
    let index: ptr<BrowserSearchIndex> = browser_search_new()
    if index == (0 as ptr<BrowserSearchIndex>):
        put_errnl("volt-search: cannot allocate index")
        return 1
    defer browser_search_free(index)
    let source: ByteBuffer
    bytes_init(&source)
    defer bytes_free(&source)
    for i in 2..argc():
        let path: string = ""
        match arg_at(i):
            Ok(value): path = value
            Err(_): return 2
        let absolute: [2049]char
        let file: string = (&absolute[0]) as string
        let status: i64 = volt_search_absolute(path, &absolute[0])
        if status == 0: status = volt_search_read(file, &source)
        if status == 0: status = browser_search_add(index, file, source.data as ptr<char> as string, volt_search_is_html(file))
        if status < 0:
            let shown: [644]char
            browser_search_preview(path as ptr<char>, __volt_strlen(path), &shown[0])
            if status == -7: put_err("volt-search: file or index limit exceeded: ")
            elif status == -22: put_err("volt-search: expected a local regular file with valid UTF-8 text or HTML: ")
            else: put_err("volt-search: cannot read or index: ")
            put_errnl((&shown[0]) as string)
            return 1
    let hits: [64]BrowserSearchHit
    let count: i64 = browser_search_query(index, query, &hits[0], BROWSER_SEARCH_DOCUMENTS)
    if count < 0:
        put_errnl("volt-search: query must be UTF-8 and at most 1024 bytes")
        return 2
    volt_search_page(index, query, &hits[0], count)
    return 0

fn volt_search_usage() -> i64:
    put_errnl("usage: volt-search QUERY FILE [FILE ...] > results.html")
    return 2

fn main() -> i64:
    match arg_at(1):
        Ok(query):
            if argc() >= 3:
                unsafe: return volt_search_run(query)
            if query == "--help":
                put_str("usage: volt-search QUERY FILE [FILE ...] > results.html\n")
                return 0
        Err(_): return volt_search_usage()
    return volt_search_usage()
