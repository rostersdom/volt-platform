# Parent-owned session cookie jar. Scripts never see these values: the worker
# only sends fetch frames, and the browser adds and captures Cookie/Set-Cookie
# around its own transport. Host-only, path-scoped, in-memory, no persistence.
use sdl
use thread

const BROWSER_COOKIE_LIMIT: i64 = 64
const BROWSER_COOKIE_HOST_BYTES: i64 = 254
const BROWSER_COOKIE_PATH_BYTES: i64 = 512
const BROWSER_COOKIE_NAME_BYTES: i64 = 128
const BROWSER_COOKIE_VALUE_BYTES: i64 = 1024
const BROWSER_COOKIE_HEADER_BYTES: i64 = 4096

struct BrowserCookie:
    used: bool
    secure: bool
    http_only: bool
    created: i64
    host: [254]char
    path: [512]char
    name: [128]char
    value: [1024]char

struct BrowserCookieJar:
    clock: i64
    entries: [64]BrowserCookie

struct BrowserCookieState:
    mutex: Mutex
    jar: ptr<BrowserCookieJar>

let browser_cookie_init: i32 = 0
let browser_cookie_state: ptr<BrowserCookieState> = 0 as ptr<BrowserCookieState>

unsafe fn browser_cookie_ensure() -> ptr<BrowserCookieState>:
    let status: i32 = SDL_AtomicGet(&browser_cookie_init)
    if status == 3: return browser_cookie_state
    if status == 2: return 0 as ptr<BrowserCookieState>
    if SDL_AtomicCAS(&browser_cookie_init, 0, 1) != 0:
        let state: ptr<BrowserCookieState> = mmap(sizeof(BrowserCookieState)) as ptr<BrowserCookieState>
        if (state as i64) <= 0:
            SDL_AtomicSet(&browser_cookie_init, 2)
            return 0 as ptr<BrowserCookieState>
        let jar: ptr<BrowserCookieJar> = mmap(sizeof(BrowserCookieJar)) as ptr<BrowserCookieJar>
        if (jar as i64) <= 0:
            munmap(state as ptr<char>, sizeof(BrowserCookieState))
            SDL_AtomicSet(&browser_cookie_init, 2)
            return 0 as ptr<BrowserCookieState>
        state.jar = jar
        if mutex_init(&state.mutex) != 0:
            munmap(jar as ptr<char>, sizeof(BrowserCookieJar))
            munmap(state as ptr<char>, sizeof(BrowserCookieState))
            SDL_AtomicSet(&browser_cookie_init, 2)
            return 0 as ptr<BrowserCookieState>
        browser_cookie_state = state
        SDL_AtomicSet(&browser_cookie_init, 3)
        return state
    while SDL_AtomicGet(&browser_cookie_init) == 1: sdl_delay(0)
    if SDL_AtomicGet(&browser_cookie_init) == 2: return 0 as ptr<BrowserCookieState>
    return browser_cookie_state

unsafe fn browser_cookie_lock(state: ptr<BrowserCookieState>) -> bool:
    if state == (0 as ptr<BrowserCookieState>): return false
    return mutex_lock(&state.mutex) == 0

unsafe fn browser_cookie_unlock(state: ptr<BrowserCookieState>):
    mutex_unlock(&state.mutex)

unsafe fn browser_cookie_space(c: char) -> bool:
    return c == ' ' or c == '\t'

unsafe fn browser_cookie_lower(c: i64) -> i64:
    if c >= 65 and c <= 90: return c + 32
    return c

unsafe fn browser_cookie_name_equal(p: ptr<char>, start: i64, end: i64, word: string) -> bool:
    let n: i64 = end - start
    if n != __volt_strlen(word): return false
    let w: ptr<char> = word as ptr<char>
    let i: i64 = 0
    while i < n:
        if browser_cookie_lower(p[start + i] as i64) != browser_cookie_lower(w[i] as i64): return false
        i += 1
    return true

