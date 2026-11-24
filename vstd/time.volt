# Linux x86-64 monotonic clock, using the kernel syscall directly.
const CLOCK_MONOTONIC: i64 = 1

unsafe native fn __volt_time_clock_gettime(clock_id: i64, tp: ptr<i64>) -> i64:
{
    mov rax, 228
    syscall
}

fn monotonic_ms() -> Result<i64, i32>:
    let ts: [2]i64
    let status: i64
    unsafe: status = __volt_time_clock_gettime(CLOCK_MONOTONIC, &ts[0])
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(ts[0] * 1000 + ts[1] / 1000000)
