# Bounded plain HTTP/1.0 GET over IPv4/TCP (Linux x86-64 only).
# The timeout covers transport connect/send/read; hostname resolution is separate.
# Existing APIs use a 10-second transport deadline; DNS callers opt in after resolve.
use bytes
use event
use http_frame

const HTTP_CLOCK_MONOTONIC: i64 = 1
const HTTP_DEFAULT_TIMEOUT_MS: i64 = 10000
const HTTP_DEFAULT_RESPONSE_LIMIT: i64 = 65536
const HTTP_SOCK_NONBLOCK: i64 = 0x800
const HTTP_SOCK_CLOEXEC: i64 = 0x80000
const HTTP_POLLIN: i64 = 0x0001
const HTTP_POLLOUT: i64 = 0x0004
const HTTP_SOL_SOCKET: i64 = 1
const HTTP_SO_ERROR: i64 = 4
const HTTP_EINPROGRESS: i64 = -115
const HTTP_EALREADY: i64 = -114
const HTTP_EAGAIN: i64 = -11
const HTTP_TIMEOUT: i64 = -110
const HTTP_CANCELLED: i64 = -125

struct HttpTransfer:
    deadline: i64
    cancel_state: ptr<i32>
    response_bytes: i64
    body_bytes: i64  # 0 keeps the raw EOF-delimited API.
    clean_eof: bool
    accept_gzip: bool

# An aligned x86-64 load pairs with the window's atomic state transition.
unsafe native fn http_load_state(state: ptr<i32>) -> i32:
{
    mov eax, dword ptr [rdi]
}

unsafe native fn __volt_http_socket(domain: i64, kind: i64, protocol: i64) -> i64:
{
    mov rax, 41
    syscall
}

unsafe native fn __volt_http_getsockopt(fd: i64, level: i64, name: i64, value: ptr<i32>, length: ptr<u32>) -> i64:
{
    mov r10, rcx
    mov rax, 55
    syscall
}

unsafe native fn __volt_http_clock(tp: ptr<i64>) -> i64:
{
    mov rsi, rdi
    mov rdi, 1
    mov rax, 228
    syscall
}

unsafe fn http_now_ms() -> i64:
    let ts: [2]i64
    let status: i64 = __volt_http_clock(&ts[0])
    if status < 0: return status
    return ts[0] * 1000 + ts[1] / 1000000

unsafe native fn __volt_http_connect(fd: i64, address: ptr<u8>, length: i64) -> i64:
{
    mov rax, 42
    syscall
}

# sendto(..., MSG_NOSIGNAL, NULL, 0) prevents a peer close from raising SIGPIPE.
unsafe native fn __volt_http_send(fd: i64, data: ptr<u8>, length: i64) -> i64:
{
    mov r10, 0x4000
    xor r8, r8
    xor r9, r9
    mov rax, 44
    syscall
}

unsafe fn http_remaining_ms(deadline: i64) -> i64:
    let now: i64 = http_now_ms()
    if now < 0: return now
    let remaining: i64 = deadline - now
    if remaining <= 0: return HTTP_TIMEOUT
    return remaining

unsafe fn http_deadline_after(timeout_ms: i64) -> i64:
    if timeout_ms <= 0: return -22
    let now: i64 = http_now_ms()
    if now < 0: return now
    if now > 9223372036854775807 - timeout_ms: return -75
    return now + timeout_ms

unsafe fn http_transfer_remaining(transfer: ptr<HttpTransfer>) -> i64:
    if transfer.cancel_state != (0 as ptr<i32>) and http_load_state(transfer.cancel_state) != 0: return HTTP_CANCELLED
    return http_remaining_ms(transfer.deadline)

unsafe fn http_wait(fd: i64, events: i16, transfer: ptr<HttpTransfer>) -> i64:
    while true:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        let wait_ms: i64 = min(remaining, 2147483647)
        if transfer.cancel_state != (0 as ptr<i32>): wait_ms = min(wait_ms, 50)
        let pfd: EventPollFd
        pfd.fd = fd as i32
        pfd.events = events
        pfd.revents = 0
        let status: i64
        unsafe: status = __volt_event_poll(&pfd, 1, wait_ms)
        if status == -4: continue
        if status < 0: return status
        if status == 0: continue
        let after_wait: i64 = http_transfer_remaining(transfer)
        if after_wait < 0: return after_wait
        return pfd.revents as i64
    return -5

