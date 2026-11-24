# Вызов функций из libc по системному C ABI.
link "-lc"

unsafe extern fn strlen(s: ptr<char>) -> u64
extern fn abs(n: i32) -> i32

fn main() -> i64:
    let negative: i32 = -7
    unsafe:
        print(strlen("VOLT" as ptr<char>), abs(negative))
    return 0
