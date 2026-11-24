# Fixed-capacity temporary storage for Linux x86-64, without libc.
const ARENA_EINVAL: i64 = -22
const ARENA_ENOSPC: i64 = -28
const ARENA_EOVERFLOW: i64 = -75
const __VOLT_ARENA_MAX_ADDRESS: i64 = 9223372036854775807

# Start with `let slot: Arena`. Keep it at the same address until drop succeeds.
# Do not copy, overwrite or edit a live slot. The address guard only rejects
# copies at a different address; it is not an ownership or lifetime check.
struct Arena:
    data: ptr<u8>
    capacity: i64
    used: i64
    address: ptr<Arena>

unsafe fn __volt_arena_live(slot: ptr<Arena>) -> bool:
    if slot == (0 as ptr<Arena>) or slot.address != slot: return false
    let base: i64 = slot.data as i64
    if base <= 0 or slot.capacity <= 0 or slot.capacity > __VOLT_ARENA_MAX_ADDRESS - base: return false
    return slot.used >= 0 and slot.used <= slot.capacity

# Init only a zeroed or successfully dropped slot. Statuses are negative errno.
unsafe fn arena_init(slot: ptr<Arena>, capacity: i64) -> i64:
    if slot == (0 as ptr<Arena>) or capacity <= 0: return ARENA_EINVAL
    if slot.address != (0 as ptr<Arena>) or slot.data != (0 as ptr<u8>) or slot.capacity != 0 or slot.used != 0:
        return ARENA_EINVAL

    let mapped: ptr<char> = mmap(capacity)
    let base: i64 = mapped as i64
    if base < 0: return base
    if base == 0 or capacity > __VOLT_ARENA_MAX_ADDRESS - base:
        let status: i64 = munmap(mapped, capacity)
        if status < 0: return status
        return ARENA_EOVERFLOW

    slot.data = mapped as ptr<u8>
    slot.capacity = capacity
    slot.address = slot
    return 0

# Positive size; positive power-of-two alignment. No growth or per-block free.
# Initialize before reading; all addresses expire on reset or successful drop.
unsafe fn arena_alloc(slot: ptr<Arena>, size: i64, alignment: i64) -> Result<ptr<u8>, i64>:
    if not __volt_arena_live(slot) or size <= 0 or alignment <= 0: return Err(ARENA_EINVAL)
    let mask: i64 = alignment - 1
    if (alignment & mask) != 0: return Err(ARENA_EINVAL)
    let left: i64 = slot.capacity - slot.used
    if size > left: return Err(ARENA_ENOSPC)

    # Align the actual address: the mapping can be less aligned than requested.
    let cursor: i64 = (slot.data as i64) + slot.used
    let remainder: i64 = cursor & mask
    let padding: i64 = 0
    if remainder != 0: padding = alignment - remainder
    if padding > left - size: return Err(ARENA_ENOSPC)

    let start: i64 = slot.used + padding
    slot.used = start + size
    return Ok(slot.data + start)

# Keep the mapping; do not clear its bytes or run object cleanup.
unsafe fn arena_reset(slot: ptr<Arena>) -> i64:
    if not __volt_arena_live(slot): return ARENA_EINVAL
    slot.used = 0
    return 0

unsafe fn arena_drop(slot: ptr<Arena>) -> i64:
    if not __volt_arena_live(slot): return ARENA_EINVAL
    let status: i64 = munmap(slot.data as ptr<char>, slot.capacity)
    if status < 0: return status
    slot.data = 0 as ptr<u8>
    slot.capacity = 0
    slot.used = 0
    slot.address = 0 as ptr<Arena>
    return 0
