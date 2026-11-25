use event

fn main() -> i64:
    let first: [2]i32
    let second: [2]i32
    let status: i64
    unsafe: status = __volt_event_pipe2(&first[0], 0)
    if status < 0:
        panic("first pipe2 failed")
    unsafe: status = __volt_event_pipe2(&second[0], 0)
    if status < 0:
        panic("second pipe2 failed")

    let empty_storage: [1]EventPollFd
    let empty: []mut EventPollFd = mut empty_storage[0..0]
    match poll(empty, 0):
        Ok(ready):
            if ready != 0:
                panic("empty poll unexpectedly ready")
        Err(error):
            panic("empty poll failed")
    match poll(empty, -2):
        Ok(ready):
            panic("invalid timeout accepted")
        Err(error):
            if error != 22:
                panic("invalid timeout errno failed")
    match poll(empty, 2147483648):
        Ok(ready):
            panic("large timeout accepted")
        Err(error):
            if error != 22:
                panic("large timeout errno failed")

    let byte: [1]char = ['x']
    unsafe: status = write(second[1], &byte[0], 1)
    if status != 1:
        panic("pipe write failed")

    let entries: [4]EventPollFd
    entries[0] = EventPollFd(-1, 0, 7)
    entries[1] = EventPollFd(first[0] as i32, POLLIN as i16, 1 as i16)
    entries[2] = EventPollFd(second[0] as i32, POLLIN as i16, 0 as i16)
    entries[3] = EventPollFd(-1, 0, 9)
    if true:
        match poll(mut entries[1..3], 0):
            Ok(ready):
                if ready != 1:
                    panic("poll ready count failed")
            Err(error):
                panic("poll readiness failed")
    if entries[0].revents != 7 or entries[3].revents != 9:
        panic("poll wrote outside the slice")
    if (entries[1].revents as i64) != 0:
        panic("first pipe unexpectedly readable")
    if (entries[2].revents as i64) & POLLIN == 0:
        panic("second pipe not readable")

    let timer_fd: i64
    unsafe:
        match timer_create():
            Ok(fd):
                timer_fd = fd
            Err(error):
                panic("timer create failed")
        match timer_set(timer_fd, 10, 0):
            Ok(status):
                if status != 0:
                    panic("timer set returned nonzero")
            Err(error):
                panic("timer set failed")

    let timer_entries: [1]EventPollFd
    timer_entries[0] = EventPollFd(timer_fd as i32, POLLIN as i16, 0 as i16)
    let timer_watched: []mut EventPollFd = mut timer_entries[0..1]
    match poll(timer_watched, -1):
        Ok(ready):
            if ready != 1 or (timer_watched[0].revents as i64) & POLLIN == 0:
                panic("timer poll failed")
        Err(error):
            panic("timer poll failed")
    unsafe:
        match timer_read(timer_fd):
            Ok(expirations):
                if expirations != 1:
                    panic("timer expiration count failed")
            Err(error):
                panic("timer read failed")
        match timer_read(timer_fd):
            Ok(expirations):
                panic("timer read unexpectedly succeeded")
            Err(error):
                if error != 11:
                    panic("timer read errno failed")
        match timer_close(timer_fd):
            Ok(status):
                if status != 0:
                    panic("timer close returned nonzero")
            Err(error):
                panic("timer close failed")

    let received: [1]char
    unsafe: status = read(second[0], &received[0], 1)
    if status != 1 or received[0] != 'x':
        panic("pipe read failed")
    close(first[0])
    close(first[1])
    close(second[0])
    close(second[1])
    print("event ok")
    return 0
