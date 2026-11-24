use http

fn main() -> i64:
    unsafe:
        let response: ByteBuffer
        bytes_init(&response)
        let status: i64 = http_get_ipv4("127.0.0.1", HTTP_TEST_PORT, "/x?y=1", &response)
        if status < 0:
            bytes_free(&response)
            return 1
        print("HTTP response verified", status)
        bytes_free(&response)
    return 0
