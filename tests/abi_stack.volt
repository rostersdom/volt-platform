enum Mark:
    Stop = 4294967367

struct Pair:
    first: i64
    second: i64

unsafe fn mixed(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, small: i8, x0: f64, x1: f32, x2: f64, x3: f32, x4: f64, x5: f32, x6: f64, x7: f32, x8: f32, mid: u16, x9: f64, mark: Mark, flag: bool, item: ptr<i64>):
    print(a, b, c, d, e, f, small, mid, mark as i64, flag, *item)
    print(x0, x1, x2, x3, x4, x5, x6, x7, x8, x9)

fn collect(a: i64, b: i64, c: i64, d: i64, e: i64, pair: Pair, last: i32) -> Pair:
    return Pair(pair.first + a, pair.second + e + last as i64)

# With one GP register left, both slice words go to the stack; tail still gets a GP register.
fn slices(a: i64, b: i64, c: i64, d: i64, e: i64, first: []i64, tail: i64, second: []i64, end: i64):
    print(a, e, len(first), first[1], tail, len(second), second[0], end)

native fn native_slots(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, stack0: i64, x0: f64, x1: f64, x2: f64, x3: f64, x4: f64, x5: f64, x6: f64, x7: f64, stack1: f32, stack2: i64) -> i64:
{
    # Check the compiler's aligned frame and unmodified argument registers.
    mov rax, rbp
    and rax, 15
    add rax, rdi
    add rax, rsi
    add rax, rdx
    add rax, rcx
    add rax, r8
    add rax, r9
    add rax, qword ptr [rbp + 16]
    cvttsd2si r10, xmm0
    add rax, r10
    cvttsd2si r10, xmm7
    add rax, r10
    cvttss2si r10, dword ptr [rbp + 24]
    add rax, r10
    imul rax, rax, 10
    add rax, qword ptr [rbp + 32]
}

let item: i64 = 40
let first_values: [2]i64 = [20, 30]
let second_values: [3]i64 = [0, 40, 50]
let head: []i64 = first_values[0..2]
unsafe:
    mixed(1, 2, 3, 4, 5, 6, -17 as i8, 1.25, -2.5, 3.75, -4.0, 5.5, -6.25, 7.125, -8.625, 9.75, 60000 as u16, -10.25, Mark.Stop, true, &item)
let pair = collect(1, 2, 3, 4, 5, collect(2, 4, 6, 8, 10, Pair(10, 20), -15 as i32), -13 as i32)
print(pair.first, pair.second)
slices(1, 2, 3, 4, 5, head, 91, second_values[1..3], -9)
unsafe: print(native_slots(1, 2, 3, 4, 5, 6, 70, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0, 90.25, 6))
