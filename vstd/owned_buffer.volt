use bytes

# Do not let an older compiler treat this as a freely copyable record.
const __VOLT_OWNED_BUFFER_CHECK: __VoltOwnedBufferV1 = 0

struct OwnedBuffer:
    storage: ByteBuffer

# Non-panicking allocation: Err carries the positive errno of the failed
# allocation (ENOMEM from mmap for a fresh, zeroed buffer).
fn owned_buffer_try_new(initial: string) -> Result<OwnedBuffer, i32>:
    let storage: ByteBuffer
    let count: i64 = str_len(initial)
    let failed: i32 = 0
    unsafe:
        let reserved: i64 = bytes_reserve(&storage, count)
        if reserved < 0:
            failed = (0 - reserved) as i32
        else:
            let source = initial as ptr<char>
            for i in 0..count: storage.data[i] = source[i] as u8
            storage.len = count
    if failed != 0: return Err(failed)
    return Ok(OwnedBuffer(storage))

fn owned_buffer_new(initial: string) -> OwnedBuffer:
    match owned_buffer_try_new(initial):
        Ok(buffer): return buffer
        Err(code): panic("OwnedBuffer allocation failed\n")
    # Unreachable: the Err arm above panics. The compiler only accepts an
    # explicit return as proof that a function exits, so close the match off.
    while true:
        return owned_buffer_new("")

# Adopt the bytes of an already filled ByteBuffer without copying them. The
# source is zeroed in place: a second call (or any later use of the source)
# sees an empty buffer instead of producing a second owner. Unsafe because
# only the caller can guarantee that no other raw copy of the source's
# data/len/cap triple still aliases the same mapping.
unsafe fn owned_buffer_from_bytes(storage: ptr<ByteBuffer>) -> OwnedBuffer:
    let moved: ByteBuffer
    moved.data = storage.data
    moved.len = storage.len
    moved.cap = storage.cap
    bytes_init(storage)
    return OwnedBuffer(moved)

# &owner is accepted only as an immediate argument to these readers.
fn owned_buffer_len(buffer: ptr<OwnedBuffer>) -> i64:
    unsafe: return buffer.storage.len

fn owned_buffer_get(buffer: ptr<OwnedBuffer>, index: i64) -> u8:
    unsafe: return bytes_get(&buffer.storage, index)

# All bytes of the buffer as a slice, without copying. The slice borrows the
# owner until the end of its block: while it is alive the buffer cannot be
# moved, and the slice cannot outlive the buffer's scope.
fn owned_buffer_bytes(buffer: ptr<OwnedBuffer>) -> []u8 from buffer:
    unsafe:
        return buffer.storage.data[0..buffer.storage.len]

fn __volt_owned_buffer_drop(buffer: ptr<OwnedBuffer>):
    unsafe:
        if bytes_free(&buffer.storage) < 0: panic("OwnedBuffer release failed\n")
