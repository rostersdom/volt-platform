# Repeated checked string indexing; VOLT recalculates the NUL-terminated length per access.
fn main() -> i64:
    let text = "VOLT benchmark string"
    let sum: i64 = 0
    let i: i64 = 0
    while i < 200000:
        sum += text[i % 21] as i64
        i += 1
    print(sum)
    return 0
