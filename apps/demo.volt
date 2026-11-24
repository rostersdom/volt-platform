# Пример VOLT: игры с числами, строками и структурами.
# Запуск из корня репозитория:  ./volt apps/demo.volt --run

use math

struct Point:
    x: f64
    y: f64

fn dist(a: Point, b: Point) -> f64:
    let dx: f64 = a.x - b.x
    let dy: f64 = a.y - b.y
    return hypot(dx, dy)

fn fib(n: i64) -> i64:
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

fn main() -> i64:
    # числа
    print("fib(10) =", fib(10))
    print("sqrt(2) =", sqrt(2.0), " PI =", PI)
    print("gcd(48, 60) =", gcd(48, 60), " fact(6) =", fact(6))

    # строки
    let who = "VOLT"
    print("hello, " + who + "!")
    print(who * 3)

    # структуры и указатели
    let a = Point(0.0, 0.0)
    let b = Point(3.0, 4.0)
    print("dist =", dist(a, b))
    unsafe:
        let p: ptr<Point> = &b
        p.x = 10.0
    print("b.x =", b.x)

    # массивы и циклы
    let xs: [5]i64 = [5, 3, 9, 1, 7]
    let maxv: i64 = xs[0]
    for i in 0..5:
        if xs[i] > maxv:
            maxv = xs[i]
    print("max =", maxv)

    # флоаты и касты
    let x: f64 = 2.5
    print("x*4 =", x * 4.0, " int(x) =", x as i64)
    return 0
