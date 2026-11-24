# extern: сырой символ из runtime (линкуется автоматически)
unsafe extern fn VOLT_rt_write(fd: i64, buf: ptr<char>, n: i64) -> i64

# native: тело — сырой ассемблер (Intel), параметры по SysV ABI (rdi, rsi, ...)
native fn double_it(x: i64) -> i64:
{
    mov rax, rdi
    add rax, rax
}

fn main() -> i64:
    let s: string = "extern works\n"
    let written: i64
    unsafe:
        written = VOLT_rt_write(1, s as ptr<char>, 13)
        print(double_it(21))
    if written != 13:
        panic("write failed")
    return 0
