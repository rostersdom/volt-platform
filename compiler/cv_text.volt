use cv_value
use cv_decimal

unsafe fn cv_ascii_space(c: char) -> bool:
    return c == ' ' or (c >= '\t' and c <= '\r')

unsafe fn cv_digit(c: char) -> i64:
    if c >= '0' and c <= '9': return (c as i64) - 48
    if c >= 'a' and c <= 'f': return (c as i64) - 87
    if c >= 'A' and c <= 'F': return (c as i64) - 55
    return -1

unsafe fn cv_ascii_lower(c: char) -> char:
    if c >= 'A' and c <= 'Z': return c + 32
    return c

unsafe fn cv_lower(v: i64) -> i64:
    let n: i64 = cv_len(v)
    let p: ptr<char> = cv_alloc(n + 1)
    for i in 0..n: p[i] = cv_ascii_lower(cv_byte(v, i))
    return cv_text(p as string)

unsafe fn cv_starts_at(v: i64, part: i64, i: i64) -> bool:
    let n: i64 = cv_text_len(part)
    if i < 0 or i + n > cv_text_len(v): return false
    let left: ptr<char> = cv_cptr(v) + i
    let right: ptr<char> = cv_cptr(part)
    for j in 0..n:
        if left[j] != right[j]: return false
    return true

unsafe fn cv_starts(v: i64, part: i64) -> bool:
    if cv_kind(part) == CV_TUPLE:
        for i in 0..cv_len(part):
            if cv_starts_at(v, cv_at(part, i), 0): return true
        return false
    return cv_starts_at(v, part, 0)

unsafe fn cv_ends(v: i64, part: i64) -> bool:
    return cv_starts_at(v, part, cv_len(v) - cv_len(part))

unsafe fn cv_strip(v: i64) -> i64:
    let lo: i64 = 0
    let hi: i64 = cv_text_len(v)
    let p: ptr<char> = cv_cptr(v)
    while lo < hi and cv_ascii_space(p[lo]): lo += 1
    while hi > lo and cv_ascii_space(p[hi - 1]): hi -= 1
    if lo == 0 and hi == cv_text_len(v): return v
    return cv_subtext(v, lo, hi - lo)

unsafe fn cv_split(v: i64, sep: i64, maximum: i64) -> i64:
    let out: i64 = cv_list()
    let n: i64 = cv_text_len(v)
    let i: i64 = 0
    let limit: i64 = -1
    if maximum != 0: limit = cv_index(maximum)
    if sep == 0:
        let p: ptr<char> = cv_cptr(v)
        while i < n:
            while i < n and cv_ascii_space(p[i]): i += 1
            if i == n: break
            let start: i64 = i
            if cv_len(out) == limit:
                cv_push(out, cv_subtext(v, start, n - start))
                break
            while i < n and not cv_ascii_space(p[i]): i += 1
            cv_push(out, cv_subtext(v, start, i - start))
    else:
        let step: i64 = cv_len(sep)
        if step == 0: panic("volt: empty split separator\n")
        while cv_len(out) != limit:
            let found: i64 = cv_find(v, sep, i)
            if found < 0: break
            cv_push(out, cv_subtext(v, i, found - i))
            i = found + step
        cv_push(out, cv_subtext(v, i, n - i))
    return out

unsafe fn cv_join(sep: i64, values: i64) -> i64:
    let count: i64 = cv_len(values)
    if count == 0: return cv_text("")
    if count == 1: return cv_at(values, 0)
    let delim: i64 = cv_text_len(sep)
    let length: i64 = (count - 1) * delim
    for i in 0..count: length += cv_text_len(cv_at(values, i))
    let p: ptr<char> = cv_alloc(length + 1)
    let at: i64 = 0
    for i in 0..count:
        if i != 0:
            cv_copy(p + at, cv_cptr(sep), delim)
            at += delim
        let item: i64 = cv_at(values, i)
        let n: i64 = cv_text_len(item)
        cv_copy(p + at, cv_cptr(item), n)
        at += n
    return cv_text(p as string)

