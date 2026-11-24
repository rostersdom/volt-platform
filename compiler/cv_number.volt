use cv_memory

# Boxed integers use a sign and two magnitude words. Source values fit in
# 64 bits, but their products and the upper bounds used by the compiler don't.
struct CVWide:
    low: u64
    high: u64
    negative: bool

const CV_SMALL_MIN: i64 = -1152921504606846976
const CV_SMALL_MAX: i64 = 1152921504606846975

unsafe fn cv_i(n: i64) -> i64:
    if n >= CV_SMALL_MIN and n <= CV_SMALL_MAX: return n * 8 + CV_NUMBER
    if n < 0: return cv_words(((0 - (n + 1)) as u64) + 1, 0, true)
    return cv_words(n as u64, 0, false)

unsafe fn cv_words(low: u64, high: u64, sign: bool) -> i64:
    if high == 0:
        if low == 0: return CV_NUMBER
        if not sign and low <= CV_SMALL_MAX as u64: return (low as i64) * 8 + CV_NUMBER
        if sign and low <= 1152921504606846976: return (0 - (low as i64)) * 8 + CV_NUMBER
    let p: ptr<u64> = cv_alloc(32) as ptr<u64>
    p[0] = CV_BIG as u64
    p[1] = low
    p[2] = high
    p[3] = 0
    if sign: p[3] = 1
    return p as i64

unsafe fn cv_u(n: u64) -> i64:
    return cv_words(n, 0, false)

unsafe fn cv_wide(v: i64) -> CVWide:
    let k: i64 = cv_kind(v)
    if k == CV_BIG:
        let data: ptr<u64> = v as ptr<u64>
        return CVWide(data[1], data[2], data[3] != 0)
    if v == CV_TRUE: return CVWide(1, 0, false)
    if v == CV_FALSE: return CVWide(0, 0, false)
    if k != CV_NUMBER: panic("volt: compiler expected integer\n")
    let n: i64 = v >> 3
    if n < 0: return CVWide((0 - n) as u64, 0, true)
    return CVWide(n as u64, 0, false)

unsafe fn cv_index(v: i64) -> i64:
    if v & 7 == CV_NUMBER: return v >> 3
    let n: CVWide = cv_wide(v)
    if n.high != 0 or n.low > 0x8000000000000000: panic("volt: compiler integer outside i64\n")
    if n.negative:
        if n.low == 0x8000000000000000: return -9223372036854775808
        return 0 - (n.low as i64)
    if n.low == 0x8000000000000000: panic("volt: compiler integer outside i64\n")
    return n.low as i64

unsafe fn cv_real(n: f64) -> i64:
    let p: ptr<i64> = cv_alloc(16) as ptr<i64>
    p[0] = CV_REAL
    (p as ptr<f64>)[1] = n
    return p as i64

unsafe native fn cv_fbits(x: f64) -> u64:
{
    movsd qword ptr [rbp-8], xmm0
    mov rax, qword ptr [rbp-8]
}

unsafe native fn cv_from_bits(x: u64) -> f64:
{
    mov qword ptr [rbp-8], rdi
    movsd xmm0, qword ptr [rbp-8]
}

unsafe native fn cv_fbits32(x: f32) -> u32:
{
    movss dword ptr [rbp-8], xmm0
    mov eax, dword ptr [rbp-8]
}

unsafe fn cv_real_value(v: i64) -> f64:
    if cv_kind(v) == CV_REAL: return (v as ptr<f64>)[1]
    let n: CVWide = cv_wide(v)
    let r: f64 = n.low as f64
    if n.high != 0: r += (n.high as f64) * 18446744073709551616.0
    if n.negative: return cv_from_bits(cv_fbits(r) ^ 0x8000000000000000)
    return r

unsafe fn cv_real_sign(v: i64) -> bool:
    return cv_fbits(cv_real_value(v)) >> 63 != 0

unsafe fn cv_magcmp(a: CVWide, b: CVWide) -> i64:
    if a.high < b.high: return -1
    if a.high > b.high: return 1
    if a.low < b.low: return -1
    if a.low > b.low: return 1
    return 0

unsafe native fn cv_uadd(a: u64, b: u64) -> u64:
{
    lea rax, [rdi+rsi]
}

unsafe native fn cv_usub(a: u64, b: u64) -> u64:
{
    mov rax, rdi
    sub rax, rsi
}