unsafe fn http_write_all(fd: i64, data: ptr<u8>, length: i64, transfer: ptr<HttpTransfer>) -> i64:
    let sent: i64 = 0
    while sent < length:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        let count: i64 = __volt_http_send(fd, data + sent, length - sent)
        if count == -4: continue
        if count == HTTP_EAGAIN:
            let ready: i64 = http_wait(fd, HTTP_POLLOUT as i16, transfer)
            if ready < 0: return ready
            continue
        if count < 0: return count
        if count == 0: return -5
        sent += count
    return sent

unsafe fn http_connect(port: i64, address: ptr<u8>, transfer: ptr<HttpTransfer>) -> i64:
    let result: i64 = http_transfer_remaining(transfer)
    if result < 0: return result
    let sockaddr: [16]u8
    sockaddr[0] = 2
    sockaddr[2] = (port / 256) as u8
    sockaddr[3] = (port % 256) as u8
    let i: i64 = 0
    while i < 4:
        sockaddr[4 + i] = address[i]
        i += 1
    let fd: i64 = __volt_http_socket(2, 1 | HTTP_SOCK_NONBLOCK | HTTP_SOCK_CLOEXEC, 0)
    if fd < 0: return fd
    result = __volt_http_connect(fd, &sockaddr[0], 16)
    if result == -4: result = HTTP_EINPROGRESS
    while result == HTTP_EINPROGRESS or result == HTTP_EALREADY:
        result = http_wait(fd, HTTP_POLLOUT as i16, transfer)
        if result < 0: break
        let socket_error: i32 = 0
        let length: u32 = 4
        result = __volt_http_getsockopt(fd, HTTP_SOL_SOCKET, HTTP_SO_ERROR, &socket_error, &length)
        if result == 0: result = 0 - (socket_error as i64)
    if result == 0: result = http_transfer_remaining(transfer)
    if result < 0:
        close(fd)
        return result
    return fd

unsafe fn http_append_text(buf: ptr<ByteBuffer>, text: string) -> i64:
    let p: ptr<char> = text as ptr<char>
    let n: i64 = strlen(p)
    let i: i64 = 0
    while i < n:
        let status: i64 = bytes_push(buf, p[i] as u8)
        if status < 0:
            return status
        i += 1
    return 0

unsafe fn http_parse_ipv4(host: string, address: ptr<u8>) -> i64:
    let p: ptr<char> = host as ptr<char>
    let n: i64 = strlen(p)
    if n < 7 or n > 15:
        return -22
    let octet: i64 = 0
    let digits: i64 = 0
    let value: i64 = 0
    let i: i64 = 0
    while i <= n:
        let c: i64 = 0
        if i < n:
            c = p[i] as i64
        if c == 46 or i == n:
            if digits == 0 or value > 255 or octet >= 4:
                return -22
            address[octet] = value as u8
            octet += 1
            digits = 0
            value = 0
        else:
            if c < 48 or c > 57 or digits == 3:
                return -22
            value = value * 10 + c - 48
            digits += 1
        i += 1
    if octet != 4:
        return -22
    return 0

unsafe fn http_host_valid(p: ptr<char>, length: i64) -> bool:
    if length < 1 or length > 253: return false
    let label: i64 = 0
    let i: i64 = 0
    while i < length:
        let c: i64 = p[i] as i64
        if c == 46:
            if label == 0 or p[i - 1] == '-': return false
            label = 0
        else:
            if (c < 48 or c > 57) and (c < 65 or c > 90) and (c < 97 or c > 122) and c != 45: return false
            if (label == 0 and c == 45) or label == 63: return false
            label += 1
        i += 1
    return label > 0 and p[length - 1] != '-'

# Caller initializes response. Returns response byte count or negative Linux errno.
# The caller owns response and must call bytes_free when finished.
unsafe fn http_get_ipv4(host: string, port: i64, path: string, response: ptr<ByteBuffer>) -> i64:
    return http_get_ipv4_timeout(host, port, path, response, HTTP_DEFAULT_TIMEOUT_MS)