unsafe fn cv_replace(v: i64, old: i64, new: i64) -> i64:
    return cv_join(new, cv_split(v, old, 0))

unsafe fn cv_pad(v: i64, width: i64, c: char) -> i64:
    let len: i64 = cv_len(v)
    if len >= width: return v
    let data: ptr<char> = cv_alloc(width + 1)
    let fill: i64 = width - len
    for i in 0..fill: data[i] = c
    cv_copy(data + fill, cv_cptr(v), len)
    return cv_text(data as string)

unsafe fn cv_repr(v: i64) -> i64:
    if not cv_istext(v): return cv_str(v)
    let p: ptr<char> = cv_cptr(v)
    let n: i64 = cv_text_len(v)
    let out: ptr<char> = cv_alloc(2 * n + 3)
    let quote: char = '\''
    if cv_find(v, cv_text("'"), 0) >= 0: quote = '"'
    out[0] = quote
    let j: i64 = 1
    for i in 0..n:
        let c: char = p[i]
        if c == '\n' or c == '\r' or c == '\t' or c == '\0':
            out[j] = '\\'
            j += 1
            if c == '\n': c = 'n'
            elif c == '\r': c = 'r'
            elif c == '\t': c = 't'
            else: c = '0'
        elif c == quote or c == '\\':
            out[j] = '\\'
            j += 1
        out[j] = c
        j += 1
    out[j] = quote
    return cv_text(out as string)

unsafe fn cv_str(v: i64) -> i64:
    if cv_istext(v): return v
    if v == 0: return cv_text("None")
    if v == CV_TRUE: return cv_text("True")
    if v == CV_FALSE: return cv_text("False")
    if cv_kind(v) == CV_NUMBER or cv_kind(v) == CV_BIG: return cv_digits(v, 10)
    if cv_kind(v) == CV_REAL:
        let bits: u64 = cv_fbits(cv_real_value(v))
        if bits == 0x7ff0000000000000: return cv_text("inf")
        if bits == 0xfff0000000000000: return cv_text("-inf")
        if cv_real_value(v) != cv_real_value(v): return cv_text("nan")
        return cv_cat(cv_text("f64:0x"), cv_digits(cv_u(bits), 16))
    return cv_typename(v)

unsafe fn cv_format(v: i64, spec: string) -> i64:
    let tag: i64 = cv_text(spec)
    if cv_name(tag, "r"): return cv_repr(v)
    if cv_name(tag, "+d"):
        if cv_less(v, CV_NUMBER): return cv_str(v)
        return cv_cat(cv_text("+"), cv_str(v))
    if cv_name(tag, "x"): return cv_digits(v, 16)
    if cv_name(tag, "03o"): return cv_pad(cv_digits(v, 8), 3, '0')
    if cv_name(tag, "04X"):
        let s: i64 = cv_pad(cv_digits(v, 16), 4, '0')
        let p: ptr<char> = cv_alloc(cv_len(s) + 1)
        for i in 0..cv_len(s):
            let c: char = cv_byte(s, i)
            if c >= 'a' and c <= 'f': c -= 32
            p[i] = c
        return cv_text(p as string)
    return cv_str(v)

unsafe fn cv_mod(a: i64, b: i64) -> i64:
    if not cv_istext(a): return cv_division(a, b, true)
    let n: i64 = cv_len(a)
    let out: i64 = cv_list()
    let p: ptr<char> = cv_cptr(a)
    let pos: i64 = 0
    let start: i64 = 0
    let index: i64 = 0
    while pos < n:
        if p[pos] != '%':
            pos += 1
            continue
        cv_push(out, cv_subtext(a, start, pos - start))
        pos += 1
        let s: i64 = pos
        while pos < n and ((p[pos] >= '0' and p[pos] <= '9') or p[pos] == '+'): pos += 1
        if pos == n: panic("volt: invalid compiler format\n")
        let arg: i64 = b
        if cv_kind(b) == CV_TUPLE: arg = cv_at(b, index)
        cv_push(out, cv_format(arg, cv_cptr(cv_subtext(a, s, pos - s + 1)) as string))
        pos += 1
        start = pos
        index += 1
    cv_push(out, cv_subtext(a, start, n - start))
    return cv_join(cv_text(""), out)

