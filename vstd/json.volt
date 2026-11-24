use utf8

const JSON_MAX_BYTES: i64 = 8388608
const JSON_MAX_DEPTH: i64 = 64

const JSON_OBJECT: i64 = 1
const JSON_ARRAY: i64 = 2
const JSON_STRING: i64 = 3
const JSON_NUMBER: i64 = 4
const JSON_BOOL: i64 = 5
const JSON_NULL: i64 = 6

const JSON_NOT_FOUND: i64 = -2
const JSON_ERR_SPACE: i64 = -7
const JSON_ERR_DUPLICATE: i64 = -17
const JSON_ERR_ARGUMENT: i64 = -22
const JSON_ERR_SYNTAX: i64 = -74
const JSON_ERR_DEPTH: i64 = -75
const JSON_ERR_TRAILING: i64 = -84
const JSON_ERR_SIZE: i64 = -90

# Borrowed view of exactly one token, excluding surrounding whitespace.
struct JsonValue:
    text: ptr<char>
    start: i64
    stop: i64
    kind: i64

struct JsonCursor:
    text: ptr<char>
    at: i64
    stop: i64

unsafe fn json_peek(c: ptr<JsonCursor>) -> char:
    if c.at >= c.stop: return '\0'
    return c.text[c.at]

unsafe fn json_space(c: ptr<JsonCursor>):
    while c.at < c.stop:
        let ch: char = c.text[c.at]
        if ch != ' ' and ch != '\t' and ch != '\r' and ch != '\n': return
        c.at += 1

unsafe fn json_take(c: ptr<JsonCursor>, ch: char) -> bool:
    json_space(c)
    if c.at >= c.stop or c.text[c.at] != ch: return false
    c.at += 1
    return true

unsafe fn json_utf8(text: ptr<char>, at: ptr<i64>, stop: i64) -> i64:
    let start: i64 = at[0]
    let code: i64 = utf8_next(text, at, stop)
    # utf8_next consumes one byte on error, three for literal U+FFFD.
    if code == 0xfffd and at[0] == start + 1: return JSON_ERR_SYNTAX
    return code

fn json_digit(ch: char) -> bool:
    return ch >= '0' and ch <= '9'

unsafe fn json_hex4(c: ptr<JsonCursor>) -> i64:
    if c.stop - c.at < 4: return JSON_ERR_SYNTAX
    let code: i64 = 0
    for i in 0..4:
        let ch: char = c.text[c.at + i]
        let digit: i64
        if json_digit(ch): digit = (ch as i64) - 48
        elif ch >= 'a' and ch <= 'f': digit = (ch as i64) - 87
        elif ch >= 'A' and ch <= 'F': digit = (ch as i64) - 55
        else: return JSON_ERR_SYNTAX
        code = code * 16 + digit
    c.at += 4
    return code

unsafe fn json_escape(c: ptr<JsonCursor>) -> i64:
    if c.at >= c.stop: return JSON_ERR_SYNTAX
    let ch: char = c.text[c.at]
    c.at += 1
    if ch == '"' or ch == '\\' or ch == '/': return ch as i64
    if ch == 'b': return 8
    if ch == 'f': return 12
    if ch == 'n': return 10
    if ch == 'r': return 13
    if ch == 't': return 9
    if ch != 'u': return JSON_ERR_SYNTAX
    let high: i64 = json_hex4(c)
    if high < 0: return high
    if high >= 0xd800 and high <= 0xdbff:
        if c.stop - c.at < 2: return JSON_ERR_SYNTAX
        if c.text[c.at] != '\\' or c.text[c.at + 1] != 'u': return JSON_ERR_SYNTAX
        c.at += 2
        let low: i64 = json_hex4(c)
        if low < 0xdc00 or low > 0xdfff: return JSON_ERR_SYNTAX
        return 0x10000 + (high - 0xd800) * 1024 + low - 0xdc00
    if high >= 0xdc00 and high <= 0xdfff: return JSON_ERR_SYNTAX
    return high

unsafe fn json_string_char(c: ptr<JsonCursor>) -> i64:
    let ch: char = json_peek(c)
    let byte: i64 = ch as i64
    if byte < 32: return JSON_ERR_SYNTAX
    if ch == '\\':
        c.at += 1
        return json_escape(c)
    if byte >= 128: return json_utf8(c.text, &c.at, c.stop)
    c.at += 1
    return byte

# With no output, validate and measure; otherwise the caller preflights capacity.
unsafe fn json_read_string(c: ptr<JsonCursor>, out: ptr<char>, capacity: i64) -> i64:
    if json_peek(c) != '"': return JSON_ERR_SYNTAX
    c.at += 1
    let used: i64 = 0
    while c.at < c.stop:
        if c.text[c.at] == '"':
            c.at += 1
            return used
        let code: i64 = json_string_char(c)
        if code < 0: return code
        if out != (0 as ptr<char>):
            let n: i64 = utf8_write(code, out + used, capacity - used)
            if n < 0: return JSON_ERR_SPACE
            used += n
        elif code < 0x80: used += 1
        elif code < 0x800: used += 2
        elif code < 0x10000: used += 3
        else: used += 4
    return JSON_ERR_SYNTAX