unsafe native fn cv_umul(a: u64, b: u64, high: ptr<u64>) -> u64:
{
    mov rcx, rdx
    mov rax, rdi
    mul rsi
    mov qword ptr [rcx], rdx
}

unsafe native fn cv_udiv(high: u64, low: u64, d: u64, rem: ptr<u64>) -> u64:
{
    mov r8, rdx
    mov rdx, rdi
    mov rax, rsi
    div r8
    mov qword ptr [rcx], rdx
}

unsafe fn cv_numcmp(a: i64, b: i64) -> i64:
    if a & 7 == CV_NUMBER and b & 7 == CV_NUMBER:
        if a < b: return -1
        if a > b: return 1
        return 0
    if cv_kind(a) == CV_REAL or cv_kind(b) == CV_REAL:
        let x: f64 = cv_real_value(a)
        let y: f64 = cv_real_value(b)
        if x < y: return -1
        if x > y: return 1
        if x == y: return 0
        return 2
    let x: CVWide = cv_wide(a)
    let y: CVWide = cv_wide(b)
    if cv_diff_sign(x.negative, y.negative):
        if x.negative: return -1
        return 1
    let cmp: i64 = cv_magcmp(x, y)
    if x.negative: return 0 - cmp
    return cmp

unsafe fn cv_neg(a: i64) -> i64:
    if cv_kind(a) == CV_REAL: return cv_real(cv_from_bits(cv_fbits(cv_real_value(a)) ^ 0x8000000000000000))
    if a & 7 == CV_NUMBER: return cv_i(0 - (a >> 3))
    let n: CVWide = cv_wide(a)
    return cv_words(n.low, n.high, not n.negative)

unsafe fn cv_numadd(a: i64, b: i64) -> i64:
    if a & 7 == CV_NUMBER and b & 7 == CV_NUMBER: return cv_i((a >> 3) + (b >> 3))
    if cv_kind(a) == CV_REAL or cv_kind(b) == CV_REAL: return cv_real(cv_real_value(a) + cv_real_value(b))
    let x: CVWide = cv_wide(a)
    let y: CVWide = cv_wide(b)
    if not cv_diff_sign(x.negative, y.negative):
        let low: u64 = cv_uadd(x.low, y.low)
        let high: u64 = x.high + y.high
        if low < x.low: high += 1
        return cv_words(low, high, x.negative)
    if cv_magcmp(x, y) < 0:
        let swap: CVWide = x
        x = y
        y = swap
    let high: u64 = x.high - y.high
    if x.low < y.low: high -= 1
    return cv_words(cv_usub(x.low, y.low), high, x.negative)

unsafe fn cv_numsub(a: i64, b: i64) -> i64:
    if a & 7 == CV_NUMBER and b & 7 == CV_NUMBER: return cv_i((a >> 3) - (b >> 3))
    return cv_numadd(a, cv_neg(b))

unsafe fn cv_nummul(a: i64, b: i64) -> i64:
    if cv_kind(a) == CV_REAL or cv_kind(b) == CV_REAL: return cv_real(cv_real_value(a) * cv_real_value(b))
    let x: CVWide = cv_wide(a)
    let y: CVWide = cv_wide(b)
    let high: u64 = 0
    let low: u64 = cv_umul(x.low, y.low, &high)
    if x.high != 0 and y.high != 0: panic("volt: integer constant outside compiler range\n")
    high += x.low * y.high + x.high * y.low
    return cv_words(low, high, cv_diff_sign(x.negative, y.negative))

unsafe fn cv_division(a: i64, b: i64, rem: bool) -> i64:
    let x: CVWide = cv_wide(a)
    let y: CVWide = cv_wide(b)
    if y.high == 0 and y.low == 0: panic("volt: compiler division by zero\n")
    let lo: u64 = 0
    let hi: u64 = 0
    let rlo: u64 = 0
    let rhi: u64 = 0
    if y.high == 0:
        hi = x.high / y.low
        lo = cv_udiv(x.high % y.low, x.low, y.low, &rlo)
    else:
        rlo = x.low
        rhi = x.high
        if cv_magcmp(x, y) >= 0:
            for bit in 0..64:
                let shift: i64 = 63 - bit
                if shift > 0 and y.high >> (64 - shift) != 0: continue
                let low: u64 = y.low << shift
                let high: u64 = y.high << shift
                if shift > 0: high |= y.low >> (64 - shift)
                if rhi > high or (rhi == high and rlo >= low):
                    rhi -= high
                    if rlo < low: rhi -= 1
                    rlo = cv_usub(rlo, low)
                    lo |= (1 as u64) << shift
    let negative: bool = cv_diff_sign(x.negative, y.negative)
    let remainder: i64 = cv_words(rlo, rhi, false)
    let q: i64 = cv_words(lo, hi, negative)
    if rem:
        if remainder == CV_NUMBER: return remainder
        if negative: return cv_numadd(cv_words(rlo, rhi, x.negative), b)
        return cv_words(rlo, rhi, x.negative)
    if negative and remainder != CV_NUMBER: return cv_numsub(q, cv_i(1))
    return q

