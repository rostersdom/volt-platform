use channel

const PRODUCERS: i64 = 4
const MESSAGES: i64 = 500

struct ChannelJob:
    channel: ChannelI64
    start: i64

fn check_recv_error(channel: ChannelI64, expected: i32):
    match channel_i64_try_recv(channel):
        Ok(value): panic("receive unexpectedly succeeded")
        Err(error):
            if error != expected: panic("wrong receive error")

fn check_lifecycle():
    let channel = channel_i64_new()
    let alias = channel
    check_recv_error(channel, CHANNEL_EAGAIN)
    if channel_i64_try_send(channel, -9223372036854775808) != 0: panic("send")
    if channel_i64_try_send(alias, 1) != CHANNEL_EAGAIN: panic("overwrote pending value")
    if channel_i64_close(alias) != 0 or channel_i64_close(channel) != 0: panic("close")
    if channel_i64_try_send(channel, 2) != CHANNEL_EPIPE: panic("send after close")
    match channel_i64_try_recv(alias):
        Ok(value):
            if value != -9223372036854775808: panic("wrong final value")
        Err(error): panic("close discarded pending value")
    check_recv_error(channel, CHANNEL_EPIPE)
    if channel_i64_drop(alias) != 0: panic("drop")
    let reused = channel_i64_new()
    if channel_i64_try_send(channel, 1) != CHANNEL_EBADF: panic("stale send")
    if channel_i64_drop(alias) != CHANNEL_EBADF: panic("stale drop")
    check_recv_error(reused, CHANNEL_EAGAIN)
    if channel_i64_drop(reused) != 0: panic("drop reused")
    let channels: [64]ChannelI64
    for i in 0..len(channels):
        channels[i] = channel_i64_new()
        if channel_i64_try_send(channels[i], i) != 0: panic("registry exhausted too soon")
    let overflow = channel_i64_new()
    check_recv_error(overflow, CHANNEL_EBADF)
    for i in 0..len(channels):
        if channel_i64_drop(channels[i]) != 0: panic("drop channel")

unsafe fn produce(data: ptr<char>) -> ptr<char>:
    let job: ptr<ChannelJob> = data as ptr<ChannelJob>
    for i in 0..MESSAGES:
        if channel_i64_send(job.channel, job.start + i) != 0: panic("producer send failed")
    return data

unsafe fn join_channel_worker(slot: ptr<Thread>, job: ptr<char>):
    match thread_join(slot):
        Ok(data):
            if data != job: panic("unexpected worker result")
        Err(error): panic("join worker")

unsafe fn check_workers():
    let channel = channel_i64_new()
    let slots: [4]Thread
    let jobs: [4]ChannelJob
    for i in 0..PRODUCERS:
        jobs[i] = ChannelJob(channel, i * MESSAGES)
        if thread_spawn(&slots[i], callback(produce), (&jobs[i]) as ptr<char>) != 0: panic("spawn producer")
    let seen: [2000]bool
    let received: i64 = 0
    while received < len(seen):
        match channel_i64_recv(channel):
            Ok(value):
                if value < 0 or value >= len(seen) or seen[value]: panic("corrupt or duplicate message")
                seen[value] = true
                received += 1
            Err(error): panic("consumer receive failed")
    for i in 0..PRODUCERS:
        join_channel_worker(&slots[i], (&jobs[i]) as ptr<char>)
    if channel_i64_close(channel) != 0: panic("close live channel")
    check_recv_error(channel, CHANNEL_EPIPE)
    if channel_i64_drop(channel) != 0: panic("drop live channel")

check_lifecycle()
unsafe: check_workers()
print("channel moved 2000 values exactly once")
