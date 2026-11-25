use event

# Inspect the public descriptors and set a small send buffer to force backpressure.
unsafe native fn fixture_fcntl(fd: i64, command: i64, argument: i64) -> i64:
{
    mov rax, 72
    syscall
}

unsafe native fn fixture_set_sendbuf(fd: i64, size: ptr<i32>) -> i64:
{
    mov r10, rsi
    mov rsi, 1      # SOL_SOCKET
    mov rdx, 7      # SO_SNDBUF
    mov r8, 4
    mov rax, 54
    syscall
}

fn expect_io(result: Result<i64, i32>, expected: i64, label: string):
    match result:
        Ok(value):
            if expected < 0 or value != expected: panic(label)
        Err(error):
            if expected >= 0 or (error as i64) != 0 - expected: panic(label)

fn open_pair() -> EventStreamPair:
    let pair: EventStreamPair
    unsafe: expect_io(stream_pair(&pair), 0, "socketpair failed")
    return pair

unsafe fn check_fd_flags(fd: i64):
    let flags: i64 = fixture_fcntl(fd, 3, 0)  # F_GETFL
    if flags < 0 or flags & 0x800 == 0: panic("missing O_NONBLOCK")
    if fixture_fcntl(fd, 1, 0) != 1: panic("missing FD_CLOEXEC")

# Temporary slices borrow their array to the end of the block, so each
# slice-based call gets its own `if true:` scope and raw-pointer probes run
# outside any borrow.
unsafe fn check_stream():
    expect_io(stream_pair(0 as ptr<EventStreamPair>), -22, "missing pair storage")
    let pair: EventStreamPair = open_pair()
    check_fd_flags(pair.first)
    check_fd_flags(pair.second)
    # Even on a blocking stream socket, try_read must not wait for data.
    if fixture_fcntl(pair.second, 4, 0) != 0: panic("clear O_NONBLOCK")

    let data: [2]u8 = [42, 0]
    let received: [4]u8
    if true: expect_io(try_read(pair.second, mut received[0..4]), -11, "empty stream returns EAGAIN")
    expect_io(poll_readable(pair.second, 0), 0, "empty stream not ready")
    if true: expect_io(try_read(pair.second, mut received[0..0]), -22, "empty read buffer is EINVAL, not EOF")
    if true: expect_io(try_write(pair.first, data[0..0]), -22, "empty write buffer is EINVAL")
    if true: expect_io(try_read(pair.second + 4294967296, mut received[0..4]), -9, "safe try_read checks fd")
    expect_io(try_read_raw(pair.second, &received[0], 0), -22, "zero length is not EOF")
    expect_io(try_write_raw(pair.first, &data[0], -1), -22, "negative length")
    expect_io(try_read_raw(pair.second, 0 as ptr<u8>, 1), -22, "null buffer")
    expect_io(try_read_raw(pair.second + 4294967296, &received[0], 4), -9, "fd must not truncate")

    if true: expect_io(try_write(pair.first, data[0..2]), 2, "write two bytes")
    expect_io(poll_readable(pair.second, 100), POLLIN, "stream becomes readable")
    if true: expect_io(try_read(pair.second, mut received[0..4]), 2, "partial read")
    if received[0] != 42 or received[1] != 0: panic("wrong stream contents")
    if true: expect_io(try_read(pair.second, mut received[0..4]), -11, "drained stream is not EOF")

    if true: expect_io(try_write(pair.first, data[0..1]), 1, "write before closing")
    expect_io(event_close(pair.first), 0, "close first endpoint")
    expect_io(event_close(pair.first), -9, "repeat close without fd reuse")
    if true: expect_io(try_write(pair.first, data[0..1]), -9, "write on closed fd")
    expect_io(poll_readable(pair.first, 0), POLLNVAL, "closed fd not valid")
    expect_io(poll_readable(pair.second, 100), POLLIN | POLLHUP, "hangup with pending data")
    if true: expect_io(try_read(pair.second, mut received[0..4]), 1, "read pending byte after hangup")
    if true: expect_io(try_read(pair.second, mut received[0..4]), 0, "EOF differs from EAGAIN")
    if true: expect_io(try_read(pair.second, mut received[0..4]), 0, "repeat EOF")
    if true: expect_io(try_write(pair.second, data[0..1]), -32, "closed peer yields EPIPE, not SIGPIPE")
    expect_io(event_close(pair.second), 0, "close second endpoint")

    let dir: i64 = open(".", 0, 0)
    if dir < 0: panic("open fixture directory")
    if true: expect_io(try_read(dir, mut received[0..4]), -88, "try_read never uses filesystem read")
    if true: expect_io(try_write(dir, data[0..1]), -88, "try_write never uses filesystem write")
    expect_io(event_close(dir), 0, "close fixture directory")

