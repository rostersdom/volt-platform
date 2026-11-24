# Linux x86-64 process arguments from the initial stack.

unsafe extern fn VOLT_rt_argc() -> i64
unsafe extern fn VOLT_rt_argv() -> ptr<ptr<char>>
unsafe extern fn VOLT_rt_envp() -> ptr<ptr<char>>

unsafe native fn __volt_process_fork() -> i64:
{
    mov rax, 57
    syscall
}

unsafe native fn __volt_process_execve(path: ptr<char>, argv: ptr<ptr<char>>, envp: ptr<ptr<char>>) -> i64:
{
    mov rax, 59
    syscall
}

unsafe native fn __volt_process_wait4(pid: i64, status: ptr<i32>, options: i64, usage: ptr<char>) -> i64:
{
    mov r10, rcx
    mov rax, 61
    syscall
}

unsafe native fn __volt_process_exit(code: i64):
{
    mov rax, 60
    syscall
}

fn argc() -> i64:
    let count: i64
    unsafe: count = VOLT_rt_argc()
    return count

unsafe fn environment() -> ptr<ptr<char>>:
    let values: ptr<ptr<char>>
    unsafe: values = VOLT_rt_envp()
    return values

fn arg_at(index: i64) -> Result<string, i32>:
    let count: i64 = argc()
    if index < 0 or index >= count:
        return Err(22 as i32)
    let argv: ptr<ptr<char>>
    let value: ptr<char>
    let result: string
    unsafe:
        argv = VOLT_rt_argv()
        value = argv[index]
        result = value as string
    return Ok(result)

# Executes one program without a shell and returns its exit status.
unsafe fn process_exec_wait(path: string, arguments: ptr<ptr<char>>) -> Result<i64, i32>:
    let values: ptr<ptr<char>> = environment()
    let pid: i64 = __volt_process_fork()
    if pid < 0: return Err((0 - pid) as i32)
    if pid == 0:
        let status: i64 = __volt_process_execve(path as ptr<char>, arguments, values)
        if status < 0:
            __volt_process_exit(127)
        __volt_process_exit(127)
    let child_status: [1]i32
    let waited: i64 = 0
    while waited == 0:
        let result: i64 = __volt_process_wait4(pid, &child_status[0], 0, 0 as ptr<char>)
        if result == -4:
            continue
        if result < 0: return Err((0 - result) as i32)
        if result != pid: return Err(10 as i32)
        waited = 1
    let status_bits: i64 = child_status[0] as i64
    if (status_bits & 127) == 0:
        return Ok((status_bits >> 8) & 255)
    return Ok(128 + (status_bits & 127))
