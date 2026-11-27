use browser_controller

unsafe fn tls11_fixture(url: string) -> i64:
    let host: [254]char
    let path: [8193]char
    let port: i64 = 0
    let address: [4]u8
    if browser_parse_url(url, &host[0], &path[0], &port) != 0 or http_parse_ipv4((&host[0]) as string, &address[0]) != 0: return 1
    let transfer: HttpTransfer = HttpTransfer(http_deadline_after(3000), 0 as ptr<i32>, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, true)
    let response: ByteBuffer
    defer bytes_free(&response)
    let request: TlsHttpRequest = TlsHttpRequest((&host[0]) as string, port, (&path[0]) as string, &address[0], true, "GET", "", 0 as ptr<u8>, 0, "")
    if tls_http_request(&request, &response, &transfer) < 0: return 2
    if browser_youtube_response(&response, &transfer, 0 as ptr<BrowserHttpMedia>) != 0: return 3
    if transfer.clean_eof or response.data as ptr<char> as string != "<p>Framed over HTTPS</p>": return 4
    return 0

fn main() -> i64:
    match arg_at(1):
        Ok(url):
            unsafe: return tls11_fixture(url)
        Err(error): return 1
