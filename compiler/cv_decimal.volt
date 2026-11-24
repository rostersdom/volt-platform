use cv_number

# A bounded rational is used only by the lexer. Rounding decimal literals via
# an intermediate f64 loses bits at halfway values and near the subnormal range.
struct CVNatural:
    n: i64
    limb: [320]u32

unsafe fn cv_nat_scale(v: ptr<CVNatural>, multiplier: u64, addend: u64):
    let carry: u64 = addend
    for i in 0..v.n:
        let product: u64 = (v.limb[i] as u64) * multiplier + carry
        v.limb[i] = (product & 0xffffffff) as u32
        carry = product >> 32
    if carry != 0:
        if v.n == 320: panic("volt: decimal literal too large\n")
        v.limb[v.n] = carry as u32
        v.n += 1

unsafe fn cv_nat_shift(to: ptr<CVNatural>, from: ptr<CVNatural>, bits: i64):
    let words: i64 = bits / 32
    let rest: i64 = bits % 32
    if from.n + words >= 320: panic("volt: decimal literal too large\n")
    let carry: u64 = 0
    for i in 0..words: to.limb[i] = 0
    for i in 0..from.n:
        let current: u64 = ((from.limb[i] as u64) << rest) | carry
        to.limb[i + words] = (current & 0xffffffff) as u32
        carry = current >> 32
    to.n = from.n + words
    if carry != 0:
        to.limb[to.n] = carry as u32
        to.n += 1
    while to.n > 0 and to.limb[to.n - 1] == 0: to.n -= 1

unsafe fn cv_nat_cmp(a: ptr<CVNatural>, b: ptr<CVNatural>) -> i64:
    if a.n != b.n: return a.n - b.n
    let i: i64 = a.n
    while i > 0:
        i -= 1
        if a.limb[i] < b.limb[i]: return -1
        if a.limb[i] > b.limb[i]: return 1
    return 0

unsafe fn cv_nat_bits(a: ptr<CVNatural>) -> i64:
    if a.n == 0: return 0
    let top: u32 = a.limb[a.n - 1]
    let width: i64 = (a.n - 1) * 32
    while top != 0:
        top = top >> 1
        width += 1
    return width

unsafe fn cv_nat_sub(a: ptr<CVNatural>, b: ptr<CVNatural>):
    let borrow: i64 = 0
    for i in 0..a.n:
        let word: i64 = (a.limb[i] as i64) - borrow
        if i < b.n: word -= b.limb[i] as i64
        borrow = 0
        if word < 0:
            word += 4294967296
            borrow = 1
        a.limb[i] = word as u32
    while a.n > 0 and a.limb[a.n - 1] == 0: a.n -= 1

unsafe fn cv_decimal(data: ptr<char>, length: i64) -> f64:
    let numerator: CVNatural
    let denominator: CVNatural
    let shifted: CVNatural
    let remainder: CVNatural
    let divisor: CVNatural
    let sign: u64 = 0
    let at: i64 = 0
    if length == 0: return 0.0
    if data[0] == '-' or data[0] == '+':
        if data[0] == '-': sign = 0x8000000000000000
        at += 1
    let fraction: bool = false
    let scale: i64 = 0
    let significant: i64 = 0
    while at < length:
        let c: char = data[at]
        if c == 'e' or c == 'E': break
        if c == '.':
            fraction = true
        else:
            let digit: u64 = ((c as i64) - 48) as u64
            if numerator.n > 0 or digit != 0: significant += 1
            if significant > 2048: panic("volt: decimal literal has more than 2048 significant digits\n")
            cv_nat_scale(&numerator, 10, digit)
            if fraction: scale -= 1
        at += 1
    if numerator.n == 0: return cv_from_bits(sign)
    if at < length:
        at += 1
        let minus: bool = data[at] == '-'
        if minus or data[at] == '+': at += 1
        let power: i64 = 0
        while at < length:
            power = min(10000000, power * 10 + (data[at] as i64) - 48)
            at += 1
        if minus: scale -= power
        else: scale += power
    if significant + scale > 310: return cv_from_bits(sign | 0x7ff0000000000000)
    if significant + scale < -324: return cv_from_bits(sign)
    cv_nat_scale(&denominator, 1, 1)
    if scale < 0:
        for i in 0..(0 - scale): cv_nat_scale(&denominator, 10, 0)
    else:
        for i in 0..scale: cv_nat_scale(&numerator, 10, 0)

    let exponent: i64 = cv_nat_bits(&numerator) - cv_nat_bits(&denominator)
    if exponent < 0:
        cv_nat_shift(&shifted, &numerator, 0 - exponent)
        if cv_nat_cmp(&shifted, &denominator) < 0: exponent -= 1
    else:
        cv_nat_shift(&shifted, &denominator, exponent)
        if cv_nat_cmp(&numerator, &shifted) < 0: exponent -= 1
    if exponent > 1023: return cv_from_bits(sign | 0x7ff0000000000000)
    let normalization: i64 = 52 - max(exponent, -1022)
    if normalization < 0:
        cv_nat_shift(&remainder, &numerator, 0)
        cv_nat_shift(&divisor, &denominator, 0 - normalization)
    else:
        cv_nat_shift(&remainder, &numerator, normalization)
        cv_nat_shift(&divisor, &denominator, 0)
    let mantissa: u64 = 0
    for j in 0..53:
        let bit: i64 = 52 - j
        cv_nat_shift(&shifted, &divisor, bit)
        if cv_nat_cmp(&remainder, &shifted) >= 0:
            cv_nat_sub(&remainder, &shifted)
            mantissa |= (1 as u64) << bit
    cv_nat_scale(&remainder, 2, 0)
    let halfway: i64 = cv_nat_cmp(&remainder, &divisor)
    if halfway > 0 or (halfway == 0 and mantissa & 1 != 0): mantissa += 1
    if exponent < -1022: return cv_from_bits(sign | mantissa)
    let encoded: u64 = (((exponent + 1022) as u64) << 52) + mantissa
    return cv_from_bits(sign | encoded)
