module fs
use fs_legacy

# Do not let an older compiler treat OwnedFd as a freely copyable record.
const __VOLT_OWNED_FD_CHECK: __VoltOwnedFdV1 = 0

pub struct Descriptor:
    fd: i64

# Owning file descriptor. Move-only: it closes itself exactly once when
# the owning scope exits; construct it only through open_owned.
pub struct OwnedFd:
    fd: i64

pub struct FileInfo:
    size: i64

pub struct IoError:
    code: i32

unsafe native fn open_readonly(path: ptr<char>) -> i64:
{
    mov eax, 2
    mov esi, 0x80000
    xor edx, edx
    syscall
}

pub fn open(path: string) -> Result<Descriptor, IoError>:
    let fd: i64
    unsafe: fd = open_readonly(path as ptr<char>)
    if fd < 0: return Err(IoError((0 - fd) as i32))
    return Ok(Descriptor(fd))

# Close exactly once; a Descriptor is copyable and this is not automatic ownership.
pub unsafe fn close_file(handle: Descriptor) -> Result<i64, IoError>:
    let status = close(handle.fd)
    if status < 0: return Err(IoError((0 - status) as i32))
    return Ok(status)

# Open read-only with automatic close: the OwnedFd owner drops at scope exit.
pub fn open_owned(path: string) -> Result<OwnedFd, IoError>:
    let fd: i64
    unsafe: fd = open_readonly(path as ptr<char>)
    if fd < 0: return Err(IoError((0 - fd) as i32))
    return Ok(OwnedFd(fd))

# &handle is accepted only as an immediate argument to this reader.
pub fn owned_fd_number(handle: ptr<OwnedFd>) -> i64:
    unsafe: return handle.fd

# Automatic drop; the close error is deliberately ignored.
fn __volt_owned_fd_close(handle: ptr<OwnedFd>):
    unsafe: close(handle.fd)

pub fn stat(path: string) -> Result<FileInfo, IoError>:
    match file_size(path):
        Ok(size): return Ok(FileInfo(size))
        Err(code): return Err(IoError(code))

pub fn size(info: FileInfo) -> i64:
    return info.size

pub fn errno(error: IoError) -> i32:
    return error.code
