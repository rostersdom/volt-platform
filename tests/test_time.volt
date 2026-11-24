use time

fn main() -> i64:
    match monotonic_ms():
        Ok(first):
            match monotonic_ms():
                Ok(second):
                    if first < 0 or second < first:
                        panic("monotonic clock moved backwards")
                    print("time", first >= 0, second >= first)
                Err(error):
                    panic("clock_gettime failed")
        Err(error):
            panic("clock_gettime failed")
    return 0
