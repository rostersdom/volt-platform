# указатели, массивы, структуры, сложные lvalue
struct Vec:
    x: i64
    y: i64
    z: i64

unsafe fn bump(v: ptr<Vec>, d: i64):
    v.x = v.x + d
    v.y = v.y + d
    v.z = v.z + d

unsafe fn sum2(a: ptr<i64>, n: i64) -> i64:
    let s: i64 = 0
    let i: i64 = 0
    while i < n:
        s = s + a[i]
        i = i + 1
    return s

fn main() -> i64:
    let m: [5]i64 = [10, 20, 30, 40, 50]
    let v = Vec(1, 2, 3)
    unsafe:
        print(sum2(&m[0], 5))
        m[1] = m[1] + m[4]
        print(m[1])
        m[2] += 100
        print(m[2])
        print(v.x + v.y + v.z)
        bump(&v, 10)
        print(v.x, v.y, v.z)
        let p: ptr<i64> = &m[0]
        print(*p)
        p = p + 2
        print(*p)
        *p = 77
        print(m[2])
        let q: ptr<Vec> = &v
        print(q.x, q.z)
        if &m[0] == p:
            print("same")
        else:
            print("diff")
    let f: [3]f64 = [1.5, 2.5, 3.5]
    let t: f64 = 0.0
    for i in 0..3:
        t = t + f[i]
    print(t)
    return 0
