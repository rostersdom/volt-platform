use browser_youtube_view
use dns
use tls

unsafe fn browser_youtube_get(host: string, path: string, buffer: ptr<ByteBuffer>, transfer: ptr<HttpTransfer>) -> i64:
    let remaining: i64 = http_transfer_remaining(transfer)
    if remaining < 0: return remaining
    let ip: [4]u8
    let resolved: i64 = dns_resolve_ipv4(host, &ip[0])
    remaining = http_transfer_remaining(transfer)
    if remaining < 0: return remaining
    if resolved != 0: return resolved
    if not browser_youtube_public_ipv4(&ip[0]): return -13
    # HTTP/1.1 permits a framed body without trusting an unauthenticated TLS EOF.
    let request: TlsHttpRequest = TlsHttpRequest(host, 443, path, &ip[0], true)
    return tls_http_request(&request, buffer, transfer)
