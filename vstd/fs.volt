# Linux x86-64 file metadata via statx, without libc.
const AT_FDCWD: i64 = -100
const STATX_SIZE: i64 = 0x200
const ERR_NOT_SUPPORTED: i32 = 95

unsafe native fn __volt_fs_statx(dirfd: i64, path: ptr<char>, flags: i64, mask: i64, metadata: ptr<u64>) -> i64:
{
    mov r10, rcx
    mov rax, 332
    syscall
}

fn file_size(path: string) -> Result<i64, i32>:
    let metadata: [32]u64
    let status: i64
    unsafe: status = __volt_fs_statx(AT_FDCWD, path as ptr<char>, 0, STATX_SIZE, &metadata[0])
    if status < 0:
        return Err((0 - status) as i32)
    if metadata[0] & STATX_SIZE == 0:
        return Err(ERR_NOT_SUPPORTED)
    if metadata[5] > 0x7fffffffffffffff:
        return Err(75 as i32)
    return Ok(metadata[5] as i64)
