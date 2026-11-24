# Thin VOLT frontend; VOLT_COMPILER must name an absolute compiler executable.
use process

unsafe extern fn getenv(name: ptr<char>) -> ptr<char>
link "-lc"

fn main() -> i64:
    let count: i64 = argc()
    let argv: ptr<ptr<char>>
    unsafe: argv = VOLT_rt_argv()
    let child_count: i64 = count + 3
    unsafe:
        let child_argv: ptr<ptr<char>> = mmap(child_count * 8) as ptr<ptr<char>>
        if (child_argv as i64) < 0:
            put_err("volt-launch: cannot allocate argv\n")
            return 1
        let compiler: ptr<char> = getenv("VOLT_COMPILER" as ptr<char>)
        if compiler == (0 as ptr<char>):
            put_str("volt-launch: set VOLT_COMPILER to an absolute compiler path\n")
            return 127
        child_argv[0] = compiler
        child_argv[1] = "--launch" as ptr<char>
        let i: i64 = 1
        while i < count:
            child_argv[i + 1] = argv[i]
            i += 1
        child_argv[child_count - 1] = 0 as ptr<char>
        match process_exec_wait(compiler as string, &child_argv[0]):
            Ok(status):
                munmap(child_argv as ptr<char>, child_count * 8)
                return status
            Err(error):
                put_err("volt-launch: cannot start volt from PATH, errno ")
                put_int(error as i64)
                nl()
                munmap(child_argv as ptr<char>, child_count * 8)
                return 127
    return 127
