use channel
link "-L. -lvolt_channel_waiters"

extern fn volt_channel_wait_probe()
extern fn volt_channel_wait_reset()

unsafe fn send_until_closed(data: ptr<char>) -> ptr<char>:
    let target = *(data as ptr<ChannelI64>)
    if channel_i64_send(target, 99) != CHANNEL_EPIPE: panic("close did not stop sender")
    return data

unsafe fn recv_until_dropped(data: ptr<char>) -> ptr<char>:
    let target = *(data as ptr<ChannelI64>)
    match channel_i64_recv(target):
        Ok(value): panic("stale receiver consumed a message")
        Err(error):
            if error != CHANNEL_EBADF: panic("drop did not invalidate receiver")
    return data

unsafe fn join_waiter(slot: ptr<Thread>, context: ptr<char>):
    match thread_join(slot):
        Ok(data):
            if data != context: panic("unexpected worker result")
        Err(error): panic("join worker")

unsafe:
    let target = channel_i64_new()
    let slot: Thread
    let context = (&target) as ptr<char>
    if channel_i64_try_send(target, 42) != 0: panic("fill target")
    if thread_spawn(&slot, callback(send_until_closed), context) != 0: panic("spawn sender")
    volt_channel_wait_probe()
    if channel_i64_close(target) != 0: panic("close target")
    join_waiter(&slot, context)
    match channel_i64_try_recv(target):
        Ok(value):
            if value != 42: panic("lost pending value at close")
        Err(error): panic("could not drain closed channel")
    if channel_i64_drop(target) != 0: panic("drop target")

    target = channel_i64_new()
    volt_channel_wait_reset()
    if thread_spawn(&slot, callback(recv_until_dropped), context) != 0: panic("spawn receiver")
    volt_channel_wait_probe()
    if channel_i64_drop(target) != 0: panic("invalidate target")
    join_waiter(&slot, context)
    let replacement = channel_i64_new()
    if channel_i64_try_send(replacement, 7) != 0: panic("send new value")
    match channel_i64_recv(target):
        Ok(value): panic("stale receiver consumed a replacement message")
        Err(error):
            if error != CHANNEL_EBADF: panic("stale receiver error")
    match channel_i64_try_recv(replacement):
        Ok(value):
            if value != 7: panic("replacement changed")
        Err(error): panic("replacement lost its value")
    if channel_i64_drop(replacement) != 0: panic("drop replacement")
    print("blocked channel waiters woke up")