unsafe fn browser_cookie_token(c: i64) -> bool:
    if c >= 48 and c <= 57: return true
    if c >= 65 and c <= 90: return true
    if c >= 97 and c <= 122: return true
    if c == 33 or c == 35 or c == 36 or c == 37 or c == 38 or c == 39: return true
    if c == 42 or c == 43 or c == 45 or c == 46: return true
    if c == 94 or c == 95 or c == 96 or c == 124 or c == 126: return true
    return false

unsafe fn browser_cookie_value_byte(c: i64) -> bool:
    if c < 33 or c > 126: return false
    if c == 34 or c == 44 or c == 59 or c == 92: return false
    return true

unsafe fn browser_cookie_copy(out: ptr<char>, capacity: i64, source: ptr<char>, length: i64, lower: bool) -> i64:
    if length < 0 or length >= capacity: return -90
    let i: i64 = 0
    while i < length:
        let c: i64 = source[i] as i64
        if lower: c = browser_cookie_lower(c)
        out[i] = c as char
        i += 1
    out[length] = 0 as char
    return length

unsafe fn browser_cookie_default_path(request: ptr<char>, length: i64, out: ptr<char>, capacity: i64) -> i64:
    # RFC 6265 default-path: the request path up to its rightmost '/'.
    let end: i64 = 0
    while end < length and request[end] != '?': end += 1
    let cut: i64 = end
    while cut > 0 and request[cut - 1] != '/': cut -= 1
    if cut <= 1: return browser_cookie_copy(out, capacity, "/" as ptr<char>, 1, false)
    return browser_cookie_copy(out, capacity, request, cut - 1, false)

unsafe fn browser_cookie_path_match(cookie: ptr<char>, request: ptr<char>, request_length: i64) -> bool:
    let cp: i64 = __volt_strlen(cookie as string)
    let end: i64 = 0
    while end < request_length and request[end] != '?': end += 1
    if end < cp: return false
    let i: i64 = 0
    while i < cp:
        if cookie[i] != request[i]: return false
        i += 1
    if end == cp: return true
    if cookie[cp - 1] == '/': return true
    return request[cp] == '/'

unsafe fn browser_cookie_host_equal(entry: ptr<BrowserCookie>, host: ptr<char>) -> bool:
    let n: i64 = __volt_strlen(host as string)
    if __volt_strlen((&entry.host[0]) as string) != n: return false
    let i: i64 = 0
    while i < n:
        if browser_cookie_lower(entry.host[i] as i64) != browser_cookie_lower(host[i] as i64): return false
        i += 1
    return true

unsafe fn browser_cookie_exact(a: ptr<char>, b: ptr<char>) -> bool:
    let n: i64 = __volt_strlen(a as string)
    if n != __volt_strlen(b as string): return false
    let i: i64 = 0
    while i < n:
        if a[i] != b[i]: return false
        i += 1
    return true

unsafe fn browser_cookie_identity(entry: ptr<BrowserCookie>, host: ptr<char>, path: ptr<char>, name: ptr<char>) -> bool:
    return entry.used and browser_cookie_host_equal(entry, host) and browser_cookie_exact(&entry.path[0], path) and browser_cookie_exact(&entry.name[0], name)

unsafe fn browser_cookie_clear(entry: ptr<BrowserCookie>):
    entry.used = false

unsafe fn browser_cookie_delete(jar: ptr<BrowserCookieJar>, host: ptr<char>, path: ptr<char>, name: ptr<char>):
    let i: i64 = 0
    while i < BROWSER_COOKIE_LIMIT:
        let entry: ptr<BrowserCookie> = &jar.entries[i]
        if browser_cookie_identity(entry, host, path, name): browser_cookie_clear(entry)
        i += 1

