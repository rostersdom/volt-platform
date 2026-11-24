use math

struct Point3:
    x: f64
    y: f64

fn fib(n: i64) -> i64:
    if n < 2: return n
    return fib(n-1) + fib(n-2)

fn add3(a: i64, b: i64, c: f64) -> f64:
    return a as f64 + b as f64 + c

unsafe fn zero_self(p: ptr<Point3>):
    p.x = 0.0
    p.y = 0.0

fn main() -> i32:
    for i in 0..10:
        if i % 3 == 0 and i > 5:
            print(i, "top")
        elif i == 7:
            continue
        else:
            print(fib(i))
    while false:
        print("never")
    let v: [4]i64 = [1, 2, 3, 4]
    print(v[2], v[0] + v[1])
    let p = Point3(1.5, 2.5)
    print(p.x + p.y, add3(v[1], v[2], p.y))
    let arr: [3]f64 = [0.5, 1.5, 2.5]
    for x in 0..len(arr):
        print(arr[x])
    unsafe: zero_self(&p)
    print(p.x, p.y)
    if 1 == 1 and 2 == 2:
        print("eq")
    let s = "volt"
    print(s + "!" * 3)
    print(sqrt(144.0), sin(0.0), abs(-7), min(3, 9))
    return 0
