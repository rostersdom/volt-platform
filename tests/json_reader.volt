use json
use bytes

fn check(ok: bool, label: string):
    if not ok: panic(label)

unsafe fn parse(text: string, out: ptr<JsonValue>) -> i64:
    return json_parse(text as ptr<char>, str_len(text), out)

unsafe fn member(object: ptr<JsonValue>, key: string, out: ptr<JsonValue>) -> i64:
    return json_member(object, key as ptr<char>, str_len(key), out)

unsafe fn raw_is(value: ptr<JsonValue>, expected: string) -> bool:
    if value.stop - value.start != str_len(expected): return false
    let bytes: ptr<char> = expected as ptr<char>
    for i in 0..str_len(expected):
        if value.text[value.start + i] != bytes[i]: return false
    return true

unsafe fn check_nested():
    let text: string = " \t{\"имя\":\"Привет\",\"\\u0069tems\":[{\"v\":9007199254740993},false,null,[],{}],\"x\\u0000y\":true,\"\":-0}\r\n"
    let root: JsonValue
    let list: JsonValue
    let value: JsonValue
    check(parse(text, &root) == 0 and root.kind == JSON_OBJECT, "object root")
    check(root.text == text as ptr<char> and root.start == 2 and root.stop == str_len(text) - 2, "borrowed token without whitespace")
    check(member(&root, "имя", &value) == 0 and value.kind == JSON_STRING and raw_is(&value, "\"Привет\""), "literal UTF-8 field")
    check(member(&root, "items", &list) == 0 and list.kind == JSON_ARRAY, "escaped key lookup")
    check(json_index(&list, 0, &value) == 0 and value.kind == JSON_OBJECT, "nested object")
    check(member(&value, "v", &value) == 0 and value.kind == JSON_NUMBER and raw_is(&value, "9007199254740993"), "exact large integer and aliased output")
    check(json_index(&list, 1, &value) == 0 and value.kind == JSON_BOOL and json_bool(&value) == 0, "false")
    check(json_index(&list, 2, &value) == 0 and value.kind == JSON_NULL, "null")
    check(json_bool(&value) == JSON_ERR_ARGUMENT, "non-bool")
    check(json_index(&list, 3, &value) == 0 and value.kind == JSON_ARRAY, "empty array")
    check(json_index(&value, 0, &value) == JSON_NOT_FOUND and value.kind == JSON_ARRAY, "empty array miss")
    check(json_index(&list, 4, &value) == 0 and value.kind == JSON_OBJECT, "empty object")
    check(member(&value, "v", &value) == JSON_NOT_FOUND and value.kind == JSON_OBJECT, "empty object miss")
    check(json_index(&list, 5, &value) == JSON_NOT_FOUND and value.kind == JSON_OBJECT, "array miss")
    check(member(&root, "x", &value) == JSON_NOT_FOUND, "NUL key is not truncated")
    let key: [3]char = ['x', '\0', 'y']
    check(json_member(&root, &key[0], 3, &value) == 0 and json_bool(&value) == 1, "NUL key lookup")
    check(json_member(&root, 0 as ptr<char>, 0, &value) == 0 and raw_is(&value, "-0"), "empty key")
    check(member(&root, "missing", &value) == JSON_NOT_FOUND and raw_is(&value, "-0"), "object miss preserves output")
    check(json_index(&root, 0, &value) == JSON_ERR_ARGUMENT, "wrong accessor kind")
    check(json_index(&list, -1, &value) == JSON_ERR_ARGUMENT, "negative index")

    check(parse("{\"😀\":[],\"\\uD83d\\uDe00\":{},\"ok\":1}", &root) == 0, "valid repeated names")
    check(member(&root, "😀", &value) == JSON_ERR_DUPLICATE and raw_is(&value, "-0"), "ambiguous decoded key is not published")
    check(member(&root, "ok", &value) == 0 and raw_is(&value, "1"), "unambiguous sibling")

unsafe fn check_documents():
    let value: JsonValue
    let numbers: [7]string = ["0", "-0", "0.0", "-1.2500e+009", "1E-99999999999999999999", "18446744073709551616", "-9223372036854775809"]
    for i in 0..7:
        check(parse(numbers[i], &value) == 0 and value.kind == JSON_NUMBER and raw_is(&value, numbers[i]), "valid number lexeme")
    let bad: [26]string = ["", " \t\r\n", "[", "[1,]", "[1 2]", "{", "{\"a\":1,}", "{a:1}", "{\"a\" 1}", "{\"a\":}", "[}", "+1", "01", "-01", "-", ".1", "1.", "1e", "1e+", "1e-", "NaN", "Infinity", "True", "nul", "/*x*/0", "\"a\n\""]
    for i in 0..26:
        check(parse(bad[i], &value) == JSON_ERR_SYNTAX, "malformed document")
        check(value.kind == JSON_NUMBER and raw_is(&value, numbers[6]), "syntax error preserves output")

    let tails: [5]string = ["true false", "{}[]", "[] x", "0x20", "null null"]
    for i in 0..5:
        check(parse(tails[i], &value) == JSON_ERR_TRAILING, "trailing data")
        check(raw_is(&value, numbers[6]), "trailing data preserves output")

    let bytes: [6]char = ['n', 'u', 'l', 'l', '\0', 'x']
    check(json_parse(&bytes[0], 5, &value) == JSON_ERR_TRAILING, "raw NUL is trailing data")
    check(json_parse(&bytes[0], 3, &value) == JSON_ERR_SYNTAX, "short literal")
    check(json_parse(&bytes[0], 4, &value) == 0 and value.kind == JSON_NULL, "read exactly the given length")
    bytes[4] = 12 as char
    check(json_parse(&bytes[0], 5, &value) == JSON_ERR_TRAILING, "form feed is not JSON whitespace")
    check(json_parse(0 as ptr<char>, 0, &value) == JSON_ERR_SYNTAX, "empty byte range")
    check(json_parse(0 as ptr<char>, 1, &value) == JSON_ERR_ARGUMENT, "null input")
    check(json_parse(&bytes[0], -1, &value) == JSON_ERR_ARGUMENT, "negative length")
    check(json_parse(&bytes[0], 4, 0 as ptr<JsonValue>) == JSON_ERR_ARGUMENT, "null output")

unsafe fn check_limits():
    let value: JsonValue
    let arrays: [131]char
    for i in 0..65:
        arrays[i] = '['
        arrays[130 - i] = ']'
    arrays[65] = '0'
    check(json_parse(&arrays[1], 129, &value) == 0 and value.kind == JSON_ARRAY, "64 open containers with scalar")
    check(json_parse(&arrays[0], 131, &value) == JSON_ERR_DEPTH, "65 open containers")
    check(value.start == 0 and value.stop == 129, "depth error preserves output")

    let max_doc: ByteBuffer
    bytes_init(&max_doc)
    check(bytes_reserve(&max_doc, JSON_MAX_BYTES + 1) == 0, "limit test allocation")
    let text: ptr<char> = max_doc.data as ptr<char>
    text[0] = '0'
    for i in 1..(JSON_MAX_BYTES + 1): text[i] = ' '
    check(json_parse(text, JSON_MAX_BYTES, &value) == 0 and raw_is(&value, "0"), "exact document byte limit")
    check(json_parse(text, JSON_MAX_BYTES + 1, &value) == JSON_ERR_SIZE and raw_is(&value, "0"), "size error preserves output")
    check(bytes_free(&max_doc) == 0, "limit test cleanup")

fn main() -> i64:
    unsafe:
        check_nested()
        check_documents()
        check_limits()
    print("json reader ok")
    return 0
