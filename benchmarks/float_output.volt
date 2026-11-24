# Fixed-workload benchmark: each iteration emits two floats and one newline.
fn main() -> i64:
    let i: i64 = 0
    while i < 100000:
        print(1.234567, 1.0e20)
        i += 1
    return 0
