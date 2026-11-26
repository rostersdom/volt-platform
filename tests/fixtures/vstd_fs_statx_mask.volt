use fs

unsafe native fn probe_getfd(fd: i64) -> i64:
{
    mov eax, 72
    mov esi, 1
    syscall
}

# Predict the descriptor number without assuming it is always 3.
let fd: i64
unsafe:
    fd = open("payload.bin" as ptr<char>, 0, 0)
    if fd < 0: panic("fixture open failed\n")
    close(fd)

match fs.read_all("payload.bin", 128):
    Ok(buffer): panic("accepted unconfirmed metadata\n")
    Err(error): print("err", fs.errno(error))

unsafe: print("fd", probe_getfd(fd))
