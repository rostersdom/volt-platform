# Linux x86-64 poll readiness, without libc.
const POLLIN: i64 = 0x0001
const POLLPRI: i64 = 0x0002
const POLLOUT: i64 = 0x0004
const POLLERR: i64 = 0x0008
const POLLHUP: i64 = 0x0010
const POLLNVAL: i64 = 0x0020
const CLOCK_MONOTONIC: i64 = 1
const TFD_CLOEXEC: i64 = 0x80000
const TFD_NONBLOCK: i64 = 0x800
const TFD_TIMER_ABSTIME: i64 = 0x0001

struct EventPollFd:
    fd: i32
    events: i16
    revents: i16

struct EventTimerSpec:
    interval_sec: i64
    interval_nsec: i64
    value_sec: i64
    value_nsec: i64

unsafe native fn __volt_event_poll(fds: ptr<EventPollFd>, nfds: i64, timeout_ms: i64) -> i64:
{
    mov rax, 7
    syscall
}

# Internal raw pipe helper used by deterministic tests and module clients.
unsafe native fn __volt_event_pipe2(fds: ptr<i32>, flags: i64) -> i64:
{
    mov rax, 293
    syscall
}

unsafe native fn __volt_event_timerfd_create(clock_id: i64, flags: i64) -> i64:
{
    mov rax, 283
    syscall
}

unsafe native fn __volt_event_timerfd_settime(fd: i64, flags: i64, new_value: ptr<EventTimerSpec>, old_value: ptr<EventTimerSpec>) -> i64:
{
    mov r10, rcx
    mov rax, 286
    syscall
}

# shortcut: immutable slices are the only slice type; use unsafe until mutable slices exist.
unsafe fn poll(fds: []EventPollFd, timeout_ms: i64) -> Result<i64, i32>:
    if timeout_ms < -1 or timeout_ms > 2147483647:
        return Err(22 as i32)
    let status: i64
    if len(fds) == 0:
        unsafe: status = __volt_event_poll(0 as ptr<EventPollFd>, 0, timeout_ms)
    else:
        unsafe: status = __volt_event_poll(&fds[0], len(fds), timeout_ms)
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(status)

fn poll_readable(fd: i64, timeout_ms: i64) -> Result<i64, i32>:
    if fd < 0 or fd > 2147483647:
        return Err(22 as i32)
    if timeout_ms < -1 or timeout_ms > 2147483647:
        return Err(22 as i32)
    let pfd: EventPollFd = EventPollFd(fd as i32, POLLIN as i16, 0 as i16)
    let status: i64
    unsafe: status = __volt_event_poll(&pfd, 1, timeout_ms)
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(pfd.revents as i64)

unsafe fn timer_create() -> Result<i64, i32>:
    let status: i64 = __volt_event_timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK)
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(status)

unsafe fn timer_set(fd: i64, first_ms: i64, interval_ms: i64) -> Result<i64, i32>:
    const TIMER_MAX_MS: i64 = 9223372036854775
    if first_ms < 0 or first_ms > TIMER_MAX_MS or interval_ms < 0 or interval_ms > TIMER_MAX_MS:
        return Err(22 as i32)
    let spec: EventTimerSpec = EventTimerSpec(
        interval_ms / 1000,
        (interval_ms % 1000) * 1000000,
        first_ms / 1000,
        (first_ms % 1000) * 1000000
    )
    let status: i64 = __volt_event_timerfd_settime(fd, 0, &spec, 0 as ptr<EventTimerSpec>)
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(status)

unsafe fn timer_read(fd: i64) -> Result<u64, i32>:
    let expirations: [1]u64
    let status: i64 = read(fd, (&expirations[0]) as ptr<char>, 8)
    if status < 0:
        return Err((0 - status) as i32)
    if status != 8:
        return Err(5 as i32)
    return Ok(expirations[0])

unsafe fn timer_close(fd: i64) -> Result<i64, i32>:
    let status: i64 = close(fd)
    if status < 0:
        return Err((0 - status) as i32)
    return Ok(status)
