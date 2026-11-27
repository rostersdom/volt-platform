# Bounded HTTPS GET using the system OpenSSL 3 client API.
use bytes
use http

link "-lssl -lcrypto"

unsafe extern fn TLS_client_method() -> ptr<char>
unsafe extern fn SSL_CTX_new(method: ptr<char>) -> ptr<char>
unsafe extern fn SSL_CTX_free(context: ptr<char>)
unsafe extern fn SSL_CTX_set_default_verify_paths(context: ptr<char>) -> i32
unsafe extern fn SSL_CTX_set_verify(context: ptr<char>, mode: i32, callback: ptr<char>)
unsafe extern fn SSL_CTX_clear_options(context: ptr<char>, options: u64) -> u64
unsafe extern fn SSL_new(context: ptr<char>) -> ptr<char>
unsafe extern fn SSL_free(ssl: ptr<char>)
unsafe extern fn SSL_set_fd(ssl: ptr<char>, fd: i32) -> i32
unsafe extern fn SSL_set1_host(ssl: ptr<char>, host: ptr<char>) -> i32
unsafe extern fn SSL_get0_param(ssl: ptr<char>) -> ptr<char>
unsafe extern fn X509_VERIFY_PARAM_set1_ip(param: ptr<char>, ip: ptr<u8>, length: i64) -> i32
unsafe extern fn SSL_ctrl(ssl: ptr<char>, command: i32, larg: i64, parg: ptr<char>) -> i64
unsafe extern fn SSL_connect(ssl: ptr<char>) -> i32
unsafe extern fn SSL_write(ssl: ptr<char>, data: ptr<char>, length: i32) -> i32
unsafe extern fn SSL_read(ssl: ptr<char>, data: ptr<char>, length: i32) -> i32
unsafe extern fn SSL_get_verify_result(ssl: ptr<char>) -> i64
unsafe extern fn SSL_get_error(ssl: ptr<char>, status: i32) -> i32
unsafe extern fn SSL_get_shutdown(ssl: ptr<char>) -> i32
unsafe extern fn SSL_shutdown(ssl: ptr<char>) -> i32
unsafe extern fn ERR_clear_error()

const TLS_WANT_READ: i32 = 2
const TLS_WANT_WRITE: i32 = 3
const TLS_ZERO_RETURN: i32 = 6
const TLS_IGNORE_UNEXPECTED_EOF: u64 = 128  # SSL_OP_IGNORE_UNEXPECTED_EOF
const TLS_RECEIVED_SHUTDOWN: i32 = 2

# OpenSSL's socket BIO can raise SIGPIPE when a peer closes during a write.
unsafe native fn tls_block_sigpipe(previous: ptr<u64>, mask: ptr<u64>) -> i64:
{
    mov rdx, rdi
    xor edi, edi
    mov r10d, 8
    mov eax, 14
    syscall
}

unsafe native fn tls_restore_sigpipe(mask: ptr<u64>, timeout: ptr<i64>):
{
    mov r8, rdi
    mov rdx, rsi
    xor esi, esi
    mov r10d, 8
.Ltls_drain_sigpipe:
    mov eax, 128
    syscall
    cmp rax, -4
    je .Ltls_drain_sigpipe
    mov rsi, r8
    mov edi, 1
    xor edx, edx
    mov eax, 14
    syscall
}

unsafe fn tls_unblock_sigpipe(previous: u64, mask: ptr<u64>):
    if previous & mask[0] == 0:
        let no_wait: [2]i64
        tls_restore_sigpipe(mask, &no_wait[0])

unsafe fn tls_wait(fd: i64, error: i32, transfer: ptr<HttpTransfer>, failure: i64) -> i64:
    if error == TLS_WANT_READ: return http_wait(fd, HTTP_POLLIN as i16, transfer)
    if error == TLS_WANT_WRITE: return http_wait(fd, HTTP_POLLOUT as i16, transfer)
    return failure

unsafe fn tls_http_get_ipv4(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>) -> i64:
    let clean_eof: bool = false
    return tls_http_get_with_eof(host, port, path, address, response, &clean_eof)

unsafe fn tls_http_get_with_eof(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, clean_eof: ptr<bool>) -> i64:
    let limits: TlsReadLimits = TlsReadLimits(HTTP_DEFAULT_RESPONSE_LIMIT, false)
    let status: i64 = tls_http_get_bounded(host, port, path, address, response, &limits)
    clean_eof[0] = limits.clean_eof
    return status

