use http

fn main() -> i64:
    unsafe:
        let response: ByteBuffer
        bytes_init(&response)
        let first: i64 = http_get_ipv4("127.0.0.1", HTTP_TEST_PORT, "/volt", &response)
        if first < 0 or response.len == 0:
            panic("first HTTP request did not populate response")
        print("first", first, response.len)
        let second: i64 = http_get_ipv4("127.0.0.1", 0, "/", &response)
        print("second", second, response.len)
        bytes_free(&response)
    return 0
