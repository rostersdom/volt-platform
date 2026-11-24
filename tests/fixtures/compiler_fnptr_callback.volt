fn increment(n: i64) -> i64:
    return n + 1

fn unexpected(n: i64):
    panic("defer evaluated early\n")

fn finish(n: i64):
    print(n)

unsafe fn invoke(f: fnptr<(i64) -> i64>, n: i64) -> i64:
    defer f(99)
    return f(n)

unsafe:
    let f = callback(increment)
    let done = callback(unexpected)
    let value = 0
    defer done(value)
    print(invoke(f, f(19)))
    done = callback(finish)
    value = 37
    print("body")
