use thread

unsafe fn write_thread_data(data: ptr<char>) -> ptr<char>:
    *(data as ptr<i64>) = 42
    return data

unsafe fn expect_join_error(slot: ptr<Thread>, expected: i32):
    let result = thread_join(slot)
    match result:
        Ok(value): panic("join unexpectedly succeeded")
        Err(status):
            if status != expected: panic("wrong join error")

unsafe:
    let slot: Thread
    let data: i64
    let address: ptr<char> = (&data) as ptr<char>
    if thread_spawn(&slot, callback(write_thread_data), address) != 11: panic("expected EAGAIN")
    expect_join_error(&slot, THREAD_EINVAL)

    if thread_spawn(&slot, callback(write_thread_data), address) != 0: panic("spawn after EAGAIN")
    expect_join_error(&slot, 35 as i32)  # EDEADLK; the interposer did not join.
    if thread_spawn(&slot, callback(write_thread_data), address) != THREAD_EINVAL:
        panic("failed join must leave the slot occupied")

    let result = thread_join(&slot)
    match result:
        Ok(value):
            if value != address or data != 42: panic("bad result after retrying join")
        Err(status): panic("join retry failed")
    expect_join_error(&slot, THREAD_EINVAL)
    print("pthread errors preserved")