unsafe fn json_number(c: ptr<JsonCursor>) -> i64:
    if json_peek(c) == '-': c.at += 1
    let first: char = json_peek(c)
    if not json_digit(first): return JSON_ERR_SYNTAX
    c.at += 1
    if first != '0':
        while json_digit(json_peek(c)): c.at += 1
    elif json_digit(json_peek(c)): return JSON_ERR_SYNTAX
    if json_peek(c) == '.':
        c.at += 1
        if not json_digit(json_peek(c)): return JSON_ERR_SYNTAX
        while json_digit(json_peek(c)): c.at += 1
    let exp: char = json_peek(c)
    if exp == 'e' or exp == 'E':
        c.at += 1
        let sign: char = json_peek(c)
        if sign == '+' or sign == '-': c.at += 1
        if not json_digit(json_peek(c)): return JSON_ERR_SYNTAX
        while json_digit(json_peek(c)): c.at += 1
    return JSON_NUMBER

unsafe fn json_literal(c: ptr<JsonCursor>, word: string, kind: i64) -> i64:
    let size: i64 = str_len(word)
    if size > c.stop - c.at: return JSON_ERR_SYNTAX
    let bytes: ptr<char> = word as ptr<char>
    for i in 0..size:
        if c.text[c.at + i] != bytes[i]: return JSON_ERR_SYNTAX
    c.at += size
    return kind

unsafe fn json_scan(c: ptr<JsonCursor>, depth: i64) -> i64:
    json_space(c)
    let ch: char = json_peek(c)
    if ch == '"':
        let size: i64 = json_read_string(c, 0 as ptr<char>, 0)
        if size < 0: return size
        return JSON_STRING
    if ch == 't': return json_literal(c, "true", JSON_BOOL)
    if ch == 'f': return json_literal(c, "false", JSON_BOOL)
    if ch == 'n': return json_literal(c, "null", JSON_NULL)
    if ch != '{' and ch != '[': return json_number(c)

    if depth >= JSON_MAX_DEPTH: return JSON_ERR_DEPTH
    c.at += 1
    let kind: i64 = JSON_ARRAY
    let close: char = ']'
    if ch == '{':
        kind = JSON_OBJECT
        close = '}'
    if json_take(c, close): return kind
    while true:
        if kind == JSON_OBJECT:
            json_space(c)
            if json_read_string(c, 0 as ptr<char>, 0) < 0 or not json_take(c, ':'): return JSON_ERR_SYNTAX
        let child: i64 = json_scan(c, depth + 1)
        if child < 0: return child
        if json_take(c, close): return kind
        if not json_take(c, ','): return JSON_ERR_SYNTAX
    return JSON_ERR_SYNTAX

unsafe fn json_parse(text: ptr<char>, length: i64, out: ptr<JsonValue>) -> i64:
    if out == (0 as ptr<JsonValue>) or length < 0: return JSON_ERR_ARGUMENT
    if length > JSON_MAX_BYTES: return JSON_ERR_SIZE
    if length > 0 and text == (0 as ptr<char>): return JSON_ERR_ARGUMENT
    let c: JsonCursor = JsonCursor(text, 0, length)
    json_space(&c)
    let start: i64 = c.at
    let kind: i64 = json_scan(&c, 0)
    if kind < 0: return kind
    let stop: i64 = c.at
    json_space(&c)
    if c.at != length: return JSON_ERR_TRAILING
    out[0] = JsonValue(text, start, stop, kind)
    return 0

unsafe fn json_has_kind(value: ptr<JsonValue>, kind: i64) -> bool:
    if value == (0 as ptr<JsonValue>): return false
    return value.kind == kind and value.text != (0 as ptr<char>) and value.start >= 0 and value.stop > value.start and value.stop <= JSON_MAX_BYTES

unsafe fn json_key_matches(c: ptr<JsonCursor>, key: ptr<char>, size: i64) -> bool:
    let at: i64 = 0
    while c.at < c.stop:
        if at >= size: return false
        let code: i64 = json_string_char(c)
        if code < 0 or code != json_utf8(key, &at, size): return false
    return at == size