unsafe fn browser_cookie_store(state: ptr<BrowserCookieState>, host: string, request_path: string, secure: bool, header: ptr<char>, length: i64) -> i64:
    let jar: ptr<BrowserCookieJar> = state.jar
    let i: i64 = 0
    while i < length and browser_cookie_space(header[i]): i += 1
    let name_start: i64 = i
    while i < length and header[i] != '=' and header[i] != ';': i += 1
    if i >= length or header[i] != '=': return 0
    let name_len: i64 = i - name_start
    if name_len < 1 or name_len >= BROWSER_COOKIE_NAME_BYTES: return 0
    let k: i64 = 0
    while k < name_len:
        if not browser_cookie_token(header[name_start + k] as i64): return 0
        k += 1
    i += 1
    let value_start: i64 = i
    while i < length and header[i] != ';': i += 1
    let value_end: i64 = i
    while value_end > value_start and browser_cookie_space(header[value_end - 1]): value_end -= 1
    let value_len: i64 = value_end - value_start
    if value_len >= BROWSER_COOKIE_VALUE_BYTES: return 0
    k = 0
    while k < value_len:
        if not browser_cookie_value_byte(header[value_start + k] as i64): return 0
        k += 1
    let path: [512]char
    let path_len: i64 = browser_cookie_default_path(request_path as ptr<char>, __volt_strlen(request_path), &path[0], BROWSER_COOKIE_PATH_BYTES)
    if path_len < 0: return path_len
    let cookie_secure: bool = false
    let http_only: bool = false
    let remove: bool = false
    let at: i64 = i
    while at < length:
        while at < length and (header[at] == ';' or browser_cookie_space(header[at])): at += 1
        let start: i64 = at
        while at < length and header[at] != ';': at += 1
        let end: i64 = at
        while end > start and browser_cookie_space(header[end - 1]): end -= 1
        if end > start:
            let eq: i64 = start
            while eq < end and header[eq] != '=': eq += 1
            if eq == end:
                if browser_cookie_name_equal(header, start, end, "secure"): cookie_secure = true
                elif browser_cookie_name_equal(header, start, end, "httponly"): http_only = true
            else:
                let key_start: i64 = start
                let key_end: i64 = eq
                let value: i64 = eq + 1
                while value < end and browser_cookie_space(header[value]): value += 1
                if browser_cookie_name_equal(header, key_start, key_end, "path"):
                    if value < end and header[value] == '/':
                        let copied: i64 = browser_cookie_copy(&path[0], BROWSER_COOKIE_PATH_BYTES, header + value, end - value, false)
                        if copied > 0: path_len = copied
                elif browser_cookie_name_equal(header, key_start, key_end, "max-age"):
                    let negative: bool = value < end and header[value] == '-'
                    if negative: value += 1
                    let age: i64 = 0
                    let digits: i64 = 0
                    while value < end and header[value] >= '0' and header[value] <= '9':
                        if age > 100000000: digits = 99
                        elif digits < 99: age = age * 10 + (header[value] as i64 - 48)
                        value += 1
                        digits += 1
                    if digits > 0 and (negative or age == 0): remove = true
    # RFC 6265 §5.3: ignore a Secure cookie received over cleartext HTTP.
    if cookie_secure and not secure: return 0
    let name: [128]char
    if browser_cookie_copy(&name[0], BROWSER_COOKIE_NAME_BYTES, header + name_start, name_len, false) < 0: return 0
    if remove:
        browser_cookie_delete(jar, host as ptr<char>, &path[0], &name[0])
        return 0
    let slot: i64 = -1
    let i2: i64 = 0
    while i2 < BROWSER_COOKIE_LIMIT and slot < 0:
        let entry: ptr<BrowserCookie> = &jar.entries[i2]
        if browser_cookie_identity(entry, host as ptr<char>, &path[0], &name[0]): slot = i2
        i2 += 1
    if slot < 0:
        i2 = 0
        while i2 < BROWSER_COOKIE_LIMIT and slot < 0:
            if not jar.entries[i2].used: slot = i2
            i2 += 1
    if slot < 0:
        let oldest: i64 = 0
        let created: i64 = 9223372036854775807
        i2 = 0
        while i2 < BROWSER_COOKIE_LIMIT:
            let entry: ptr<BrowserCookie> = &jar.entries[i2]
            if entry.created < created:
                created = entry.created
                oldest = i2
            i2 += 1
        slot = oldest
    let entry: ptr<BrowserCookie> = &jar.entries[slot]
    entry.used = true
    entry.secure = cookie_secure
    entry.http_only = http_only
    jar.clock += 1
    entry.created = jar.clock
    if browser_cookie_copy(&entry.host[0], BROWSER_COOKIE_HOST_BYTES, host as ptr<char>, __volt_strlen(host), true) < 0: return -90
    if browser_cookie_copy(&entry.path[0], BROWSER_COOKIE_PATH_BYTES, &path[0], path_len, false) < 0: return -90
    if browser_cookie_copy(&entry.name[0], BROWSER_COOKIE_NAME_BYTES, &name[0], __volt_strlen((&name[0]) as string), false) < 0: return -90
    if browser_cookie_copy(&entry.value[0], BROWSER_COOKIE_VALUE_BYTES, header + value_start, value_len, false) < 0: return -90
    return 0

