# Fixed-workload benchmark for checked integer arithmetic and array indexing.
fn main() -> i64:
    let values: [8]i64 = [1, 2, 3, 4, 5, 6, 7, 8]
    let i: i64 = 0
    let sum: i64 = 0
    while i < 1000000:
        sum += values[i & 7]
        i += 1
    print(sum)
    return 0
