# Unsafe baseline: cache length once and walk a raw pointer; do not mutate the string.
use str

fn main() -> i64:
    let text = "VOLT benchmark string"
    let sum: i64 = 0
    let length: i64 = str_len(text)
    let p: ptr<char>
    unsafe:
        p = text as ptr<char>
        let i: i64 = 0
        while i < 200000:
            sum += p[i % length] as i64
            i += 1
    print(sum)
    return 0
