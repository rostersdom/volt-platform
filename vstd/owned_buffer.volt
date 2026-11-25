use bytes

# Do not let an older compiler treat this as a freely copyable record.
const __VOLT_OWNED_BUFFER_CHECK: __VoltOwnedBufferV1 = 0

struct OwnedBuffer:
    storage: ByteBuffer

fn owned_buffer_new(initial: string) -> OwnedBuffer:
    let storage: ByteBuffer
    let count: i64 = str_len(initial)
    unsafe:
        if bytes_reserve(&storage, count) < 0: panic("OwnedBuffer allocation failed\n")
        let source = initial as ptr<char>
        for i in 0..count: storage.data[i] = source[i] as u8
        storage.len = count
    return OwnedBuffer(storage)

# Adopt an already filled ByteBuffer without copying its bytes. The caller
# must not touch or free `storage` afterwards; the OwnedBuffer owns it now.
fn owned_buffer_from_bytes(storage: ByteBuffer) -> OwnedBuffer:
    return OwnedBuffer(storage)

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