unsafe fn json_lookup(parent: ptr<JsonValue>, key: ptr<char>, size: i64, index: i64, out: ptr<JsonValue>) -> i64:
    let c: JsonCursor = JsonCursor(parent.text, parent.start + 1, parent.stop)
    let close: char = ']'
    if parent.kind == JSON_OBJECT: close = '}'
    if json_take(&c, close): return JSON_NOT_FOUND
    let found: JsonValue
    let item: i64 = 0
    while true:
        let matches: bool = item == index
        if close == '}':
            json_space(&c)
            let start: i64 = c.at
            if json_read_string(&c, 0 as ptr<char>, 0) < 0: return JSON_ERR_SYNTAX
            let name: JsonCursor = JsonCursor(c.text, start + 1, c.at - 1)
            matches = json_key_matches(&name, key, size)
            if not json_take(&c, ':'): return JSON_ERR_SYNTAX
        json_space(&c)
        let start: i64 = c.at
        # The immutable source already passed the depth check from the root.
        let kind: i64 = json_scan(&c, 1)
        if kind < 0: return kind
        if matches:
            if found.kind != 0: return JSON_ERR_DUPLICATE
            found = JsonValue(c.text, start, c.at, kind)
            if close == ']': break
        if json_take(&c, close): break
        if not json_take(&c, ','): return JSON_ERR_SYNTAX
        item += 1
    if found.kind == 0: return JSON_NOT_FOUND
    out[0] = found
    return 0

unsafe fn json_member(object: ptr<JsonValue>, key: ptr<char>, length: i64, out: ptr<JsonValue>) -> i64:
    if length < 0 or out == (0 as ptr<JsonValue>) or not json_has_kind(object, JSON_OBJECT): return JSON_ERR_ARGUMENT
    if length > JSON_MAX_BYTES: return JSON_ERR_SIZE
    if length > 0 and key == (0 as ptr<char>): return JSON_ERR_ARGUMENT
    return json_lookup(object, key, length, -1, out)

unsafe fn json_index(array: ptr<JsonValue>, index: i64, out: ptr<JsonValue>) -> i64:
    if index < 0 or out == (0 as ptr<JsonValue>) or not json_has_kind(array, JSON_ARRAY): return JSON_ERR_ARGUMENT
    return json_lookup(array, 0 as ptr<char>, 0, index, out)

unsafe fn json_bool(value: ptr<JsonValue>) -> i64:
    if not json_has_kind(value, JSON_BOOL): return JSON_ERR_ARGUMENT
    if value.text[value.start] == 't': return 1
    return 0

unsafe fn json_decode_string(value: ptr<JsonValue>, out: ptr<char>, capacity: i64) -> i64:
    if capacity < 0 or not json_has_kind(value, JSON_STRING): return JSON_ERR_ARGUMENT
    if out == (0 as ptr<char>) and capacity != 0: return JSON_ERR_ARGUMENT
    let c: JsonCursor = JsonCursor(value.text, value.start, value.stop)
    let size: i64 = json_read_string(&c, 0 as ptr<char>, 0)
    if size < 0: return size
    if c.at != value.stop: return JSON_ERR_SYNTAX
    if out == (0 as ptr<char>): return size
    if size > capacity: return JSON_ERR_SPACE
    c.at = value.start
    return json_read_string(&c, out, size)

unsafe fn json_quote_pass(text: ptr<char>, length: i64, out: ptr<char>) -> i64:
    let hex: ptr<char> = "0123456789abcdef" as ptr<char>
    let at: i64 = 0
    let used: i64 = 1
    if out != (0 as ptr<char>): out[0] = '"'
    while at < length:
        let start: i64 = at
        let code: i64 = json_utf8(text, &at, length)
        if code < 0: return code
        if code < 32 or code == 127:
            if out != (0 as ptr<char>):
                out[used] = '\\'
                out[used + 1] = 'u'
                out[used + 2] = '0'
                out[used + 3] = '0'
                out[used + 4] = hex[code / 16]
                out[used + 5] = hex[code % 16]
            used += 6
        elif code == 34 or code == 92:
            if out != (0 as ptr<char>):
                out[used] = '\\'
                out[used + 1] = code as char
            used += 2
        else:
            if out != (0 as ptr<char>):
                for i in start..at: out[used + i - start] = text[i]
            used += at - start
    if out != (0 as ptr<char>): out[used] = '"'
    return used + 1

unsafe fn json_quote(text: ptr<char>, length: i64, out: ptr<char>, capacity: i64) -> i64:
    if length < 0 or capacity < 0: return JSON_ERR_ARGUMENT
    if out == (0 as ptr<char>) and capacity != 0: return JSON_ERR_ARGUMENT
    if length > JSON_MAX_BYTES: return JSON_ERR_SIZE
    if length > 0 and text == (0 as ptr<char>): return JSON_ERR_ARGUMENT
    let size: i64 = json_quote_pass(text, length, 0 as ptr<char>)
    if size < 0: return size
    if size > JSON_MAX_BYTES: return JSON_ERR_SIZE
    if out == (0 as ptr<char>): return size
    if size > capacity: return JSON_ERR_SPACE
    return json_quote_pass(text, length, out)