unsafe fn browser_cookie_header(host: string, request_path: string, secure: bool, out: ptr<char>, capacity: i64) -> i64:
    if capacity < 2: return -22
    out[0] = 0 as char
    let state: ptr<BrowserCookieState> = browser_cookie_ensure()
    if state == (0 as ptr<BrowserCookieState>) or not browser_cookie_lock(state): return 0
    defer browser_cookie_unlock(state)
    let jar: ptr<BrowserCookieJar> = state.jar
    let used: i64 = 0
    let i: i64 = 0
    while i < BROWSER_COOKIE_LIMIT:
        let entry: ptr<BrowserCookie> = &jar.entries[i]
        if entry.used and browser_cookie_host_equal(entry, host as ptr<char>) and (not entry.secure or secure) and browser_cookie_path_match(&entry.path[0], request_path as ptr<char>, __volt_strlen(request_path)):
            let name_len: i64 = __volt_strlen((&entry.name[0]) as string)
            let value_len: i64 = __volt_strlen((&entry.value[0]) as string)
            let separator: i64 = 0
            if used > 0: separator = 2
            if used + separator + name_len + 1 + value_len >= capacity: break
            if separator > 0:
                out[used] = ';'
                out[used + 1] = ' '
                used += 2
            let k: i64 = 0
            while k < name_len:
                out[used] = entry.name[k]
                used += 1
                k += 1
            out[used] = '='
            used += 1
            k = 0
            while k < value_len:
                out[used] = entry.value[k]
                used += 1
                k += 1
        i += 1
    out[used] = 0 as char
    return used

unsafe fn browser_cookie_capture(host: string, request_path: string, secure: bool, response: ptr<ByteBuffer>, limit: i64) -> i64:
    if response == (0 as ptr<ByteBuffer>) or limit < 1: return -22
    let state: ptr<BrowserCookieState> = browser_cookie_ensure()
    if state == (0 as ptr<BrowserCookieState>) or not browser_cookie_lock(state): return 0
    defer browser_cookie_unlock(state)
    let p: ptr<char> = response.data as ptr<char>
    let n: i64 = min(limit, response.len)
    let at: i64 = 0
    while at + 1 < n:
        let end: i64 = at
        while end + 1 < n and not (p[end] == '\r' and p[end + 1] == '\n'): end += 1
        if end == at: break
        let colon: i64 = at
        while colon < end and p[colon] != ':': colon += 1
        if colon < end:
            let value: i64 = colon + 1
            while value < end and browser_cookie_space(p[value]): value += 1
            if browser_cookie_name_equal(p, at, colon, "set-cookie"):
                browser_cookie_store(state, host, request_path, secure, p + value, end - value)
        at = end + 2
    return 0