# Move a large payload through a small send buffer, forcing short counts and
# EAGAIN on both ends; every transferred byte is verified.
unsafe fn check_large_transfer():
    const TRANSFER_SIZE: i64 = 65536
    let pair: EventStreamPair = open_pair()
    let size: i32 = 4096
    if fixture_set_sendbuf(pair.first, &size) != 0: panic("set large transfer send buffer")
    let outgoing: [65536]u8
    let incoming: [65536]u8
    let i: i64 = 0
    while i < TRANSFER_SIZE:
        outgoing[i] = ((i * 31 + 7) % 251) as u8
        i += 1

    # Push until the kernel buffer refuses, then drain until it is empty;
    # both ends must observe EAGAIN at least once.
    let sent: i64 = 0
    let received: i64 = 0
    let write_eagain: i64 = 0
    let read_eagain: i64 = 0
    while received < TRANSFER_SIZE:
        let pushing: i64 = 1
        while pushing == 1 and sent < TRANSFER_SIZE:
            match try_write(pair.first, outgoing[sent..TRANSFER_SIZE]):
                Ok(count):
                    if count <= 0 or count > TRANSFER_SIZE - sent: panic("invalid write count")
                    sent += count
                Err(error):
                    if error != EVENT_EAGAIN: panic("large write failed")
                    write_eagain += 1
                    pushing = 0
        let draining: i64 = 1
        while draining == 1 and received < TRANSFER_SIZE:
            match try_read(pair.second, mut incoming[received..TRANSFER_SIZE]):
                Ok(count):
                    if count <= 0 or count > TRANSFER_SIZE - received: panic("invalid read count")
                    received += count
                Err(error):
                    if error != EVENT_EAGAIN: panic("large read failed")
                    read_eagain += 1
                    draining = 0
    if write_eagain == 0: panic("large write never hit EAGAIN")
    if read_eagain == 0: panic("large read never hit EAGAIN")
    if sent != TRANSFER_SIZE or received != TRANSFER_SIZE: panic("large transfer byte count")

    let j: i64 = 0
    while j < TRANSFER_SIZE:
        if incoming[j] != ((j * 31 + 7) % 251) as u8: panic("large transfer contents")
        j += 1

    # With a non-empty buffer, Ok(0) still means end of stream after shutdown.
    expect_io(event_close(pair.first), 0, "close large transfer writer")
    if true: expect_io(try_read(pair.second, mut incoming[0..1]), 0, "EOF after full transfer")
    expect_io(event_close(pair.second), 0, "close large transfer reader")

unsafe fn check_backpressure():
    let pair: EventStreamPair = open_pair()
    let size: i32 = 4096
    if fixture_set_sendbuf(pair.first, &size) != 0: panic("set send buffer size")
    # Try on a full blocking socket too, to exercise per-call nonblocking send.
    if fixture_fcntl(pair.first, 4, 0) != 0: panic("clear writer O_NONBLOCK")
    let data: [32768]u8
    let sent: i64
    if true:
        match try_write(pair.first, data[0..32768]):
            Ok(count):
                if count <= 0 or count >= 32768: panic("expected partial write")
                sent = count
            Err(error): panic("first write failed")
    if true: expect_io(try_write(pair.first, data[0..32768]), -11, "full stream returns EAGAIN")

    let entries: [1]EventPollFd = [EventPollFd(pair.first as i32, POLLOUT as i16, 0 as i16)]
    let watched: []mut EventPollFd = mut entries[0..1]
    expect_io(poll(watched, 0), 0, "full stream not writable")
    while sent > 0:
        match try_read(pair.second, mut data[0..32768]):
            Ok(count):
                if count <= 0 or count > sent: panic("invalid count while draining stream")
                sent -= count
            Err(error): panic("drain failed")
    expect_io(poll(watched, 100), 1, "drained stream becomes ready")
    if (watched[0].revents as i64) & POLLOUT == 0: panic("drained stream not writable")
    if true: expect_io(try_write(pair.first, data[0..1]), 1, "retry write after readiness")
    expect_io(event_close(pair.first), 0, "close backpressure sender")
    expect_io(event_close(pair.second), 0, "close backpressure receiver")

unsafe fn check_timer():
    let fd: i64
    match timer_create():
        Ok(timer): fd = timer
        Err(error): panic("timer_create failed")
    expect_io(poll_readable(fd, 0), 0, "unarmed timer not ready")
    expect_io(timer_set(fd, 10, 0), 0, "arm one-shot timer")
    expect_io(poll_readable(fd, 500), POLLIN, "timer becomes readable")
    match timer_read(fd):
        Ok(count):
            if count != 1: panic("one-shot expiration count")
        Err(error): panic("timer_read failed")
    match timer_read(fd):
        Ok(count): panic("timer remained ready after drain")
        Err(error):
            if error != 11: panic("drained timer must return EAGAIN")
    expect_io(timer_close(fd), 0, "close timer")

fn main() -> i64:
    unsafe:
        check_stream()
        check_large_transfer()
        check_backpressure()
        check_timer()
    print("event stream ok")
    return 0
