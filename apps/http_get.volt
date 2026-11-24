# Start a local HTTP server separately, then pass its port as an argument
# by editing the constant below. This demo intentionally uses loopback.
use http

fn main() -> i64:
    unsafe:
        let response: ByteBuffer
        bytes_init(&response)
        let result: i64 = http_get_ipv4("127.0.0.1", 8080, "/", &response)
        if result < 0:
            put_err("http_get_ipv4 failed with errno ")
            put_int(0 - result)
            nl()
            bytes_free(&response)
            return 1
        let p: ptr<char> = response.data as ptr<char>
        put_str("Raw HTTP response (")
        put_int(result)
        put_str(" bytes):\n")
        unsafe:
            write_all(1, p, response.len)
        bytes_free(&response)
    return 0