struct TlsReadLimits:
    response_bytes: i64
    clean_eof: bool

unsafe fn tls_http_get_bounded(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, limits: ptr<TlsReadLimits>) -> i64:
    limits.clean_eof = false
    let deadline: i64 = http_deadline_after(HTTP_DEFAULT_TIMEOUT_MS)
    if deadline < 0: return deadline
    let transfer: HttpTransfer = HttpTransfer(deadline, 0 as ptr<i32>, limits.response_bytes, 0, false, false)
    let status: i64 = tls_http_get_transfer(host, port, path, address, response, &transfer)
    limits.clean_eof = transfer.clean_eof
    return status

unsafe fn tls_http_get_transfer(host: string, port: i64, path: string, address: ptr<u8>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    let request: TlsHttpRequest = TlsHttpRequest(host, port, path, address, false, "GET", "", 0 as ptr<u8>, 0)
    return tls_http_request(&request, response, transfer)

unsafe fn tls_http_request_general(host: string, port: i64, path: string, method: string, content_type: string, body: ptr<u8>, body_len: i64, address: ptr<u8>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    let request: TlsHttpRequest = TlsHttpRequest(host, port, path, address, false, method, content_type, body, body_len)
    return tls_http_request(&request, response, transfer)

struct TlsHttpRequest:
    host: string
    port: i64
    path: string
    address: ptr<u8>
    http11: bool
    method: string
    content_type: string
    body: ptr<u8>
    body_len: i64

unsafe fn tls_http_request(target: ptr<TlsHttpRequest>, response: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    let host: string = target.host
    let port: i64 = target.port
    let path: string = target.path
    let address: ptr<u8> = target.address
    transfer.clean_eof = false
    if response == (0 as ptr<ByteBuffer>): return -22
    response.len = 0
    if address == (0 as ptr<u8>) or port < 1 or port > 65535 or transfer.response_bytes < 1 or transfer.response_bytes == 9223372036854775807 or transfer.body_bytes < 0: return -22
    if target.body_len < 0 or (target.body_len > 0 and target.body == (0 as ptr<u8>)): return -22
    let get: bool = target.method == "GET"
    let post: bool = target.method == "POST"
    if not get and not post: return -22
    if get and target.body_len != 0: return -22
    let host_len: i64 = __volt_strlen(host)
    let path_len: i64 = __volt_strlen(path)
    if not http_host_valid(host as ptr<char>, host_len) or path_len < 1 or path_len > 8192 or (path as ptr<char>)[0] != '/': return -22
    let content_len: i64 = __volt_strlen(target.content_type)
    if content_len > 128: return -22
    let ci: i64 = 0
    let ct: ptr<char> = target.content_type as ptr<char>
    while ci < content_len:
        let c: i64 = ct[ci] as i64
        if c < 32 or c == 127: return -22
        ci += 1
    let request: ByteBuffer
    bytes_init(&request)
    defer bytes_free(&request)
    let status: i64 = bytes_reserve(&request, path_len + host_len + content_len + 160)
    if status < 0: return status
    let p: ptr<char> = target.method as ptr<char>
    let i: i64 = 0
    while p[i] != 0 as char:
        if bytes_push(&request, p[i] as u8) != 0: return -12
        i += 1
    if bytes_push(&request, ' ' as u8) != 0: return -12
    p = path as ptr<char>
    i = 0
    while p[i] != 0 as char:
        if p[i] <= 32 or p[i] >= 127 or p[i] == '#' or p[i] == '\\': return -22
        if bytes_push(&request, p[i] as u8) != 0: return -12
        i += 1
    let headers: string = " HTTP/1.0\r\nHost: "
    if target.http11: headers = " HTTP/1.1\r\nHost: "
    p = headers as ptr<char>
    i = 0
    while p[i] != 0 as char:
        if bytes_push(&request, p[i] as u8) != 0: return -12
        i += 1
    p = host as ptr<char>
    i = 0
    while p[i] != 0 as char:
        if bytes_push(&request, p[i] as u8) != 0: return -12
        i += 1
    if bytes_push(&request, ':' as u8) != 0: return -12
    let digits: [5]char
    let value: i64 = port
    let digit_count: i64 = 0
    while value > 0:
        digits[digit_count] = '0' + (value % 10) as char
        digit_count += 1
        value /= 10
    while digit_count > 0:
        digit_count -= 1
        if bytes_push(&request, digits[digit_count] as u8) != 0: return -12
    status = http_append_text(&request, "\r\n")
    if status == 0 and target.body_len > 0:
        status = http_append_text(&request, "Content-Type: ")
        if status == 0: status = http_append_text(&request, target.content_type)
        if status == 0: status = http_append_text(&request, "\r\nContent-Length: ")
        if status == 0: status = http_append_number(&request, target.body_len)
        if status == 0: status = http_append_text(&request, "\r\n")
    if status == 0 and transfer.body_bytes > 0:
        if transfer.accept_gzip: status = http_append_text(&request, "Accept-Encoding: gzip\r\n")
        else: status = http_append_text(&request, "Accept-Encoding: identity\r\n")
    if status == 0: status = http_append_text(&request, "Connection: close\r\n\r\n")
    if status < 0: return status

    let fd: i64 = http_connect(port, address, transfer)
    if fd < 0: return fd
    defer close(fd)
    let sigpipe: u64 = 4096
    let previous: u64 = 0
    let masked: i64 = tls_block_sigpipe(&previous, &sigpipe)
    if masked < 0: return masked
    defer tls_unblock_sigpipe(previous, &sigpipe)
    let context: ptr<char> = SSL_CTX_new(TLS_client_method())
    if context == (0 as ptr<char>): return -12
    defer SSL_CTX_free(context)
    # A system OpenSSL config must not turn unauthenticated EOF into close_notify.
    SSL_CTX_clear_options(context, TLS_IGNORE_UNEXPECTED_EOF)
    SSL_CTX_set_verify(context, 1, 0 as ptr<char>)
    if SSL_CTX_set_default_verify_paths(context) != 1: return -111
    let ssl: ptr<char> = SSL_new(context)
    if ssl == (0 as ptr<char>): return -12
    defer SSL_free(ssl)
    let ip: [4]u8
    if SSL_set_fd(ssl, fd as i32) != 1: return -22
    if http_parse_ipv4(host, &ip[0]) == 0:
        if X509_VERIFY_PARAM_set1_ip(SSL_get0_param(ssl), &ip[0], 4) != 1: return -22
    elif SSL_set1_host(ssl, host as ptr<char>) != 1 or SSL_ctrl(ssl, 55, 0, host as ptr<char>) <= 0:
        return -22
    while true:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        ERR_clear_error()
        let connected: i32 = SSL_connect(ssl)
        if connected == 1: break
        let ready: i64 = tls_wait(fd, SSL_get_error(ssl, connected), transfer, -111)
        if ready < 0: return ready
    if SSL_get_verify_result(ssl) != 0: return -111
    let sent: i64 = 0
    while sent < request.len:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        ERR_clear_error()
        let written: i32 = SSL_write(ssl, (request.data + sent) as ptr<char>, (request.len - sent) as i32)
        if written > 0:
            sent += written as i64
        else:
            let ready: i64 = tls_wait(fd, SSL_get_error(ssl, written), transfer, -5)
            if ready < 0: return ready
    let body_sent: i64 = 0
    while body_sent < target.body_len:
        let remaining: i64 = http_transfer_remaining(transfer)
        if remaining < 0: return remaining
        ERR_clear_error()
        let written: i32 = SSL_write(ssl, (target.body + body_sent) as ptr<char>, (target.body_len - body_sent) as i32)
        if written > 0:
            body_sent += written as i64
        else:
            let ready: i64 = tls_wait(fd, SSL_get_error(ssl, written), transfer, -5)
            if ready < 0: return ready
    let frame: HttpFrame
    let result: i64 = 0
    while true:
        result = http_transfer_remaining(transfer)
        if result < 0: break
        let amount: i64 = bytes_read_room(response, transfer.response_bytes)
        if amount < 0:
            result = amount
            break
        ERR_clear_error()
        let received: i32 = SSL_read(ssl, (response.data + response.len) as ptr<char>, amount as i32)
        if received <= 0:
            let error: i32 = SSL_get_error(ssl, received)
            if error == TLS_ZERO_RETURN and (SSL_get_shutdown(ssl) & TLS_RECEIVED_SHUTDOWN) != 0:
                transfer.clean_eof = true
                SSL_shutdown(ssl)
                return response.len
            result = tls_wait(fd, error, transfer, -5)
            if result < 0: break
            continue
        result = http_receive_bytes(response, received as i64, transfer, &frame)
        if result > 0:
            SSL_shutdown(ssl)
            return response.len
        if result < 0: break
    if result < 0 and result != -90: response.len = 0
    return result
