struct Inner:
    a: i64
    b: i64

struct Outer:
    tag: char
    in1: Inner

fn main() -> i64:
    let o = Outer('Q', Inner(7, 8))
    print(o.tag)
    print(o.in1.a, o.in1.b)
    o.in1.a = o.in1.a * 2
    print(o.in1.a)
    # копия структуры
    let p = o
    p.in1.b = 100
    print(o.in1.b, p.in1.b)
    # отрицательные: деление и остаток
    print(-7 / 2, -7 % 2, 7 / -2, 7 % -2)
    print(-7.5 / 2.0)
    # унарный минус и скобки
    let x: i64 = -(2 + 3) * 4
    print(x)
    # строки: escape
    print("tab:\tend")
    print("quote:\"q\" back:\\")
    # сравнения
    let a: i64 = 5
    print(a > 3, a <= 5, a == 5, a != 5)
    print(1.5 < 2.5, 2.5 >= 2.5)
    # bool-логика
    print(true and false, true or false, not true)
    # массивы нулевые
    let z: [4]i64
    print(z[0], z[3])
    # приведение указателей
    let n: i64 = 123
    let ad: i64
    unsafe: ad = (&n) as i64
    print(ad != 0)
    return 0
