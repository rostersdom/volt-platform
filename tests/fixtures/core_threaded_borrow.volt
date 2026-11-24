use borrow_buffer
use channel

struct ChannelJob:
    request: ChannelI64
    reply: ChannelI64

fn stack_sum(a: i64, b: i64, c: i64, d: i64, e: i64, f: i64, g: i64) -> i64:
    return a + b + c + d + e + f + g

fn receive(channel: ChannelI64) -> i64:
    match channel_i64_recv(channel):
        Ok(item): return item
        Err(error): panic("receive")
    return 0

unsafe fn update_buffer(data: ptr<char>) -> ptr<char>:
    let job: ptr<ChannelJob> = data as ptr<ChannelJob>
    let last = receive(job.request)
    let sum = callback(stack_sum)
    let item = sum(1, 2, 3, 4, 5, 6, last)
    if item != 28: panic("indirect call lost a stack argument")
    let initial: [2]i64 = [12, 30]
    let owner = borrow_buffer_new(initial[0..2])
    if borrow_buffer_len(owner) != 2: panic("create buffer")
    let alias = owner
    if true:
        let view = borrow_buffer_read(owner)
        if borrow_buffer_set(alias, 0, item) != -16: panic("write during borrow")
        if borrow_buffer_reserve(alias, 128) != -16: panic("reserve during borrow")
        if borrow_buffer_push(alias, item) != -16: panic("append during borrow")
        if borrow_buffer_drop(alias) != -16: panic("drop during borrow")
        if buffer_read_len(view) != 2 or buffer_read_get(view, 0) != 12 or buffer_read_get(view, 1) != 30:
            panic("borrowed buffer changed")
    if borrow_buffer_push(alias, item) != 0: panic("append after borrow failed")
    if true:
        let view = borrow_buffer_read(owner)
        if buffer_read_len(view) != 3: panic("append missing")
        if channel_i64_send(job.reply, buffer_read_get(view, 2)) != 0: panic("send reply")
    if borrow_buffer_drop(owner) != 0: panic("last borrow was not released")
    return data

fn main() -> i64:
    let request = channel_i64_new()
    let reply = channel_i64_new()
    let job = ChannelJob(request, reply)
    let slot: Thread
    unsafe:
        if thread_spawn(&slot, callback(update_buffer), (&job) as ptr<char>) != 0: panic("spawn")
    if channel_i64_send(request, 7) != 0: panic("send request")
    if receive(reply) != 28: panic("wrong reply")
    unsafe:
        match thread_join(&slot):
            Ok(data):
                if data != ((&job) as ptr<char>): panic("worker returned wrong state")
            Err(error): panic("join")
    if channel_i64_drop(request) != 0 or channel_i64_drop(reply) != 0: panic("drop channels")
    print("threaded borrow and ABI ok")
    return 0
