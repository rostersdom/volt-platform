# HTTP client

`use http` provides a blocking HTTP/1.0 GET client for Linux x86-64 IPv4/TCP.
The native browser accepts numeric dotted IPv4 addresses and ASCII DNS hostnames
for plain HTTP navigation. Hostnames resolve through the VOLT `use dns` wrapper
around libc `getaddrinfo`; the transport connects to one returned IPv4 address
and keeps the original hostname in the `Host` header. This is not a general-purpose
HTTP API for resolving arbitrary host strings.

```volt
use http

fn main() -> i64:
    unsafe:
        let response: ByteBuffer
        bytes_init(&response)
        let result: i64 = http_get_ipv4("127.0.0.1", 8080, "/", &response)
        if result < 0:
            put_err("HTTP errno ")
            put_int(0 - result)
            nl()
        else:
            # response.data[0..response.len] contains raw status line, headers,
            # separator and body. HTTP is untrusted input; validate before use.
            put_int(result)
            nl()
        bytes_free(&response)
    return 0
```

API:

```volt
unsafe fn http_get_ipv4(host: string, port: i64, path: string,
                        response: ptr<ByteBuffer>) -> i64
```

The caller must initialize `response` with `bytes_init` before calling and own
it for the duration of the call; after use call `bytes_free`. On success the
return value is the number of response bytes and `response.len` matches it. The
buffer retains the complete raw HTTP response, including status, headers, and
body. Each call resets `response.len`. A failure returns a negative Linux errno
and leaves the length at zero, except when exceeding the response size limit.
In that case the length covers the retained prefix. The allocation is retained
for reuse. The client closes the connection on every path after socket creation.

The request is exactly `GET <path> HTTP/1.0`, a `Host` header including port,
and `Connection: close`. The HTTP transport API requires a numeric IPv4 host;
the browser's URL parser separately accepts DNS hostnames of 1–253 ASCII bytes
with labels of 1–63 letters, digits, or interior hyphens. It rejects malformed
numeric IPv4 strings instead of treating them as names. Port must be 1–65535,
and path must be an HTTP origin-form request-target beginning
with `/`. It rejects ASCII SP, HTAB, all bytes `0x00`–`0x20`, DEL (`0x7f`),
and `#` (URI fragments are client-side and are not sent in HTTP request-targets).
Percent-encode spaces and control bytes; preserve `/`, `?`, and other path/query
punctuation as appropriate. For example, `/` and `/x?y=1` are accepted while
`/a b` and `/a#frag` are rejected. Invalid arguments return `-22` (`EINVAL`). Requests are capped at 8 KiB and responses at
64 KiB by default. `http_get_address_bounded` accepts `HttpLimits`, with a
timeout in milliseconds and a response limit in bytes. A response exceeding the
limit returns `-90` (`EMSGSIZE`) and retains the prefix up to that limit.
`http_get_ipv4` and `http_get_address` apply a 10-second absolute
monotonic deadline to connect, write, and read; the `_timeout` variants accept a
positive millisecond deadline. The budget is shared across transport phases and
successful partial progress does not reset it. Short writes are handled by a loop,
and sends use `MSG_NOSIGNAL` so a peer closing early does not deliver SIGPIPE.

This is a minimal HTTP/1.0 transport, **not** a complete HTTP stack. The raw API
reads until EOF; the browser's framed reader stops at `Content-Length` or the
final chunk without waiting for the peer to close. Bytes beyond the first complete
response are discarded because the client does not reuse the connection. Chunk extensions and trailers
are not supported. The browser normally sends HTTP/1.0 requests; the native
YouTube view uses HTTP/1.1 over TLS. The browser reads a subset of HTTP/1.0
and HTTP/1.1 responses, and reports a non-rendered HTTP status (e.g. `404`)
separately from malformed responses. Window and screenshot modes request
`Accept-Encoding: gzip` and accept `identity` and single-member `gzip` bodies.
Decoded bytes are checked against the body budget. The legacy `--check` mode
requests `identity`.
The browser accepts up to 2 MiB of HTML, 64 KiB of headers, and 2 MiB + 64 KiB of
raw response data, including chunk framing. HTTPS uses system OpenSSL 3, verifies
the trust chain and the requested hostname, and requires TLS `close_notify` for
a body without length or chunk framing.

The visual renderer fetches external CSS (`text/css`) and raster images (`image/png`,
`image/jpeg`, `image/webp`) from the document's origin. Asset redirects must
preserve the scheme, hostname and port. The CSP subset recognizes `default-src`,
`style-src`, `style-src-elem`, `style-src-attr`, and `img-src` for these resources.

Window navigation uses one 10-second monotonic deadline across DNS, transport
and up to five redirects (301, 302, 303, 307, 308). Stop/Esc discards the
candidate without changing the current page or history. In-flight socket I/O
checks cancellation in both HTTP and HTTPS. The GUI also abandons a pending
result at the deadline. Blocking libc IPv4 lookup cannot be interrupted; up to
four loader jobs may be outstanding while such calls finish. In headless
`--check` mode, blocking DNS may exceed the deadline before returning.

The native socket wrappers use Linux x86-64 syscall numbers
and `sockaddr_in` layout. The API is
unsafe: raw pointers and the caller-provided `ByteBuffer` must be valid, and
network response bytes are untrusted. No claim is made that the returned bytes
are safe to interpret as a string or trusted application data.

Run the loopback integration test with:

```sh
python3 tests/http_integration.py
```
