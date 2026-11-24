# ══════════════════════════════════════════════════════════
# VOLT std/io — вывод без libc (сырые syscall-ы).
# Авто-импорт: доступен всегда. put_* зарезервированы компилятором.
# ══════════════════════════════════════════════════════════

fn put_char(c: char):
    let b: char = c
    let p: ptr<char> = &b
    let status: i64
    unsafe: status = write_all(1, p, 1)
    if status < 0:
        panic("volt: write failed\n")

fn put_str(s: string):
    let p: ptr<char>
    let status: i64
    unsafe:
        p = s as ptr<char>
        status = write_all(1, p, __volt_strlen(s))
    if status < 0:
        panic("volt: write failed\n")

fn put_bool(b: bool):
    if b:
        put_str("true")
    else:
        put_str("false")

fn put_int(v: i64):
    let u: u64 = 0
    if v < 0:
        put_char('-')
        u = (0 - (v + 1)) as u64
        u = u + 1
    else:
        u = v as u64
    put_uint(u)

fn put_uint(v: u64):
    let buf: [20]char
    let u: u64 = v
    if u == 0:
        put_char('0')
        return
    let n: i64 = 20
    while u > 0:
        n = n - 1
        buf[n] = '0' + (u % 10)
        u = u / 10
    let status: i64
    unsafe: status = write_all(1, &buf[n], 20 - n)
    if status < 0:
        panic("volt: write failed\n")

# One bounded write for a complete float value; panic matches other put_* helpers.
unsafe fn put_float_emit(buf: ptr<char>, length: i64):
    let status: i64
    unsafe: status = write_all(1, buf, length)
    if status < 0:
        panic("volt: write failed\n")

fn put_float(x: f64):
    let buf: [32]char
    let length: i64 = 0
    if x < 0.0:
        buf[length] = '-'
        length += 1
        x = 0.0 - x
    if x != x:
        buf[length] = 'n'
        buf[length + 1] = 'a'
        buf[length + 2] = 'n'
        length += 3
        unsafe: put_float_emit(&buf[0], length)
        return
    if x > 1.7976931348623157e308:
        buf[length] = 'i'
        buf[length + 1] = 'n'
        buf[length + 2] = 'f'
        length += 3
        unsafe: put_float_emit(&buf[0], length)
        return
    if x >= 9223372036854775808.0:
        let exponent: i64 = 0
        while x >= 10.0:
            x = x / 10.0
            exponent = exponent + 1
        while x < 1.0:
            x = x * 10.0
            exponent = exponent - 1
        x = x + 0.0000005
        if x >= 10.0:
            x = x / 10.0
            exponent = exponent + 1
        let ip: i64 = x as i64
        let digits_start: i64 = length
        let remaining: u64 = ip as u64
        if remaining == 0:
            buf[length] = '0'
            length += 1
        else:
            while remaining > 0:
                buf[length] = '0' + (remaining % 10) as char
                length += 1
                remaining = remaining / 10
            let left: i64 = digits_start
            let right: i64 = length - 1
            while left < right:
                let saved: char = buf[left]
                buf[left] = buf[right]
                buf[right] = saved
                left += 1
                right -= 1
        buf[length] = '.'
        length += 1
        let fr: f64 = x - (ip as f64)
        let k: i64 = 0
        while k < 6:
            fr = fr * 10.0
            let d: i64 = fr as i64
            buf[length] = '0' + d as char
            length += 1
            fr = fr - (d as f64)
            k = k + 1
        buf[length] = 'e'
        length += 1
        let exp_value: u64
        if exponent < 0:
            buf[length] = '-'
            length += 1
            exp_value = (0 - (exponent + 1)) as u64 + 1
        else:
            exp_value = exponent as u64
        let exp_start: i64 = length
        let exp_remaining: u64 = exp_value
        if exp_remaining == 0:
            buf[length] = '0'
            length += 1
        else:
            while exp_remaining > 0:
                buf[length] = '0' + (exp_remaining % 10) as char
                length += 1
                exp_remaining = exp_remaining / 10
            let left: i64 = exp_start
            let right: i64 = length - 1
            while left < right:
                let saved: char = buf[left]
                buf[left] = buf[right]
                buf[right] = saved
                left += 1
                right -= 1
        unsafe: put_float_emit(&buf[0], length)
        return
    # округление до 6 знаков: половинка последнего разряда
    x = x + 0.0000005
    let ip: i64 = x as i64
    let digits_start: i64 = length
    let remaining: u64 = ip as u64
    if remaining == 0:
        buf[length] = '0'
        length += 1
    else:
        while remaining > 0:
            buf[length] = '0' + (remaining % 10) as char
            length += 1
            remaining = remaining / 10
        let left: i64 = digits_start
        let right: i64 = length - 1
        while left < right:
            let saved: char = buf[left]
            buf[left] = buf[right]
            buf[right] = saved
            left += 1
            right -= 1
    buf[length] = '.'
    length += 1
    let fr: f64 = x - (ip as f64)
    let k: i64 = 0
    while k < 6:
        fr = fr * 10.0
        let d: i64 = fr as i64
        buf[length] = '0' + d as char
        length += 1
        fr = fr - (d as f64)
        k = k + 1
    unsafe: put_float_emit(&buf[0], length)

fn nl():
    put_char('\n')

fn put_err(s: string):
    let p: ptr<char>
    let status: i64
    unsafe:
        p = s as ptr<char>
        status = write_all(2, p, __volt_strlen(s))
    if status < 0:
        panic("volt: stderr write failed\n")

fn put_errnl(s: string):
    let p: ptr<char>
    let status: i64
    unsafe:
        p = s as ptr<char>
        status = write_all(2, p, __volt_strlen(s))
    let nl: char = '\n'
    let nl_ptr: ptr<char> = &nl
    let nl_status: i64
    unsafe: nl_status = write_all(2, nl_ptr, 1)
    if status < 0 or nl_status < 0:
        panic("volt: stderr write failed\n")
