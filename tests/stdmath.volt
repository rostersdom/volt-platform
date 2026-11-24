use math

fn main() -> i64:
    print(sqrt(2.0))
    print(PI)
    print(powi(2.0, 10))
    print(floor(-2.7), ceil(-2.7), round(2.5))
    print(fact(10), gcd(12, 18), ipowi(3, 5))
    print(exp(1.0))
    print(hypot(3.0, 4.0), log10(1000.0), ln(E))
    print(clamp(5.0, 0.0, 1.0), sign(-3.0), iabs(-9))
    # вложенные циклы + break/continue
    let acc: i64 = 0
    for i in 0..10:
        if i % 2 == 0:
            continue
        for j in 0..10:
            if j > i:
                break
            acc = acc + j
    print(acc)
    # касты
    let x: f64 = 3.99
    print(x as i64, -x as i64)
    let n: i64 = 7
    print(n as f64 / 2.0)
    let c: char = 'A'
    print(c as i64 + 1)
    # while с условием
    let k: i64 = 100
    while k > 1:
        k = k / 2
    print(k)
    return 0
