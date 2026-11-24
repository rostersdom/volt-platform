use bytevec

fn expect_byte(result: Result<u8, i32>, expected: u8):
    match result:
        Ok(value):
            if value != expected: panic("wrong byte")
        Err(error): panic("expected a byte")

fn expect_error(result: Result<u8, i32>, expected: i32):
    match result:
        Ok(value): panic("expected a checked access error")
        Err(error):
            if error != expected: panic("wrong byte access error")

fn check_capacity():
    let active: [64]ByteVec
    let i: i64 = 0
    while i < 64:
        active[i] = byte_vec_new()
        if byte_vec_len(active[i]) != 0: panic("live ByteVec slot")
        i += 1
    if byte_vec_len(byte_vec_new()) >= 0: panic("ByteVec slot limit")
    while i > 0:
        i -= 1
        if byte_vec_drop(active[i]) != 0: panic("ByteVec slot left live")

fn main() -> i64:
    check_capacity()
    let bytes: ByteVec = byte_vec_new()
    defer byte_vec_drop(bytes)
    if byte_vec_len(bytes) != 0: panic("new byte vector")
    if byte_vec_push(bytes, 0) != 0 or byte_vec_push(bytes, 255) != 0: panic("push bytes")
    let view: ByteView = byte_vec_view(bytes, 1, 2)
    let i: i64 = 0
    while i < 4096:
        if byte_vec_push(bytes, (i % 256) as u8) != 0: panic("grow byte vector")
        i += 1
    if byte_vec_len(bytes) != 4098 or byte_view_len(view) != 1: panic("known lengths")
    expect_byte(byte_vec_get(bytes, 0), 0)
    expect_byte(byte_view_get(view, 0), 255)
    expect_error(byte_view_get(view, -1), 34)
    expect_error(byte_view_get(view, 1), 34)
    expect_error(byte_vec_get(bytes, 4098), 34)
    if byte_vec_set(bytes, 1, 42) != 0: panic("checked byte write")
    expect_byte(byte_view_get(view, 0), 42)
    if byte_view_len(byte_vec_view(bytes, 4098, 4098)) != 0: panic("empty end view")
    if byte_view_len(byte_vec_view(bytes, -1, 1)) >= 0 or byte_view_len(byte_vec_view(bytes, 0, 4099)) >= 0:
        panic("invalid view range")
    expect_error(byte_view_get(ByteView(bytes, 9223372036854775807, 2), 1), 34)
    if byte_vec_drop(bytes) != 0 or byte_vec_drop(bytes) == 0: panic("double drop")
    let replacement: ByteVec = byte_vec_new()
    defer byte_vec_drop(replacement)
    if byte_vec_push(replacement, 7) != 0: panic("reuse slot")
    expect_error(byte_vec_get(bytes, 0), 9)
    expect_error(byte_view_get(view, 0), 9)
    expect_byte(byte_vec_get(replacement, 0), 7)
    print("byte vector ok")
    return 0
