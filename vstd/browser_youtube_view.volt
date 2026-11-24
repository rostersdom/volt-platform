use browser_youtube_metadata
use http

unsafe fn browser_youtube_view_id(address: string) -> string:
    let p: ptr<char> = address as ptr<char>
    if __volt_strlen(address) == 25 and html_match(p, 0, 25, "about:youtube:") and youtube_id_valid(p + 14, 11):
        return (p + 14) as string
    return ""

# `out` holds the internal address (25 bytes plus NUL), not any original query or fragment.
unsafe fn browser_youtube_address(url: string, out: ptr<char>) -> bool:
    if not youtube_video_id(url, out + 14): return false
    let prefix: ptr<char> = "about:youtube:" as ptr<char>
    for i in 0..14: out[i] = prefix[i]
    return true

# Display and copy the public link, not the internal origin or the CDN locator.
unsafe fn browser_youtube_display(address: string, out: ptr<char>) -> string:
    let id: string = browser_youtube_view_id(address)
    if id == "": return address
    let prefix: string = "https://www.youtube.com/watch?v="
    let n: i64 = __volt_strlen(prefix)
    for i in 0..n: out[i] = (prefix as ptr<char>)[i]
    for i in 0..12: out[n + i] = (id as ptr<char>)[i]
    return out as string

unsafe fn browser_youtube_public_ipv4(ip: ptr<u8>) -> bool:
    let a: u8 = ip[0]
    let b: u8 = ip[1]
    let c: u8 = ip[2]
    if a == 0 or a == 10 or a == 127 or a >= 224: return false
    if a == 100 and b >= 64 and b <= 127: return false
    if a == 169 and b == 254: return false
    if a == 172 and b >= 16 and b <= 31: return false
    if a == 192 and (b == 168 or (b == 0 and (c == 0 or c == 2)) or (b == 88 and c == 99)): return false
    if a == 198 and (b == 18 or b == 19 or (b == 51 and c == 100)): return false
    return not (a == 203 and b == 0 and c == 113)

unsafe fn browser_youtube_escape(out: ptr<ByteBuffer>, text: string) -> i64:
    let p: ptr<char> = text as ptr<char>
    let i: i64 = 0
    while p[i] != '\0':
        let status: i64 = 0
        if p[i] == '&': status = http_append_text(out, "&amp;")
        elif p[i] == '<': status = http_append_text(out, "&lt;")
        elif p[i] == '>': status = http_append_text(out, "&gt;")
        elif p[i] == '"': status = http_append_text(out, "&quot;")
        elif p[i] == '\'': status = http_append_text(out, "&#39;")
        else: status = bytes_push(out, p[i] as u8)
        if status < 0: return status
        i += 1
    return 0

unsafe fn browser_youtube_html(out: ptr<ByteBuffer>, id: string, metadata: ptr<YoutubeMetadata>, checked: bool, fetched: bool) -> i64:
    let playable: bool = metadata.media[0] != '\0'
    let name: string = "Видео YouTube"
    if metadata.title[0] != '\0': name = (&metadata.title[0]) as string
    out.len = 0
    let status: i64 = http_append_text(out, "<!doctype html><html lang=\"ru\"><head><meta charset=\"utf-8\"><title>")
    if status == 0: status = browser_youtube_escape(out, name)
    let style: string = "</title><style>html {background:#eef3fb} body {margin:0;color:#1c2a46;font:16px/1.5 system-ui,sans-serif} main {box-sizing:border-box;max-width:900px;margin:20px auto;padding:20px} .label {color:#a23140;font-size:13px;font-weight:700;margin:0} h1 {font-size:28px;line-height:1.15;margin:8px 0 14px} .card {background:#fff;border:1px solid #d6e2f3;border-radius:16px;padding:16px;box-shadow:0 6px 16px #29436618} .card p {margin:0 0 12px} .card .id {font-size:13px;color:#4e607d;margin:12px 0 0} a {display:block;width:fit-content;max-width:100%;background:#234a83;color:#fff;padding:8px 14px;border-radius:8px;text-decoration:none;font-weight:600} video {width:100%;aspect-ratio:16 / 9;object-fit:contain;border-radius:10px} @media (max-width:480px) {main {margin:8px auto;padding:12px} h1 {font-size:22px}}</style></head><body><main><p class=\"label\">YOUTUBE В VOLT</p><h1>"
    if status == 0: status = http_append_text(out, style)
    if status == 0: status = browser_youtube_escape(out, name)
    if status == 0: status = http_append_text(out, "</h1><section class=\"card\">")
    if playable:
        if status == 0: status = http_append_text(out, "<video controls></video><p class=\"id\">Щелчок — воспроизведение или пауза. Пробел — пауза или продолжение.</p>")
    else:
        if checked:
            if status == 0:
                if fetched: status = http_append_text(out, "<p>Для этого ролика VOLT не получил прямой файл со звуком и видео.</p><p>Официальный плеер YouTube пока не поддерживается.</p>")
                else: status = http_append_text(out, "<p>Не удалось загрузить данные ролика с YouTube.</p>")
        else:
            if status == 0: status = http_append_text(out, "<p>VOLT может показать ролик, если YouTube отдаёт прямой файл с видео и звуком без входа в аккаунт.</p><p>При проверке YouTube получит ID ролика и ваш IP-адрес.</p>")
    if status == 0:
        if checked: status = http_append_text(out, "<a href=\"#check\">Проверить снова</a>")
        else: status = http_append_text(out, "<a href=\"#check\">Проверить доступность</a>")
    if status == 0: status = http_append_text(out, "<p class=\"id\">ID ролика: ")
    if status == 0: status = browser_youtube_escape(out, id)
    if status == 0: status = http_append_text(out, "</p></section></main></body></html>")
    if status == 0: status = bytes_push(out, 0 as u8)
    return status
