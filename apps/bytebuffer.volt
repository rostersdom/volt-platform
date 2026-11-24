# Run from the repository root with: ./volt apps/bytebuffer.volt --run
use bytes

fn main() -> i64:
    unsafe:
        let buf: ByteBuffer
        bytes_init(&buf)

        let status: i64 = bytes_read_file(&buf, "tests/expected/hello.txt")
        if status < 0:
            put_err("bytes_read_file failed with errno ")
            put_int(0 - status)
            nl()
            bytes_free(&buf)
            return 1

        let i: i64 = 0
        while i < buf.len:
            put_char(bytes_get(&buf, i) as char)
            i += 1

        status = bytes_free(&buf)
        if status < 0:
            put_err("bytes_free failed with errno ")
            put_int(0 - status)
            nl()
            return 1
    return 0