unsafe fn cv_numdiv(a: i64, b: i64) -> i64:
    return cv_real(cv_real_value(a) / cv_real_value(b))

unsafe fn cv_twos(v: i64) -> CVWide:
    let n: CVWide = cv_wide(v)
    if n.negative:
        n.low = cv_usub(0, n.low)
        n.high = n.high ^ 0xffffffffffffffff
        if n.low == 0: n.high = cv_uadd(n.high, 1)
    return n

unsafe fn cv_bitop(a: i64, b: i64, op: i64) -> i64:
    let x: CVWide = cv_twos(a)
    let y: CVWide = cv_twos(b)
    let lo: u64 = 0
    let hi: u64 = 0
    let neg: bool = false
    if op == 0:
        lo = x.low & y.low
        hi = x.high & y.high
        neg = x.negative and y.negative
    elif op == 1:
        lo = x.low | y.low
        hi = x.high | y.high
        neg = x.negative or y.negative
    else:
        lo = x.low ^ y.low
        hi = x.high ^ y.high
        neg = cv_diff_sign(x.negative, y.negative)
    if neg:
        lo = cv_usub(0, lo)
        hi = hi ^ 0xffffffffffffffff
        if lo == 0: hi = cv_uadd(hi, 1)
    return cv_words(lo, hi, neg)

unsafe fn cv_shift(a: i64, b: i64, left: bool) -> i64:
    let k: i64 = cv_index(b)
    if k < 0: panic("volt: negative shift\n")
    if k == 0: return a
    let n: CVWide = cv_wide(a)
    if left:
        if k >= 128: panic("volt: integer constant outside compiler range\n")
        if k >= 64:
            if n.high != 0 or (k > 64 and n.low >> (128 - k) != 0): panic("volt: integer constant outside compiler range\n")
            return cv_words(0, n.low << (k - 64), n.negative)
        if n.high >> (64 - k) != 0: panic("volt: integer constant outside compiler range\n")
        return cv_words(n.low << k, (n.high << k) | (n.low >> (64 - k)), n.negative)
    let lo: u64 = 0
    let hi: u64 = 0
    let lost: bool = n.low != 0 or n.high != 0
    if k < 64:
        lo = (n.low >> k) | (n.high << (64 - k))
        hi = n.high >> k
        lost = n.low << (64 - k) != 0
    elif k < 128:
        lo = n.high >> (k - 64)
        lost = n.low != 0 or (k > 64 and n.high << (128 - k) != 0)
    let q: i64 = cv_words(lo, hi, n.negative)
    if n.negative and lost: return cv_numsub(q, cv_i(1))
    return q

unsafe fn cv_round32(v: i64) -> i64:
    if cv_kind(v) == CV_REAL: return cv_real(((v as ptr<f64>)[1] as f32) as f64)
    let n: CVWide = cv_wide(v)
    if n.high != 0: return cv_real((cv_real_value(v) as f32) as f64)
    let rounded: f32 = n.low as f32
    if n.negative: return cv_real(cv_from_bits(cv_fbits(rounded as f64) ^ 0x8000000000000000))
    return cv_real(rounded as f64)

unsafe fn cv_digits(v: i64, base: i64) -> i64:
    let radix: u64 = base as u64
    let n: CVWide = cv_wide(v)
    let buf: [132]char
    let at: i64 = 132
    let digits: ptr<char> = "0123456789abcdef" as ptr<char>
    while n.low != 0 or n.high != 0 or at == 132:
        let r: u64 = 0
        n.low = cv_udiv(n.high % radix, n.low, radix, &r)
        n.high /= radix
        at -= 1
        buf[at] = digits[r]
    if n.negative:
        at -= 1
        buf[at] = '-'
    return cv_text(cv_cstring(&buf[at], 132 - at))

fn cv_diff_sign(a: bool, b: bool) -> bool:
    return (a and not b) or (b and not a)
