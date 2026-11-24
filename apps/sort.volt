# Пример VOLT: сортировка массива (пузырьком) и работа с файлами через extern.
# Запуск из корня репозитория:  ./volt apps/sort.volt --run

unsafe fn sort(xs: ptr<i64>, n: i64):
    let i: i64 = 0
    while i < n:
        let j: i64 = 0
        while j < n - 1:
            if xs[j] > xs[j + 1]:
                let t: i64 = xs[j]
                xs[j] = xs[j + 1]
                xs[j + 1] = t
            j = j + 1
        i = i + 1

fn main() -> i64:
    let xs: [8]i64 = [42, 7, 19, 3, 88, 1, 55, 23]
    unsafe: sort(&xs[0], 8)
    for i in 0..8:
        put_int(xs[i])
        put_char(' ')
    nl()

    # строка как ptr<char>, длина и копия
    let s = "abcdef"
    print("len:", str_len(s), "first:", s[0])

    # min/max/cast
    let lo: i64 = 100
    let hi: i64 = -100
    for i in 0..8:
        lo = min(lo, xs[i])
        hi = max(hi, xs[i])
    print("lo:", lo, "hi:", hi, "range:", (hi - lo) as f64 / 2.0)
    return 0
