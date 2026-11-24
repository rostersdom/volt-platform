# ══════════════════════════════════════════════════════════
# VOLT std/bytes — ByteBuffer для Linux x86-64.
# ══════════════════════════════════════════════════════════

struct ByteBuffer:
    data: ptr<u8>
    len: i64
    cap: i64

# shortcut: initialize a fresh or freed buffer only; use bytes_free before reinitializing an active mapping.
unsafe fn bytes_init(buf: ptr<ByteBuffer>):
    buf.data = 0 as ptr<u8>
    buf.len = 0
    buf.cap = 0

unsafe fn bytes_reserve(buf: ptr<ByteBuffer>, need: i64) -> i64:
    if need < 0 or buf.len < 0 or buf.cap < 0 or buf.len > buf.cap:
        return -22
    if buf.cap == 0:
        if buf.data != (0 as ptr<u8>):
            return -22
    if buf.cap > 0:
        if buf.data == (0 as ptr<u8>):
            return -22
    if need <= buf.cap:
        return 0

    let new_cap: i64 = buf.cap
    if new_cap == 0:
        new_cap = 8
    while new_cap < need:
        if new_cap > 9223372036854775807 / 2:
            new_cap = need
        else:
            new_cap = new_cap * 2

    let mapped: ptr<char> = mmap(new_cap)
    let map_status: i64 = mapped as i64
    if map_status < 0:
        return map_status
    let new_data: ptr<u8> = mapped as ptr<u8>
    let i: i64 = 0
    while i < buf.len:
        new_data[i] = buf.data[i]
        i = i + 1

    if buf.cap > 0:
        let unmap_status: i64 = munmap(buf.data as ptr<char>, buf.cap)
        if unmap_status < 0:
            munmap(mapped, new_cap)
            return unmap_status
    buf.data = new_data
    buf.cap = new_cap
    return 0

unsafe fn bytes_push(buf: ptr<ByteBuffer>, value: u8) -> i64:
    if buf.len < 0:
        return -22
    if buf.len == 9223372036854775807:
        return -75
    let status: i64 = bytes_reserve(buf, buf.len + 1)
    if status < 0:
        return status
    buf.data[buf.len] = value
    buf.len = buf.len + 1
    return 0

# Reserve space for the next read, including one byte to detect overflow at the limit.
unsafe fn bytes_read_room(buf: ptr<ByteBuffer>, limit: i64) -> i64:
    if limit < 0 or limit == 9223372036854775807 or buf.len < 0 or buf.len > limit: return -22
    let amount: i64 = min(4096, limit - buf.len + 1)
    let status: i64 = bytes_reserve(buf, buf.len + amount)
    if status < 0: return status
    return amount

unsafe fn bytes_get(buf: ptr<ByteBuffer>, index: i64) -> u8:
    if index < 0 or index >= buf.len:
        panic("ByteBuffer index")
    return buf.data[index]

unsafe fn bytes_set(buf: ptr<ByteBuffer>, index: i64, value: u8):
    if index < 0 or index >= buf.len:
        panic("ByteBuffer index")
    buf.data[index] = value

unsafe fn bytes_free(buf: ptr<ByteBuffer>) -> i64:
    if buf.len < 0 or buf.cap < 0 or buf.len > buf.cap:
        return -22
    if buf.cap == 0:
        if buf.data != (0 as ptr<u8>):
            return -22
        buf.len = 0
        return 0
    if buf.data == (0 as ptr<u8>):
        return -22
    let status: i64 = munmap(buf.data as ptr<char>, buf.cap)
    if status < 0:
        return status
    bytes_init(buf)
    return 0

# При ошибке чтения оставляет уже прочитанные байты и возвращает errno.
unsafe fn bytes_read_file(buf: ptr<ByteBuffer>, path: string) -> i64:
    let status: i64 = bytes_reserve(buf, buf.cap)
    if status < 0:
        return status
    let fd: i64 = open(path, 0, 0)
    if fd < 0:
        return fd

    buf.len = 0
    let result: i64 = 0
    let done: bool = false
    while not done:
        if buf.len == 9223372036854775807:
            result = -75
            done = true
        else:
            let room: i64 = 9223372036854775807 - buf.len
            let amount: i64 = 4096
            if room < amount:
                amount = room
            result = bytes_reserve(buf, buf.len + amount)
            if result < 0:
                done = true
            else:
                let count: i64 = buf.cap - buf.len
                if count > amount:
                    count = amount
                let n: i64 = read(fd, buf.data + buf.len, count)
                if n != -4:
                    if n < 0:
                        result = n
                        done = true
                    else:
                        if n == 0:
                            done = true
                        else:
                            buf.len = buf.len + n

    let close_status: i64 = close(fd)
    if result == 0 and close_status < 0:
        return close_status
    return result
