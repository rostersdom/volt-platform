use html

fn main() -> i64:
    let i: i64 = 0
    let out: i64 = 0
    while i < 2:
        if i == 0:
            out = out + 1
            i = i + 1
        else:
            out = out + 10
            i = i + 1
    if i != 2 or out != 11:
        panic("VOLT branch-local mutation")
    let source: string = "A&amp;B"
    let decoded: [16]char
    let decoded_length: i64 = 0
    unsafe: decoded_length = html_decode(source, 0, 7, &decoded[0], 16)
    if decoded_length != 3 or decoded[0] != 'A' or decoded[1] != '&' or decoded[2] != 'B' or decoded[3] != '\0':
        panic("VOLT entity decode")
    let entity: string = "&amp;"
    let one: [2]char
    let consumed: i64 = 0
    unsafe: consumed = html_decode_named(entity, 0, 5, &one[0])
    if consumed != 5 or one[0] != '&':
        panic("VOLT named entity helper")
    let small: [1]char
    let limited: i64 = 0
    unsafe: limited = html_decode(entity, 0, 5, &small[0], 1)
    if limited != -7:
        panic("VOLT entity capacity")
    let all: string = "&lt;&gt;&quot;&apos;"
    unsafe: decoded_length = html_decode(all, 0, 20, &decoded[0], 16)
    if decoded_length != 4 or decoded[0] != '<' or decoded[1] != '>' or decoded[2] != '"' or decoded[3] != '\'':
        panic("VOLT named entity set")
    print("control flow ok", i, out)
    return 0
