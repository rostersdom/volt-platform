module fs
use fs_legacy

pub struct Descriptor:
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

pub fn stat(path: string) -> Result<FileInfo, IoError>:
    match file_size(path):
        Ok(size): return Ok(FileInfo(size))
        Err(code): return Err(IoError(code))

pub fn size(info: FileInfo) -> i64:
    return info.size

pub fn errno(error: IoError) -> i32:
    return error.code
