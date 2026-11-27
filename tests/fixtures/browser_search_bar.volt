use browser_search_bar
use process

fn main() -> i64:
    let value: string = ""
    match arg_at(1):
        Ok(argument): value = argument
        Err(error): return 2
    let out: [8193]char
    unsafe:
        let converted: i64 = browser_search_address(value, &out[0], 8193)
        if converted <= 0:
            put_str("address\n")
        else:
            put_str("search ")
            put_str((&out[0]) as string)
            nl()
    return 0
