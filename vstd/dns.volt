# Narrow glibc x86-64 IPv4 resolver wrapper. Resolver pointers never escape.
link "-lc"

unsafe extern fn getaddrinfo(node: ptr<char>, service: ptr<char>, hints: ptr<char>, result: ptr<ptr<char>>) -> i32
unsafe extern fn freeaddrinfo(result: ptr<char>)

unsafe fn dns_resolve_ipv4(host: string, address_out: ptr<u8>) -> i64:
    let hints: [48]u8
    let i: i64 = 0
    while i < 48:
        hints[i] = 0
        i += 1
    # glibc x86-64 addrinfo offsets: family=4, socktype=8, protocol=12.
    hints[4] = 2
    hints[8] = 1
    hints[12] = 6
    let result: ptr<char> = 0 as ptr<char>
    let hints_ptr: ptr<u8> = &hints[0]
    let result_ptr: ptr<ptr<char>> = &result
    let status: i64 = getaddrinfo(host as ptr<char>, 0 as ptr<char>, hints_ptr as ptr<char>, result_ptr) as i64
    if status != 0 or result == (0 as ptr<char>):
        if result != (0 as ptr<char>): freeaddrinfo(result)
        return -2
    let current: ptr<char> = result
    let found: bool = false
    let count: i64 = 0
    while current != (0 as ptr<char>) and count < 16 and not found:
        let bytes: ptr<u8> = current as ptr<u8>
        let family: i64 = bytes[4] as i64
        let addr_len: i64 = bytes[16] as i64 + bytes[17] as i64 * 256 + bytes[18] as i64 * 65536 + bytes[19] as i64 * 16777216
        let sockaddr_bits: u64 = bytes[24] as u64 + (bytes[25] as u64 << 8) + (bytes[26] as u64 << 16) + (bytes[27] as u64 << 24) + (bytes[28] as u64 << 32) + (bytes[29] as u64 << 40) + (bytes[30] as u64 << 48) + (bytes[31] as u64 << 56)
        let sockaddr: ptr<char> = sockaddr_bits as ptr<char>
        if family == 2 and addr_len >= 16 and sockaddr != (0 as ptr<char>):
            let address: ptr<u8> = sockaddr as ptr<u8>
            address_out[0] = address[4]
            address_out[1] = address[5]
            address_out[2] = address[6]
            address_out[3] = address[7]
            found = true
        let next_bits: u64 = bytes[40] as u64 + (bytes[41] as u64 << 8) + (bytes[42] as u64 << 16) + (bytes[43] as u64 << 24) + (bytes[44] as u64 << 32) + (bytes[45] as u64 << 40) + (bytes[46] as u64 << 48) + (bytes[47] as u64 << 56)
        current = next_bits as ptr<char>
        count += 1
    freeaddrinfo(result)
    if found: return 0
    return -97
