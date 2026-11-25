# Linux x86-64 readiness and nonblocking stream I/O, without libc.
# poll may wait for the requested timeout; try_read/try_write never wait for
# readiness. These are primitives, not async/await or asynchronous disk I/O.
# Err contains a positive errno.
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
const EVENT_EAGAIN: i32 = 11

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

# The kernel writes revents only within the borrowed range and does not retain it.
fn poll(fds: []mut EventPollFd, timeout_ms: i64) -> Result<i64, i32>:
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

# fd must be a live timerfd from timer_create.
unsafe fn timer_read(fd: i64) -> Result<u64, i32>:
    let expirations: [1]u64
    let status: i64 = read(fd, (&expirations[0]) as ptr<char>, 8)
    if status < 0:
        return Err((0 - status) as i32)
    if status != 8:
        return Err(5 as i32)
    return Ok(expirations[0])

unsafe fn timer_close(fd: i64) -> Result<i64, i32>:
    return event_close(fd)

struct EventStreamPair:
    first: i64
    second: i64

unsafe native fn __volt_event_socketpair(fds: ptr<i32>) -> i64:
{
    mov r10, rdi
    mov edi, 1          # AF_UNIX
    mov esi, 0x80801    # SOCK_STREAM | SOCK_NONBLOCK | SOCK_CLOEXEC
    xor edx, edx
    mov eax, 53
    syscall
}

unsafe native fn __volt_event_recv(fd: i64, buffer: ptr<u8>, length: i64) -> i64:
{
    mov r10d, 0x40     # MSG_DONTWAIT
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 45        # recvfrom without a source address
    syscall
}

unsafe native fn __volt_event_send(fd: i64, buffer: ptr<u8>, length: i64) -> i64:
{
    mov r10d, 0x4040   # MSG_DONTWAIT | MSG_NOSIGNAL
    xor r8d, r8d
    xor r9d, r9d
    mov eax, 44        # sendto without a destination address
    syscall
}

# Create two owned ends of a local bidirectional byte stream (NONBLOCK and CLOEXEC).
# out must point to writable storage not owning any live descriptors. If creation
# fails, out is unchanged. On success, close each end once with event_close.
unsafe fn stream_pair(out: ptr<EventStreamPair>) -> Result<i64, i32>:
    if out == (0 as ptr<EventStreamPair>): return Err(22 as i32)
    let fds: [2]i32
    let status: i64 = __volt_event_socketpair(&fds[0])
    if status < 0: return Err((0 - status) as i32)
    out.first = fds[0] as i64
    out.second = fds[1] as i64
    return Ok(status)

fn __volt_event_io_status(status: i64) -> Result<i64, i32>:
    if status < 0: return Err((0 - status) as i32)
    return Ok(status)

# One attempt on a connected stream socket, including a blocking-mode socket.
# The buffer must be writable for length > 0 bytes. Ok(n) counts bytes (0 is
# EOF); a POLLHUP can arrive while there are still bytes to read. On
# Err(EVENT_EAGAIN), wait for POLLIN with poll. Short counts and other positive
# errnos (including EINTR) are returned as-is. Not for pipes/timerfds/files.
unsafe fn try_read(fd: i64, buffer: ptr<u8>, length: i64) -> Result<i64, i32>:
    if fd < 0 or fd > 2147483647: return Err(9 as i32)
    if length <= 0 or buffer == (0 as ptr<u8>): return Err(22 as i32)
    return __volt_event_io_status(__volt_event_recv(fd, buffer, length))

# Like try_read, with a readable source buffer and POLLOUT for retry. A closed
# peer can return EPIPE, but this call does not raise SIGPIPE or change signal handling.
unsafe fn try_write(fd: i64, buffer: ptr<u8>, length: i64) -> Result<i64, i32>:
    if fd < 0 or fd > 2147483647: return Err(9 as i32)
    if length <= 0 or buffer == (0 as ptr<u8>): return Err(22 as i32)
    return __volt_event_io_status(__volt_event_send(fd, buffer, length))

# Release an owned fd. Do not retry close on Linux even after EINTR: the
# descriptor number may already have been reused.
unsafe fn event_close(fd: i64) -> Result<i64, i32>:
    if fd < 0 or fd > 2147483647: return Err(9 as i32)
    return __volt_event_io_status(close(fd))
