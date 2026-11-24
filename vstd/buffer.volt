use bytes

# A zero-initialized Buffer<T> owns its allocation. Reserve may invalidate pointers.
struct Buffer<T>:
    storage: ByteBuffer

unsafe fn buffer_reserve<T>(buf: ptr<Buffer<T>>, count: i64) -> i64:
    let width: i64 = sizeof(T)
    if count < 0 or width < 1: return -22
    if count > 9223372036854775807 / width: return -75
    return bytes_reserve(&buf.storage, count * width)

unsafe fn buffer_data<T>(buf: ptr<Buffer<T>>) -> ptr<T>:
    return buf.storage.data as ptr<T>

unsafe fn buffer_len<T>(buf: ptr<Buffer<T>>) -> i64:
    let width: i64 = sizeof(T)
    if width == 0: return 0
    return buf.storage.len / width

unsafe fn buffer_capacity<T>(buf: ptr<Buffer<T>>) -> i64:
    let width: i64 = sizeof(T)
    if width == 0: return 0
    return buf.storage.cap / width

unsafe fn buffer_push<T>(buf: ptr<Buffer<T>>, value: T) -> i64:
    let used: i64 = buffer_len(buf)
    if used == 9223372036854775807: return -75
    let status: i64 = buffer_reserve(buf, used + 1)
    if status < 0: return status
    let data: ptr<T> = buffer_data(buf)
    data[used] = value
    buf.storage.len += sizeof(T)
    return 0

unsafe fn buffer_at<T>(buf: ptr<Buffer<T>>, index: i64) -> ptr<T>:
    if index < 0 or index >= buffer_len(buf): panic("Buffer index out of bounds\n")
    return buffer_data(buf) + index

unsafe fn buffer_free<T>(buf: ptr<Buffer<T>>) -> i64:
    return bytes_free(&buf.storage)