unsafe fn cv_mul(a: i64, b: i64) -> i64:
    if not cv_istext(a): return cv_nummul(a, b)
    let n: i64 = cv_index(b)
    let vec: i64 = cv_list()
    for i in 0..n: cv_push(vec, a)
    return cv_join(cv_text(""), vec)

unsafe fn cv_ordinal(v: i64) -> i64:
    return cv_i(cv_byte(v, 0) as i64)

unsafe fn cv_chr(v: i64) -> i64:
    return cv_char(cv_index(v))

unsafe fn cv_encode(v: i64) -> i64:
    let out: i64 = cv_list()
    for i in 0..cv_len(v): cv_push(out, cv_i(cv_byte(v, i) as i64))
    return out

unsafe fn cv_int(v: i64, radix: i64) -> i64:
    let kind: i64 = cv_kind(v)
    if kind == CV_NUMBER or kind == CV_BIG: return v
    if kind == CV_TRUE: return cv_i(1)
    if kind == CV_FALSE: return CV_NUMBER
    if kind == CV_REAL:
        let r: f64 = cv_real_value(v)
        if r >= 0.0 and r < 18446744073709551616.0: return cv_u(r as u64)
        if r >= -9223372036854775808.0 and r < 0.0: return cv_i(r as i64)
        return 0
    let base: i64 = cv_index(radix)
    let p: ptr<char> = cv_cptr(v)
    let pos: i64 = 0
    let negative: bool = p[0] == '-'
    if negative or p[0] == '+': pos += 1
    if p[pos] == '0' and ((base == 16 and cv_ascii_lower(p[pos + 1]) == 'x') or (base == 2 and cv_ascii_lower(p[pos + 1]) == 'b')):
        pos += 2
    let first: i64 = pos
    let lo: u64 = 0
    let hi: u64 = 0
    let rdx: u64 = base as u64
    while p[pos] != '\0':
        let d: i64 = cv_digit(p[pos])
        if d < 0 or d >= base: return 0
        let carry: u64 = 0
        lo = cv_umul(lo, rdx, &carry)
        if hi > (0xffffffffffffffff - carry) / rdx: return cv_words(0, 1, negative)
        hi = hi * rdx + carry
        let next: u64 = cv_uadd(lo, d as u64)
        if next < lo:
            if hi == 0xffffffffffffffff: return cv_words(0, 1, negative)
            hi += 1
        lo = next
        pos += 1
    if pos == first: return 0
    return cv_words(lo, hi, negative)

unsafe fn cv_f(v: i64) -> i64:
    if not cv_istext(v): return cv_real(cv_real_value(v))
    if cv_name(v, "inf"): return cv_real(cv_from_bits(0x7ff0000000000000))
    if cv_name(v, "nan"): return cv_real(cv_from_bits(0x7ff8000000000000))
    return cv_real(cv_decimal(cv_cptr(v), cv_len(v)))

unsafe fn cv_copysign(v: i64, sign: i64) -> i64:
    let a: u64 = cv_fbits(cv_real_value(v)) & 0x7fffffffffffffff
    let b: u64 = cv_fbits(cv_real_value(sign)) & 0x8000000000000000
    return cv_real(cv_from_bits(a | b))

unsafe fn cv_isnan(v: i64) -> i64:
    let n: f64 = cv_real_value(v)
    return cv_bool(n != n)
