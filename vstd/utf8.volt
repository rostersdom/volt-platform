fn utf8_is_scalar(code: i64) -> bool:
    return code >= 0 and code <= 0x10ffff and (code < 0xd800 or code > 0xdfff)

# Decode within [position, end). A malformed sequence consumes one byte.
unsafe fn utf8_next(text: ptr<char>, position: ptr<i64>, end: i64) -> i64:
    if position[0] >= end: return -1
    let lead: i64 = text[position[0]] as i64
    position[0] += 1
    if lead < 128: return lead
    if lead < 0xc2 or lead > 0xf4: return 0xfffd
    let extra: i64 = 1
    let code: i64 = lead & 31
    let minimum: i64 = 0x80
    if lead >= 0xf0:
        extra = 3
        code = lead & 7
        minimum = 0x10000
    elif lead >= 0xe0:
        extra = 2
        code = lead & 15
        minimum = 0x800
    if extra > end - position[0]: return 0xfffd
    let i: i64 = 0
    while i < extra:
        let byte: i64 = text[position[0] + i] as i64
        if (byte & 0xc0) != 0x80: return 0xfffd
        code = (code << 6) | (byte & 63)
        i += 1
    if code < minimum or not utf8_is_scalar(code): return 0xfffd
    position[0] += extra
    return code

unsafe fn utf8_count(text: ptr<char>, length: i64) -> i64:
    let position: i64 = 0
    let count: i64 = 0
    while position < length:
        utf8_next(text, &position, length)
        count += 1
    return count

unsafe fn utf8_write(code: i64, out: ptr<char>, capacity: i64) -> i64:
    if not utf8_is_scalar(code): return -22
    let width: i64 = 1
    let prefix: i64 = 0
    if code >= 0x10000:
        width = 4
        prefix = 0xf0
    elif code >= 0x800:
        width = 3
        prefix = 0xe0
    elif code >= 0x80:
        width = 2
        prefix = 0xc0
    if capacity < width: return -7
    let i: i64 = width - 1
    while i > 0:
        out[i] = (0x80 | (code & 63)) as char
        code >>= 6
        i -= 1
    out[0] = (prefix | code) as char
    return width
