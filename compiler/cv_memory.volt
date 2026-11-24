# One invocation owns an arena. Values and their references stay valid until exit.
let cv_chunk: ptr<char> = 0 as ptr<char>
let cv_room: i64 = 0
let cv_reserved: i64 = 0

unsafe native fn cv_copy(to: ptr<char>, from: ptr<char>, n: i64):
{
    mov rcx, rdx
    cld
    rep movsb
}

unsafe fn cv_alloc(size: i64) -> ptr<char>:
    if size < 0 or size > 268435456: panic("volt: invalid allocation\n")
    let need: i64 = max(8, (size + 7) & -8)
    if need > cv_room:
        let chunk: i64 = max(2097152, need)
        if cv_reserved + chunk > 1073741824: panic("volt: compilation memory limit\n")
        cv_chunk = mmap(chunk)
        if cv_chunk as i64 < 0: panic("volt: out of memory\n")
        cv_reserved += chunk
        cv_room = chunk
    let data: ptr<char> = cv_chunk
    cv_chunk = cv_chunk + need
    cv_room -= need
    return data

unsafe fn cv_cstring(p: ptr<char>, n: i64) -> string:
    let copy: ptr<char> = cv_alloc(n + 1)
    cv_copy(copy, p, n)
    copy[n] = '\0'
    return copy as string

const CV_FALSE: i64 = 1
const CV_TRUE: i64 = 2
const CV_NUMBER: i64 = 3
const CV_TEXT: i64 = 4
const CV_BIG: i64 = 8
const CV_REAL: i64 = 9
const CV_LIST: i64 = 10
const CV_TUPLE: i64 = 11
const CV_DICT: i64 = 12
const CV_SET: i64 = 13
const CV_NODE: i64 = 14
const CV_NUL: i64 = 5

unsafe fn cv_kind(v: i64) -> i64:
    let tag: i64 = v & 7
    if tag != 0 or v == 0: return tag
    return (v as ptr<i64>)[0]

fn cv_bool(value: bool) -> i64:
    if value: return CV_TRUE
    return CV_FALSE

unsafe fn cv_text(value: string) -> i64:
    return ((value as ptr<char>) as i64) * 8 + CV_TEXT

unsafe fn cv_cptr(value: i64) -> ptr<char>:
    if value == CV_NUL: return "" as ptr<char>
    if value & 7 != CV_TEXT: panic("volt: compiler expected text\n")
    return (value >> 3) as ptr<char>

unsafe fn cv_text_len(value: i64) -> i64:
    if value == CV_NUL: return 1
    return __volt_strlen(cv_cptr(value))

unsafe fn cv_subtext(value: i64, start: i64, count: i64) -> i64:
    if count == 0: return cv_text("")
    if value == CV_NUL: return CV_NUL
    return cv_text(cv_cstring(cv_cptr(value) + start, count))

unsafe fn cv_byte(value: i64, index: i64) -> char:
    return cv_cptr(value)[index]

unsafe fn cv_istext(v: i64) -> bool:
    return v & 7 == CV_TEXT or v == CV_NUL

unsafe fn cv_char(c: i64) -> i64:
    if c == 0: return CV_NUL
    let ch: char = c as char
    return cv_text(cv_cstring(&ch, 1))

unsafe fn cv_cat(a: i64, b: i64) -> i64:
    let left: i64 = cv_text_len(a)
    let right: i64 = cv_text_len(b)
    if left == 0: return b
    if right == 0: return a
    if a == CV_NUL or b == CV_NUL: panic("volt: compiler cannot concatenate NUL\n")
    let p: ptr<char> = cv_alloc(left + right + 1)
    cv_copy(p, cv_cptr(a), left)
    cv_copy(p + left, cv_cptr(b), right)
    p[left + right] = '\0'
    return cv_text(p as string)

unsafe fn cv_text_cmp(a: i64, b: i64) -> i64:
    if a == b: return 0
    let p: ptr<char> = cv_cptr(a)
    let q: ptr<char> = cv_cptr(b)
    if a == CV_NUL or b == CV_NUL:
        if a == CV_NUL and q[0] != '\0': return -1
        if b == CV_NUL and p[0] != '\0': return 1
        return cv_text_len(a) - cv_text_len(b)
    return cv_compare_bytes(p, q)

unsafe native fn cv_compare_bytes(p: ptr<char>, q: ptr<char>) -> i64:
{
    xor ecx, ecx
.Lcv_compare_byte:
    movzx rax, byte ptr [rdi+rcx]
    movzx rdx, byte ptr [rsi+rcx]
    cmp rax, rdx
    jne .Lcv_compare_done
    inc rcx
    test rax, rax
    jnz .Lcv_compare_byte
.Lcv_compare_done:
    sub rax, rdx
}

unsafe fn cv_is(a: i64, b: i64) -> bool:
    return a == b

unsafe fn cv_name(v: i64, s: string) -> bool:
    return cv_istext(v) and cv_text_cmp(v, cv_text(s)) == 0
