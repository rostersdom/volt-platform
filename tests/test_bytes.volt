use bytes

fn main() -> i64:
    unsafe:
        let buf: ByteBuffer
        bytes_init(&buf)
        let status: i64 = bytes_reserve(&buf, 4)
        print(status, buf.cap >= 4)

        let i: i64 = 0
        while i < 128:
            status = bytes_push(&buf, (i + 1) as u8)
            if status < 0:
                print("push failed", status)
                return 1
            i = i + 1
        status = bytes_push(&buf, 0 as u8)
        print(status, buf.len, buf.cap >= buf.len, bytes_get(&buf, 0) as i64, bytes_get(&buf, 128) as i64)
        bytes_set(&buf, 64, 0 as u8)
        print(bytes_get(&buf, 64) as i64)

        status = bytes_read_file(&buf, "tests/expected/hello.txt")
        if status < 0:
            print("read failed", status)
            return 1
        print(status, buf.len, bytes_get(&buf, 0) as i64, bytes_get(&buf, buf.len - 1) as i64)
        status = bytes_free(&buf)
        print(status, buf.len, buf.cap)
        return 0
