# Fixed output workload. The runner validates captured bytes separately from timing.
fn main() -> i64:
    let i: i64 = 0
    while i < 20000:
        put_str("VOLT output benchmark\n")
        i += 1
    return 0
