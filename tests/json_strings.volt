use json
use bytes

fn check(ok: bool, label: string):
    if not ok: panic(label)

unsafe fn parse(text: string, out: ptr<JsonValue>) -> i64:
    return json_parse(text as ptr<char>, str_len(text), out)

unsafe fn check_decode():
    let value: JsonValue
    let out: [32]char
    check(parse("\"Привет \\uD83D\\uDE00 �\"", &value) == 0, "raw UTF-8 and surrogate pair")
    let want: string = "Привет 😀 �"
    let size: i64 = str_len(want)
    let text: ptr<char> = want as ptr<char>
    check(json_decode_string(&value, 0 as ptr<char>, 0) == size, "measure decode")
    for i in 0..32: out[i] = '?'
    check(json_decode_string(&value, &out[0], size - 1) == JSON_ERR_SPACE, "short decode buffer")
    for i in 0..32: check(out[i] == '?', "short decode leaves output untouched")
    check(json_decode_string(&value, &out[0], size) == size, "exact decode buffer")
    for i in 0..size: check(out[i] == text[i], "decoded UTF-8 bytes")
    check(out[size] == '?', "decode does not append a terminator")

    check(parse("\"a\\u0000b\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\"", &value) == 0, "all JSON escapes")
    check(json_decode_string(&value, &out[0], 32) == 12, "decode embedded NUL and escapes")
    let decoded: [12]i64 = [97, 0, 98, 34, 92, 47, 8, 12, 10, 13, 9, 65]
    for i in 0..12: check((out[i] as i64) == decoded[i], "exact escaped byte")
    check(parse("\"\\uD800\\uDC00\\uDBFF\\uDFFF\"", &value) == 0, "surrogate pair boundaries")
    check(json_decode_string(&value, &out[0], 8) == 8, "boundary decode length")
    let boundary: [8]i64 = [0xf0, 0x90, 0x80, 0x80, 0xf4, 0x8f, 0xbf, 0xbf]
    for i in 0..8: check((out[i] as i64) == boundary[i], "boundary UTF-8 byte")
    check(parse("\"\"", &value) == 0 and json_decode_string(&value, &out[0], 0) == 0, "empty decoded string")
    check(json_decode_string(&value, 0 as ptr<char>, 1) == JSON_ERR_ARGUMENT, "invalid decode output")
    check(parse("null", &value) == 0 and json_decode_string(&value, &out[0], 32) == JSON_ERR_ARGUMENT, "decode rejects non-string")

unsafe fn check_invalid_strings():
    let value: JsonValue
    check(parse("true", &value) == 0, "sentinel value")
    let bad: [10]string = ["\"unterminated", "\"\\", "\"\\v\"", "\"\\u123\"", "\"\\u12xz\"", "\"\\uD800\"", "\"\\uDC00\"", "\"\\uD800\\u0041\"", "\"\\uD800\\uD800\"", "{\"\\uDC00\":0}"]
    for i in 0..10:
        check(parse(bad[i], &value) == JSON_ERR_SYNTAX and value.kind == JSON_BOOL, "invalid escape or surrogate")

    let raw: [5]char = ['"', '\0', 'a', 'b', '"']
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "unescaped NUL")
    raw[1] = 0x1f as char
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "unescaped control")
    raw[1] = 0x80 as char
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "lone continuation")
    raw[1] = 0xc0 as char
    raw[2] = 0xaf as char
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "overlong UTF-8")
    raw[1] = 0xed as char
    raw[2] = 0xa0 as char
    raw[3] = 0x80 as char
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "UTF-8 surrogate")
    raw[1] = 0xf0 as char
    raw[2] = 0x9f as char
    check(json_parse(&raw[0], 3, &value) == JSON_ERR_SYNTAX, "truncated UTF-8")
    raw[1] = 0xc2 as char
    raw[2] = 'a'
    check(json_parse(&raw[0], 5, &value) == JSON_ERR_SYNTAX, "invalid continuation")
    let above_max: [6]char = ['"', 0xf4 as char, 0x90 as char, 0x80 as char, 0x80 as char, '"']
    check(json_parse(&above_max[0], 6, &value) == JSON_ERR_SYNTAX, "UTF-8 above U+10FFFF")
    check(value.kind == JSON_BOOL, "malformed characters do not publish")

unsafe fn check_quote():
    let input: [44]char
    for i in 0..32: input[i] = i as char
    input[32] = '"'
    input[33] = '\\'
    input[34] = 127 as char
    let unicode: ptr<char> = "Я😀�" as ptr<char>
    for i in 0..9: input[35 + i] = unicode[i]

    let out: [214]char
    for i in 0..214: out[i] = '?'
    let size: i64 = 213
    check(json_quote(&input[0], 44, 0 as ptr<char>, 0) == size, "measure quote")
    check(json_quote(&input[0], 44, &out[0], size - 1) == JSON_ERR_SPACE, "short quote buffer")
    for i in 0..214: check(out[i] == '?', "short quote leaves output untouched")
    check(json_quote(&input[0], 44, &out[0], size) == size, "exact quote buffer")
    check(out[0] == '"' and out[size - 1] == '"' and out[size] == '?', "quote boundaries and no terminator")
    let hex: ptr<char> = "0123456789abcdef" as ptr<char>
    for i in 0..32:
        let at: i64 = i * 6 + 1
        check(out[at] == '\\' and out[at + 1] == 'u' and out[at + 2] == '0' and out[at + 3] == '0', "control escape prefix")
        check(out[at + 4] == hex[i / 16] and out[at + 5] == hex[i % 16], "control escape value")
    check(out[193] == '\\' and out[194] == '"' and out[195] == '\\' and out[196] == '\\', "quote and backslash escapes")

    let value: JsonValue
    let back: [44]char
    check(json_parse(&out[0], size, &value) == 0 and value.kind == JSON_STRING, "writer produced one JSON token")
    check(json_decode_string(&value, &back[0], 44) == 44, "round trip length")
    for i in 0..44: check(back[i] == input[i], "round trip bytes")
    check(json_quote(0 as ptr<char>, 0, &out[0], 2) == 2 and out[0] == '"' and out[1] == '"', "empty source")

    let invalid: [2]char = ['a', 0xff as char]
    for i in 0..214: out[i] = '?'
    check(json_quote(&invalid[0], 2, &out[0], 214) == JSON_ERR_SYNTAX, "invalid UTF-8 before writing")
    for i in 0..214: check(out[i] == '?', "bad UTF-8 leaves output untouched")
    check(json_quote(0 as ptr<char>, JSON_MAX_BYTES + 1, &out[0], 214) == JSON_ERR_SIZE, "reject oversized source before reading")

    let zeros: ByteBuffer
    bytes_init(&zeros)
    let limit: i64 = (JSON_MAX_BYTES - 2) / 6
    check(bytes_reserve(&zeros, limit + 1) == 0, "quote limit allocation")
    let source: ptr<char> = zeros.data as ptr<char>
    for i in 0..(limit + 1): source[i] = '\0'
    check(json_quote(source, limit, 0 as ptr<char>, 0) == JSON_MAX_BYTES, "exact quoted byte limit")
    check(json_quote(source, limit + 1, &out[0], 214) == JSON_ERR_SIZE and out[0] == '?', "reject oversized quote before writing")
    check(bytes_free(&zeros) == 0, "quote limit cleanup")

fn main() -> i64:
    unsafe:
        check_decode()
        check_invalid_strings()
        check_quote()
    print("json strings ok")
    return 0
