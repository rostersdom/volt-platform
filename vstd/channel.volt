use thread

const CHANNEL_EBADF: i32 = 9
const CHANNEL_EAGAIN: i32 = 11
const CHANNEL_EPIPE: i32 = 32
const CHANNEL_I64_LIMIT: i64 = 64
const CHANNEL_MAX_GENERATION: u64 = 288230376151711743

# Copies refer to the same channel. The token is not a pointer or a capability.
struct ChannelI64:
    token: u64

struct ChannelI64Slot:
    generation: u64
    value: i64
    live: bool
    closed: bool
    full: bool
    changed: Condition

struct ChannelI64Registry:
    once: i32
    lock: Mutex
    slots: [64]ChannelI64Slot

unsafe extern fn pthread_once(control: ptr<i32>, initialize: fnptr<()>) -> i32

unsafe native fn __volt_channel_i64_registry() -> ptr<ChannelI64Registry>:
{
    .lcomm VOLT_channel_i64_state, 8192
    lea rax, [rip + VOLT_channel_i64_state]
}

unsafe fn __volt_channel_i64_init():
    if sizeof(ChannelI64Registry) > 8192: panic("channel registry size")
    let registry: ptr<ChannelI64Registry> = __volt_channel_i64_registry()
    if mutex_init(&registry.lock) != 0: panic("channel mutex initialization failed")

unsafe fn __volt_channel_i64_lock() -> ptr<ChannelI64Registry>:
    let registry: ptr<ChannelI64Registry> = __volt_channel_i64_registry()
    if pthread_once(&registry.once, callback(__volt_channel_i64_init)) != 0:
        panic("channel registry initialization failed")
    if mutex_lock(&registry.lock) != 0: panic("channel mutex lock failed")
    return registry

unsafe fn __volt_channel_i64_unlock(registry: ptr<ChannelI64Registry>):
    if mutex_unlock(&registry.lock) != 0: panic("channel mutex unlock failed")

unsafe fn __volt_channel_i64_slot(registry: ptr<ChannelI64Registry>, channel: ChannelI64) -> ptr<ChannelI64Slot>:
    let count: u64 = CHANNEL_I64_LIMIT as u64
    let slot: ptr<ChannelI64Slot> = &registry.slots[(channel.token % count) as i64]
    if not slot.live or slot.generation != channel.token / count: return 0 as ptr<ChannelI64Slot>
    return slot

unsafe fn __volt_channel_i64_wait(registry: ptr<ChannelI64Registry>, slot: ptr<ChannelI64Slot>, channel: ChannelI64) -> ptr<ChannelI64Slot>:
    if condition_wait(&slot.changed, &registry.lock) != 0: panic("channel wait failed")
    # A drop and a new allocation may both have taken place during the wait.
    return __volt_channel_i64_slot(registry, channel)

unsafe fn __volt_channel_i64_notify(slot: ptr<ChannelI64Slot>):
    if condition_broadcast(&slot.changed) != 0: panic("channel broadcast failed")

# shortcut: one pending value and 64 live slots until a larger queue is needed.
# The zero handle indicates that the registry is full.
fn channel_i64_new() -> ChannelI64:
    unsafe:
        let registry = __volt_channel_i64_lock()
        defer __volt_channel_i64_unlock(registry)
        for i in 0..CHANNEL_I64_LIMIT:
            let slot: ptr<ChannelI64Slot> = &registry.slots[i]
            if not slot.live and slot.generation < CHANNEL_MAX_GENERATION:
                # The condition stays initialized for the process: old waiters
                # can still be reacquiring the registry lock after a drop.
                if slot.generation == 0 and condition_init(&slot.changed) != 0:
                    panic("channel condition initialization failed")
                slot.generation += 1
                slot.live = true
                slot.closed = false
                slot.full = false
                return ChannelI64(slot.generation * (CHANNEL_I64_LIMIT as u64) + (i as u64))
    return ChannelI64(0)

unsafe fn __volt_channel_i64_send(channel: ChannelI64, value: i64, wait: bool) -> i32:
    let registry = __volt_channel_i64_lock()
    defer __volt_channel_i64_unlock(registry)
    let slot = __volt_channel_i64_slot(registry, channel)
    while wait and slot != (0 as ptr<ChannelI64Slot>) and not slot.closed and slot.full:
        slot = __volt_channel_i64_wait(registry, slot, channel)
    if slot == (0 as ptr<ChannelI64Slot>): return CHANNEL_EBADF
    if slot.closed: return CHANNEL_EPIPE
    if slot.full: return CHANNEL_EAGAIN
    slot.value = value
    slot.full = true
    __volt_channel_i64_notify(slot)
    return 0

fn channel_i64_send(channel: ChannelI64, value: i64) -> i32:
    unsafe: return __volt_channel_i64_send(channel, value, true)

fn channel_i64_try_send(channel: ChannelI64, value: i64) -> i32:
    unsafe: return __volt_channel_i64_send(channel, value, false)

unsafe fn __volt_channel_i64_recv(channel: ChannelI64, wait: bool) -> Result<i64, i32>:
    let registry = __volt_channel_i64_lock()
    defer __volt_channel_i64_unlock(registry)
    let slot = __volt_channel_i64_slot(registry, channel)
    while wait and slot != (0 as ptr<ChannelI64Slot>) and not slot.closed and not slot.full:
        slot = __volt_channel_i64_wait(registry, slot, channel)
    if slot == (0 as ptr<ChannelI64Slot>): return Err(CHANNEL_EBADF)
    if slot.full:
        let value: i64 = slot.value
        slot.full = false
        __volt_channel_i64_notify(slot)
        return Ok(value)
    if slot.closed: return Err(CHANNEL_EPIPE)
    return Err(CHANNEL_EAGAIN)

fn channel_i64_recv(channel: ChannelI64) -> Result<i64, i32>:
    unsafe: return __volt_channel_i64_recv(channel, true)

fn channel_i64_try_recv(channel: ChannelI64) -> Result<i64, i32>:
    unsafe: return __volt_channel_i64_recv(channel, false)

# Close prevents new sends but preserves a pending value. Drop discards it and
# invalidates every copy of the handle, even if the slot is reused.
fn channel_i64_close(channel: ChannelI64) -> i32:
    unsafe:
        let registry = __volt_channel_i64_lock()
        defer __volt_channel_i64_unlock(registry)
        let slot = __volt_channel_i64_slot(registry, channel)
        if slot == (0 as ptr<ChannelI64Slot>): return CHANNEL_EBADF
        if not slot.closed:
            slot.closed = true
            __volt_channel_i64_notify(slot)
        return 0

fn channel_i64_drop(channel: ChannelI64) -> i32:
    unsafe:
        let registry = __volt_channel_i64_lock()
        defer __volt_channel_i64_unlock(registry)
        let slot = __volt_channel_i64_slot(registry, channel)
        if slot == (0 as ptr<ChannelI64Slot>): return CHANNEL_EBADF
        slot.live = false
        __volt_channel_i64_notify(slot)
        return 0
