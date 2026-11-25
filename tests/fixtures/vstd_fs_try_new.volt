use owned_buffer

# Deterministic ENOMEM regardless of the machine's free memory: cap the
# address space with setrlimit, then consume the rest with direct mmap calls
# until less than one chunk remains. The next allocation must fail with
# ENOMEM, and owned_buffer_try_new must report it instead of panicking.
unsafe native fn set_rlimit(resource: i64, limits: ptr<u64>) -> i64:
{
    mov eax, 160
    syscall
}

fn report(label: string, result: Result<OwnedBuffer, i32>):
    match result:
        Ok(buffer): print(label, "ok", owned_buffer_len(&buffer))
        Err(code): print(label, "err", code)

report("small", owned_buffer_try_new("abc"))
let wrapped = owned_buffer_new("ok")
print("new", owned_buffer_len(&wrapped))
let big = "x" * 1000000
let limits: [2]u64
limits[0] = 67108864
limits[1] = 67108864
let status: i64
unsafe: status = set_rlimit(9, &limits[0])  # RLIMIT_AS, 64 MiB
print("rlimit", status)
let i: i64 = 0
let full: bool = false
while i < 1024 and not full:
    let p: ptr<char>
    let mapped: i64 = 0
    unsafe:
        p = mmap(1048576)
        mapped = p as i64
    if mapped < 0:
        full = true
    else:
        i = i + 1
report("huge", owned_buffer_try_new(big))
print("done")
