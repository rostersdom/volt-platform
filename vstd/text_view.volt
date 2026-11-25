module text_view

# Non-owning byte range. Safe views inherit the lifetime of a VOLT string.
pub struct TextView:
    data: ptr<char>
    length: i64

pub fn from_string(source: string) -> TextView:
    unsafe:
        return TextView(source as ptr<char>, str_len(source))

pub unsafe fn from_bytes(data: ptr<char>, length: i64) -> TextView:
    if length < 0 or (length > 0 and data == (0 as ptr<char>)): panic("volt: invalid TextView\n")
    return TextView(data, length)

pub fn len(view: TextView) -> i64:
    return view.length

pub fn get(view: TextView, index: i64) -> u8:
    if index < 0 or index >= view.length: panic("volt: TextView index out of bounds\n")
    unsafe: return view.data[index] as u8

pub fn slice(view: TextView, start: i64, end: i64) -> TextView:
    if start < 0 or end < start or end > view.length: panic("volt: TextView range out of bounds\n")
    if view.length == 0: return view
    unsafe: return TextView(view.data + start, end - start)

# Capacity includes the terminator; out must not overlap the borrowed bytes.
pub unsafe fn copy_cstr(view: TextView, out: ptr<char>, capacity: i64) -> i64:
    if out == (0 as ptr<char>) or capacity < 0: return -22
    if capacity <= view.length: return -28

    for i in 0..view.length:
        if view.data[i] == '\0': return -22
    for i in 0..view.length:
        out[i] = view.data[i]
    out[view.length] = '\0'
    return view.length
