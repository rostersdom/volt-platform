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

    let mutex: Mutex
    let condition: Condition
    if mutex_init(&mutex) != 11: panic("mutex init did not return EAGAIN")
    if mutex_try_lock(&mutex) != THREAD_EINVAL or mutex_destroy(&mutex) != THREAD_EINVAL:
        panic("failed mutex init made the slot live")
    if mutex_init(&mutex) != 0: panic("mutex init retry")
    if mutex_destroy(&mutex) != THREAD_EBUSY: panic("mutex destroy did not return EBUSY")
    if mutex_init(&mutex) != THREAD_EINVAL: panic("failed mutex destroy cleared the slot")
    if mutex_try_lock(&mutex) != 0 or mutex_unlock(&mutex) != 0:
        panic("mutex unusable after failed destroy")

    if condition_init(&condition) != 11: panic("condition init did not return EAGAIN")
    if condition_signal(&condition) != THREAD_EINVAL or condition_destroy(&condition) != THREAD_EINVAL:
        panic("failed condition init made the slot live")
    if condition_init(&condition) != 0: panic("condition init retry")
    if condition_destroy(&condition) != THREAD_EBUSY: panic("condition destroy did not return EBUSY")
    if condition_init(&condition) != THREAD_EINVAL: panic("failed condition destroy cleared the slot")
    if condition_signal(&condition) != 0: panic("condition unusable after failed destroy")
    if condition_destroy(&condition) != 0: panic("condition destroy retry")
    if condition_destroy(&condition) != THREAD_EINVAL: panic("condition live after successful destroy")
    if mutex_destroy(&mutex) != 0: panic("mutex destroy retry")
    if mutex_destroy(&mutex) != THREAD_EINVAL: panic("mutex live after successful destroy")
    print("pthread errors preserved")
