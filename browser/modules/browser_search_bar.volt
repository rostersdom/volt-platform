# Address-bar web search. The offline volt-search index is separate: this module
# only turns a non-URL query into a GET URL for the browser's own HTTP stack.
# The endpoint is a prefix ending in '='; VOLT_SEARCH_URL overrides the default
# so installations can pick their own provider.
link "-lc"

let BROWSER_SEARCH_DEFAULT: string = "https://html.duckduckgo.com/html/?q="
const BROWSER_SEARCH_BASE_BYTES: i64 = 511
const BROWSER_SEARCH_QUERY_BYTES: i64 = 2048
const BROWSER_SEARCH_URL_BYTES: i64 = 8192

unsafe extern fn getenv(name: ptr<char>) -> ptr<char>

unsafe fn browser_search_copy(source: ptr<char>, length: i64, out: ptr<char>, capacity: i64) -> i64:
    if length < 0 or length >= capacity: return -90
    let i: i64 = 0
    while i < length:
        out[i] = source[i]
        i += 1
    out[length] = 0 as char
    return length

unsafe fn browser_search_web_prefix(value: ptr<char>) -> i64:
    let web: string = value as string
    let n: i64 = __volt_strlen(web)
    if n >= 7 and value[0] == 'h' and value[1] == 't' and value[2] == 't' and value[3] == 'p' and value[4] == ':' and value[5] == '/' and value[6] == '/': return 7
    if n >= 8 and value[0] == 'h' and value[1] == 't' and value[2] == 't' and value[3] == 'p' and value[4] == 's' and value[5] == ':' and value[6] == '/' and value[7] == '/': return 8
    return 0

# The provider prefix must be an absolute HTTP(S) URL without a fragment.
# A malformed or missing override falls back to the built-in provider.
unsafe fn browser_search_base(out: ptr<char>, capacity: i64) -> i64:
    let override: ptr<char> = getenv("VOLT_SEARCH_URL" as ptr<char>)
    if override != (0 as ptr<char>):
        let text: string = override as string
        let n: i64 = __volt_strlen(text)
        if n > 0 and n <= BROWSER_SEARCH_BASE_BYTES and browser_search_web_prefix(override) > 0:
            let i: i64 = 0
            let valid: bool = true
            while i < n:
                let c: i64 = override[i] as i64
                if c <= 32 or c >= 127 or c == 35: valid = false
                i += 1
            if valid: return browser_search_copy(override, n, out, capacity)
    let fallback: string = BROWSER_SEARCH_DEFAULT
    return browser_search_copy(fallback as ptr<char>, __volt_strlen(fallback), out, capacity)

unsafe fn browser_search_space(c: char) -> bool:
    return c == ' ' or c == '\t' or c == '\n' or c == '\r'

unsafe fn browser_search_trim(value: string, start: ptr<i64>, end: ptr<i64>) -> bool:
    let p: ptr<char> = value as ptr<char>
    let n: i64 = __volt_strlen(value)
    let first: i64 = 0
    while first < n and browser_search_space(p[first]): first += 1
    let last: i64 = n
    while last > first and browser_search_space(p[last - 1]): last -= 1
    start[0] = first
    end[0] = last
    return first < last

unsafe fn browser_search_host_byte(c: i64) -> bool:
    if c >= 48 and c <= 57: return true
    if c >= 65 and c <= 90: return true
    if c >= 97 and c <= 122: return true
    if c == 45: return true
    if c == 46: return true
    return false

unsafe fn browser_search_host_like(value: ptr<char>, start: i64, end: i64) -> bool:
    # A bare hostname or IPv4 address has labels of letters, digits, '-' or '.'
    # and at least one dot (or is localhost). Anything else is a search query.
    let dots: i64 = 0
    let i: i64 = start
    while i < end:
        let c: i64 = value[i] as i64
        if c == 46: dots += 1
        elif not browser_search_host_byte(c): return false
        i += 1
    if dots > 0: return true
    let n: i64 = end - start
    if n != 9: return false
    let local: string = "localhost"
    let expected: ptr<char> = local as ptr<char>
    let j: i64 = 0
    while j < 9:
        if value[start + j] != expected[j]: return false
        j += 1
    return true

# true: navigate to the typed value; false: send it to the search provider.
unsafe fn browser_search_is_address(value: string) -> bool:
    let start: i64 = 0
    let end: i64 = 0
    if not browser_search_trim(value, &start, &end): return true
    let p: ptr<char> = (value as ptr<char>) + start
    let n: i64 = end - start
    if browser_search_web_prefix(p) > 0: return true
    let first: i64 = p[0] as i64
    if first == 47 or first == 46: return true  # absolute or relative path
    let i: i64 = 0
    while i < n:
        let c: i64 = p[i] as i64
        if browser_search_space(p[i]): return false
        if c == 47 or c == 58 or c == 63 or c == 35: return true
        i += 1
    return browser_search_host_like(p, 0, n)

unsafe fn browser_search_unreserved(c: i64) -> bool:
    return (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 45 or c == 46 or c == 95 or c == 126

unsafe fn browser_search_hex(c: i64, out: ptr<char>):
    let digits: string = "0123456789ABCDEF"
    let table: ptr<char> = digits as ptr<char>
    out[0] = table[(c >> 4) & 15]
    out[1] = table[c & 15]

# Append the query percent-encoded as an application/x-www-form-urlencoded value.
# Space becomes '+'; every byte outside the unreserved set becomes %XX.
unsafe fn browser_search_encode(query: string, out: ptr<char>, capacity: i64) -> i64:
    let p: ptr<char> = query as ptr<char>
    let n: i64 = __volt_strlen(query)
    let used: i64 = 0
    let i: i64 = 0
    while i < n:
        let c: i64 = p[i] as i64
        if c == 32:
            if used + 1 >= capacity: return -90
            out[used] = '+' as char
            used += 1
        elif browser_search_unreserved(c):
            if used + 1 >= capacity: return -90
            out[used] = p[i]
            used += 1
        else:
            if used + 3 >= capacity: return -90
            out[used] = '%' as char
            browser_search_hex(c, out + used + 1)
            used += 3
        i += 1
    out[used] = 0 as char
    return used

# Build a search URL for an explicit --search request, even when the text looks
# like a hostname. Returns the URL length or a negative errno.
unsafe fn browser_search_build(query: string, out: ptr<char>, capacity: i64) -> i64:
    let start: i64 = 0
    let end: i64 = 0
    if not browser_search_trim(query, &start, &end): return 0
    let text: [2049]char
    let length: i64 = end - start
    if length > BROWSER_SEARCH_QUERY_BYTES: return -22
    let p: ptr<char> = query as ptr<char>
    let i: i64 = 0
    while i < length:
        text[i] = p[start + i]
        i += 1
    text[length] = 0 as char
    let base: [512]char
    let base_length: i64 = browser_search_base(&base[0], BROWSER_SEARCH_BASE_BYTES + 1)
    if base_length < 0: return base_length
    if base_length + 1 >= capacity: return -90
    let used: i64 = 0
    while used < base_length:
        out[used] = base[used]
        used += 1
    let encoded: i64 = browser_search_encode((&text[0]) as string, out + used, capacity - used)
    if encoded < 0: return encoded
    return used + encoded

# Returns the search URL length when the typed value is not a URL or path,
# 0 when it should be navigated literally, or a negative errno.
unsafe fn browser_search_address(value: string, out: ptr<char>, capacity: i64) -> i64:
    if browser_search_is_address(value): return 0
    return browser_search_build(value, out, capacity)
