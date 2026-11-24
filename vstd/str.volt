# VOLT strings are validated NUL-terminated values; raw byte pointers stay unsafe.

use io

let str_arena_ptr: ptr<char> = 0 as ptr<char>
let str_arena_used: i64 = 0
let str_arena_size: i64 = 0

unsafe fn str_arena_new(need: i64) -> ptr<char>:
    if need < 0 or str_arena_used < 0 or str_arena_used > str_arena_size or need >= str_arena_size - str_arena_used:
        put_errnl("volt: arena full")
        panic("arena")
    let q: ptr<char> = str_arena_ptr + str_arena_used
    str_arena_used = str_arena_used + need + 1
    return q

fn str_len(s: string) -> i64:
    return __volt_strlen(s)

fn str_eq(a: string, b: string) -> bool:
    let la: i64 = str_len(a)
    if la != str_len(b):
        return false
    let ap: ptr<char>
    let bp: ptr<char>
    let equal: bool = true
    unsafe:
        ap = a as ptr<char>
        bp = b as ptr<char>
        let i: i64 = 0
        while i < la:
            if ap[i] != bp[i]:
                equal = false
                break
            i = i + 1
    return equal

fn str_concat(a: string, b: string) -> string:
    let la: i64 = str_len(a)
    let lb: i64 = str_len(b)
    if la > 9223372036854775807 - lb:
        put_errnl("volt: string too large")
        panic("arena")
    let need: i64 = la + lb
    let q: ptr<char>
    let ap: ptr<char>
    let bp: ptr<char>
    let result: string
    unsafe:
        q = str_arena_new(need)
        ap = a as ptr<char>
        bp = b as ptr<char>
        let k: i64 = 0
        while k < la:
            q[k] = ap[k]
            k = k + 1
        let j: i64 = 0
        while j < lb:
            q[la + j] = bp[j]
            j = j + 1
        q[la + lb] = '\0'
        result = q as string
    return result

fn str_repeat(s: string, n: i64) -> string:
    let ls: i64 = str_len(s)
    if n <= 0 or ls == 0:
        return ""
    if n > 9223372036854775807 / ls:
        put_errnl("volt: string too large")
        panic("arena")
    let need: i64 = ls * n
    let q: ptr<char>
    let source: ptr<char>
    let result: string
    unsafe:
        q = str_arena_new(need)
        source = s as ptr<char>
        let i: i64 = 0
        while i < need:
            q[i] = source[i % ls]
            i = i + 1
        q[need] = '\0'
        result = q as string
    return result

# Allocate the process-wide arena once, before user module initializers.
fn str_arena_init():
    let p: ptr<char>
    let map_status: i64
    unsafe:
        p = mmap(1048576)
        map_status = p as i64
    if map_status < 0:
        put_errnl("volt: mmap failed")
        panic("mmap")
    str_arena_ptr = p
    str_arena_size = 1048576
    str_arena_used = 0

str_arena_init()
