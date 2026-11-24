# модуль: глобальные const + инициализация
let base: i64 = 100
let banner: string = "[mod]"

fn scale(x: i64) -> i64:
    return x * 2

fn greet(name: string):
    put_str(banner)
    put_str(" hello ")
    put_str(name)
    nl()

let ready: bool = true