unsafe fn http_get_ipv4_timeout(host: string, port: i64, path: string, response: ptr<ByteBuffer>, timeout_ms: i64) -> i64:
    response.len = 0
    if timeout_ms <= 0: return -22
    let parsed: [4]u8
    let parse_status: i64 = http_parse_ipv4(host, &parsed[0])
    if parse_status < 0: return parse_status
    return http_get_address_timeout(host, port, path, &parsed[0], response, timeout_ms)

unsafe fn http_get_address(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>) -> i64:
    return http_get_address_timeout(host, port, path, address, response, HTTP_DEFAULT_TIMEOUT_MS)

unsafe fn http_get_address_timeout(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, timeout_ms: i64) -> i64:
    return http_get_address_bounded(host, port, path, address, response, HttpLimits(timeout_ms, HTTP_DEFAULT_RESPONSE_LIMIT))

struct HttpLimits:
    timeout_ms: i64
    response_bytes: i64

unsafe fn http_get_address_bounded(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, limits: HttpLimits) -> i64:
    response.len = 0
    let deadline: i64 = http_deadline_after(limits.timeout_ms)
    if deadline < 0: return deadline
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, limits.response_bytes, 0, false, false)
    return http_get_transfer(host, port, path, address, response, &transfer)

unsafe fn http_get_transfer(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    return http_request_transfer(host, port, path, "GET", "", 0 as ptr<u8>, 0, "", address, response, transfer)

unsafe fn http_get_transfer_cookie(host: string, port: i64, path: string, cookie: string, address: ptr<u8>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    return http_request_transfer(host, port, path, "GET", "", 0 as ptr<u8>, 0, cookie, address, response, transfer)

unsafe fn http_append_number(request: ptr<ByteBuffer>, value: i64) -> i64:
    if value < 0: return -22
    let digits: [20]char
    let count: i64 = 0
    let v: i64 = value
    if v == 0:
        digits[0] = '0'
        count = 1
    else:
        while v > 0:
            digits[count] = '0' + (v % 10) as char
            count += 1
            v = v / 10
    let status: i64 = 0
    while count > 0 and status == 0:
        count -= 1
        status = bytes_push(request, digits[count] as u8)
    return status

# GET or POST with an optional request body. GET with a body is rejected.
unsafe fn http_request_transfer(host: string, port: i64, path: string, method: string, content_type: string, body: ptr<u8>, body_len: i64, cookie: string, address: ptr<u8>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    response.len = 0
    transfer.clean_eof = false
    if transfer.response_bytes < 1 or transfer.response_bytes == 9223372036854775807 or transfer.body_bytes < 0: return -22
    if port < 1 or port > 65535:
        return -22
    if body_len < 0 or (body_len > 0 and body == (0 as ptr<u8>)): return -22
    let get: bool = method == "GET"
    let post: bool = method == "POST"
    if not get and not post: return -22
    if get and body_len != 0: return -22
    let host_ptr: ptr<char> = host as ptr<char>
    let path_ptr: ptr<char> = path as ptr<char>
    let host_len: i64 = strlen(host_ptr)
    let path_len: i64 = strlen(path_ptr)
    if not http_host_valid(host_ptr, host_len): return -22
    if path_len == 0 or path_ptr[0] != 47:
        return -22
    let i: i64 = 0
    while i < path_len:
        let path_byte: i64 = path_ptr[i] as i64
        # Origin-form permits visible ASCII except fragments and unsafe separators.
        if path_byte <= 32 or path_byte >= 127 or path_byte == 35 or path_byte == 92 or path_byte == 34 or path_byte == 60 or path_byte == 62 or path_byte == 123 or path_byte == 125 or path_byte == 124 or path_byte == 94 or path_byte == 96:
            return -22
        if path_byte == 37:
            if i + 2 >= path_len:
                return -22
            let hi: i64 = path_ptr[i + 1] as i64
            let lo: i64 = path_ptr[i + 2] as i64
            let valid_hi: bool = (hi >= 48 and hi <= 57) or (hi >= 65 and hi <= 70) or (hi >= 97 and hi <= 102)
            let valid_lo: bool = (lo >= 48 and lo <= 57) or (lo >= 65 and lo <= 70) or (lo >= 97 and lo <= 102)
            if not valid_hi or not valid_lo:
                return -22
            i += 2
        i += 1
    let ct_ptr: ptr<char> = content_type as ptr<char>
    let ct_len: i64 = strlen(ct_ptr)
    if ct_len > 128: return -22
    i = 0
    while i < ct_len:
        let c: i64 = ct_ptr[i] as i64
        if c < 32 or c == 127: return -22
        i += 1
    let cookie_ptr: ptr<char> = cookie as ptr<char>
    let cookie_len: i64 = strlen(cookie_ptr)
    if cookie_len > 4096: return -22
    i = 0
    while i < cookie_len:
        let c: i64 = cookie_ptr[i] as i64
        if c < 32 or c == 127: return -22
        i += 1
    if path_len > 8192:
        return -90
    let encoding_header: string = "Accept-Encoding: identity\r\n"
    if transfer.accept_gzip: encoding_header = "Accept-Encoding: gzip\r\n"
    let request: ByteBuffer
    bytes_init(&request)
    defer bytes_free(&request)
    let status: i64 = bytes_reserve(&request, 8192)
    if status < 0: return status
    if status == 0: status = http_append_text(&request, method)
    if status == 0: status = http_append_text(&request, " ")
    if status == 0: status = http_append_text(&request, path)
    if status == 0: status = http_append_text(&request, " HTTP/1.0\r\nHost: ")
    if status == 0: status = http_append_text(&request, host)
    if status == 0: status = bytes_push(&request, ':' as u8)
    if status == 0: status = http_append_number(&request, port)
    if status == 0: status = http_append_text(&request, "\r\n")
    if status == 0 and cookie_len > 0:
        status = http_append_text(&request, "Cookie: ")
        if status == 0: status = http_append_text(&request, cookie)
        if status == 0: status = http_append_text(&request, "\r\n")
    if status == 0 and body_len > 0:
        status = http_append_text(&request, "Content-Type: ")
        if status == 0: status = http_append_text(&request, content_type)
        if status == 0: status = http_append_text(&request, "\r\nContent-Length: ")
        if status == 0: status = http_append_number(&request, body_len)
        if status == 0: status = http_append_text(&request, "\r\n")
    if status == 0 and transfer.body_bytes > 0: status = http_append_text(&request, encoding_header)
    if status == 0: status = http_append_text(&request, "Connection: close\r\n\r\n")
    if status < 0: return status
    if request.len > 8192:
        return -90
    let fd: i64 = http_connect(port, address, transfer)
    if fd < 0: return fd
    defer close(fd)
    let result: i64 = http_write_all(fd, request.data, request.len, transfer)
    if result < 0: return result
    if body_len > 0:
        let sent: i64 = http_write_all(fd, body, body_len, transfer)
        if sent < 0: return sent
    let frame: HttpFrame
    while true:
        result = http_transfer_remaining(transfer)
        if result < 0: break
        let amount: i64 = bytes_read_room(response, transfer.response_bytes)
        if amount < 0:
            result = amount
            break
        let count: i64 = read(fd, response.data + response.len, amount)
        if count == -4: continue
        if count == HTTP_EAGAIN:
            result = http_wait(fd, HTTP_POLLIN as i16, transfer)
            if result < 0: break
            continue
        if count == 0:
            transfer.clean_eof = true
            return response.len
        result = http_receive_bytes(response, count, transfer, &frame)
        if result > 0: return response.len
        if result < 0: break
    if result < 0 and result != -90: response.len = 0
    return result

unsafe fn http_receive_bytes(response: ptr<ByteBuffer>, count: i64, transfer: ptr<HttpTransfer>, frame: ptr<HttpFrame>) -> i64:
    if count < 0: return count
    response.len += count
    let result: i64 = 0
    if transfer.body_bytes > 0: result = http_frame_check(response, frame, transfer.response_bytes, transfer.body_bytes)
    if response.len > transfer.response_bytes:
        response.len = transfer.response_bytes
        return -90
    return result
