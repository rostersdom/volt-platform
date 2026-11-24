# ══════════════════════════════════════════════════════════
# VOLT std/math — математика поверх intrinsics.
# sin/cos/tan/log2/atan2/sqrt/abs/min/max — встроены в компилятор
# и доступны всегда; модуль добавляет константы и остальное.
# ══════════════════════════════════════════════════════════

let PI: f64 = 3.141592653589793
let E: f64 = 2.718281828459045
let TAU: f64 = 6.283185307179586

# x^n для целого n (n < 0 -> 1/x^|n|)
fn powi(x: f64, n: i64) -> f64:
    let neg: bool = n < 0
    let k: u64 = 0
    if neg:
        k = (0 - (n + 1)) as u64
        k = k + 1
    else:
        k = n as u64
    let r: f64 = 1.0
    let factor: f64 = x
    while k > 0:
        if k & 1 != 0:
            r = r * factor
        k = k >> 1
        if k > 0:
            factor = factor * factor
    if neg:
        return 1.0 / r
    return r

# целая часть вниз (floor(2.7) = 2, floor(-2.1) = -3)
fn floor(x: f64) -> i64:
    let i: i64 = x as i64
    if (i as f64) > x:
        return i - 1
    return i

# целая часть вверх (ceil(2.1) = 3, ceil(-2.7) = -2)
fn ceil(x: f64) -> i64:
    let i: i64 = x as i64
    if (i as f64) < x:
        return i + 1
    return i

# ближайшее целое (half away from zero)
fn round(x: f64) -> i64:
    if x < 0.0:
        return ceil(x - 0.5)
    return floor(x + 0.5)

# ограничить значение диапазоном
fn clamp(x: f64, lo: f64, hi: f64) -> f64:
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x

# целочисленное возведение в степень
fn ipowi(x: i64, n: i64) -> i64:
    if n < 0:
        if x == 0:
            panic("integer power division by zero")
        if x == 1:
            return 1
        if x == -1:
            if n % 2 != 0:
                return -1
            return 1
        return 0
    let k: u64 = n as u64
    let r: i64 = 1
    let factor: i64 = x
    while k > 0:
        if k & 1 != 0:
            r = r * factor
        k = k >> 1
        if k > 0:
            factor = factor * factor
    return r

# факториал
fn fact(n: i64) -> i64:
    let r: i64 = 1
    let i: i64 = 2
    while i <= n:
        r = r * i
        i = i + 1
    return r

# НОД
fn gcd(a: i64, b: i64) -> i64:
    let x: i64 = a
    let y: i64 = b
    if x < 0:
        x = 0 - x
    if y < 0:
        y = 0 - y
    while y != 0:
        let t: i64 = y
        y = x % y
        x = t
    return x

# знак числа: -1, 0, 1
fn sign(x: f64) -> i64:
    if x < 0.0:
        return -1
    if x > 0.0:
        return 1
    return 0

# гипотенуза (без переполнения по квадратам)
fn hypot(x: f64, y: f64) -> f64:
    let ax: f64 = abs(x)
    let ay: f64 = abs(y)
    if ax < ay:
        let tmp: f64 = ax
        ax = ay
        ay = tmp
    if ax == 0.0:
        return 0.0
    let r: f64 = ay / ax
    return ax * sqrt(1.0 + r * r)

# модуль для целых (abs для float — intrinsic)
fn iabs(x: i64) -> i64:
    if x < 0:
        return 0 - x
    return x

# логарифм по основанию 10
fn log10(x: f64) -> f64:
    return log2(x) / 3.321928094887362

# натуральный логарифм
fn ln(x: f64) -> f64:
    return log2(x) * 0.693147180559945

# Экспонента: уменьшение аргумента, ряд Тейлора и последующее возведение в квадрат.
fn exp(x: f64) -> f64:
    let r: f64 = x
    let scale: i64 = 0
    while abs(r) > 0.5:
        r = r * 0.5
        scale = scale + 1
    let term: f64 = 1.0
    let sum: f64 = 1.0
    let i: i64 = 1
    while i < 18:
        term = term * r / (i as f64)
        sum = sum + term
        i = i + 1
    while scale > 0:
        sum = sum * sum
        scale = scale - 1
    return sum
