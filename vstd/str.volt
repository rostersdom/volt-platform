# VOLT strings are validated NUL-terminated values; raw byte pointers stay unsafe.

use io

const STR_ARENA_BYTES: i64 = 1048576

struct StrArena:
    data: ptr<char>
    used: i64

unsafe native fn str_arena_state() -> ptr<StrArena>:
{
    .lcomm VOLT_str_arena_state, 16
    lea rax, [rip + VOLT_str_arena_state]
}

# Allocation reserves a disjoint range; copying happens outside the lock.
unsafe native fn str_arena_lock():
{
    .lcomm VOLT_str_arena_guard, 4
.Lstr_arena_retry:
    mov eax, 1
    xchg dword ptr [rip + VOLT_str_arena_guard], eax
    test eax, eax
    jz .Lstr_arena_acquired
    pause
    jmp .Lstr_arena_retry
.Lstr_arena_acquired:
}

unsafe native fn str_arena_unlock():
{
    mov dword ptr [rip + VOLT_str_arena_guard], 0
}

unsafe fn str_arena_new(need: i64) -> ptr<char>:
    str_arena_lock()
    defer str_arena_unlock()
    let arena: ptr<StrArena> = str_arena_state()
    if arena.data == (0 as ptr<char>) or need < 0 or need >= STR_ARENA_BYTES - arena.used:
        put_errnl("volt: arena full")
        panic("arena")
    let q: ptr<char> = arena.data + arena.used
    arena.used += need + 1
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
    unsafe:
        str_arena_lock()
        defer str_arena_unlock()
        let arena: ptr<StrArena> = str_arena_state()
        if arena.data != (0 as ptr<char>): return
        let p: ptr<char> = mmap(STR_ARENA_BYTES)
        if p as i64 < 0:
            put_errnl("volt: mmap failed")
            panic("mmap")
        arena.data = p

str_arena_init()
