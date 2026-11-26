# Legacy flat filesystem functions; `use fs` still loads these during migration.
# Linux x86-64, without libc. Err contains a positive errno.
# Mutations are synchronous and return Ok(0) on success.
# Paths are NUL-terminated and resolved by Linux (relative to cwd); parent
# symlinks and normal trailing-slash rules apply. This is not path confinement.
const AT_FDCWD: i64 = -100
const FS_AT_REMOVEDIR: i64 = 0x200
const FS_RENAME_NOREPLACE: i64 = 1
const STATX_TYPE: i64 = 0x1
const STATX_SIZE: i64 = 0x200
const FS_AT_EMPTY_PATH: i64 = 0x1000
const ERR_NOT_SUPPORTED: i32 = 95

unsafe native fn __volt_fs_statx(dirfd: i64, path: ptr<char>, flags: i64, mask: i64, metadata: ptr<u64>) -> i64:
{
    mov r10, rcx
    mov rax, 332
    syscall
}

# Query logical size, following the final symlink.
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

unsafe native fn __volt_fs_mkdirat(dirfd: i64, path: ptr<char>, mode: i64) -> i64:
{
    mov rax, 258
    syscall
}

unsafe native fn __volt_fs_renameat2(oldfd: i64, old_path: ptr<char>, newfd: i64, new_path: ptr<char>, flags: i64) -> i64:
{
    mov r10, rcx
    mov rax, 316
    syscall
}

unsafe native fn __volt_fs_unlinkat(dirfd: i64, path: ptr<char>, flags: i64) -> i64:
{
    mov rax, 263
    syscall
}

fn __volt_fs_path_status(status: i64) -> Result<i64, i32>:
    if status < 0: return Err((0 - status) as i32)
    return Ok(status)

# Query an already open descriptor by handle (statx with AT_EMPTY_PATH), not
# by path: there is no stat→open race. Only return metadata whose stx_mask
# confirms both stx_mode's file type and stx_size.
unsafe fn fd_stat(fd: i64, metadata: ptr<u64>) -> Result<i64, i32>:
    let required: i64 = STATX_TYPE | STATX_SIZE
    let status: i64 = __volt_fs_statx(fd, "" as ptr<char>, FS_AT_EMPTY_PATH, required, metadata)
    if status >= 0 and (metadata[0] & required) != required:
        return Err(ERR_NOT_SUPPORTED)
    return __volt_fs_path_status(status)


# Create one directory. Only rwx permission bits (0o000..0o777) are accepted;
# the process umask or parent default ACL applies. Existing entries are errors.
fn create_dir(path: string, mode: i64) -> Result<i64, i32>:
    if mode < 0 or mode > 0x1ff: return Err(22 as i32)
    let status: i64
    unsafe: status = __volt_fs_mkdirat(AT_FDCWD, path as ptr<char>, mode)
    return __volt_fs_path_status(status)

# Atomically move an entry (including a symlink itself), never replacing a
# destination. If the kernel/filesystem rejects RENAME_NOREPLACE, return its errno.
fn rename_path(old_path: string, new_path: string) -> Result<i64, i32>:
    let status: i64
    unsafe: status = __volt_fs_renameat2(AT_FDCWD, old_path as ptr<char>, AT_FDCWD,
                                       new_path as ptr<char>, FS_RENAME_NOREPLACE)
    return __volt_fs_path_status(status)

# Unlink a non-directory entry; a final symlink is removed, not its target.
fn remove_file(path: string) -> Result<i64, i32>:
    let status: i64
    unsafe: status = __volt_fs_unlinkat(AT_FDCWD, path as ptr<char>, 0)
    return __volt_fs_path_status(status)

# Remove an empty directory only; no recursion and no following a final symlink.
fn remove_dir(path: string) -> Result<i64, i32>:
    let status: i64
    unsafe: status = __volt_fs_unlinkat(AT_FDCWD, path as ptr<char>, FS_AT_REMOVEDIR)
    return __volt_fs_path_status(status)
