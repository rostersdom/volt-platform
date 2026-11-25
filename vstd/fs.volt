module fs
use fs_legacy
use bytes
use owned_buffer

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

# Synthetic errnos reported by read_all, next to the kernel ones: EINVAL for a
# non-positive limit, EFBIG when the file is larger than the limit (the same
# code the kernel uses for a file too large for the offset/type limits).
const ERR_INVALID_LIMIT: i32 = 22
const ERR_FILE_TOO_LARGE: i32 = 27

# Read a whole file into a fresh OwnedBuffer, at most max_bytes bytes.
# Never panics: a missing or unreadable file, an allocation failure (ENOMEM
# from mmap) and a short I/O error all surface as Err with a positive errno.
# The limit is enforced by stat before reading (EFBIG) and again while reading,
# so a file that grows past max_bytes mid-read is rejected too. An empty file
# and a file of exactly max_bytes are valid; max_bytes <= 0 is Err(EINVAL).
# On a mid-read error the descriptor is closed and the partial buffer freed
# before Err returns; once the bytes become an OwnedBuffer, its automatic
# drop covers the remaining error paths, so no path leaks.
pub fn read_all(path: string, max_bytes: i64) -> Result<OwnedBuffer, IoError>:
    if max_bytes <= 0: return Err(IoError(ERR_INVALID_LIMIT))
    let info = stat(path)?
    if info.size > max_bytes: return Err(IoError(ERR_FILE_TOO_LARGE))
    let handle = open(path)?
    let storage: ByteBuffer
    let failed: i32 = 0
    let done: bool = false
    unsafe:
        # One byte of read room past the limit detects a file that grows
        # past max_bytes while it is being read.
        while not done:
            let remaining: i64 = max_bytes - storage.len
            let room: i64 = 4096
            if remaining < 4096: room = remaining + 1
            let reserved: i64 = bytes_reserve(&storage, storage.len + room)
            if reserved < 0:
                failed = (0 - reserved) as i32
                done = true
            else:
                let n: i64 = read(handle.fd, storage.data + storage.len, room)
                if n < 0:
                    if n != -4:  # EINTR: retry
                        failed = (0 - n) as i32
                        done = true
                elif n == 0:
                    done = true
                else:
                    storage.len = storage.len + n
                    if storage.len > max_bytes:
                        failed = ERR_FILE_TOO_LARGE
                        done = true
        if failed != 0: bytes_free(&storage)
    if failed != 0:
        unsafe: close_file(handle)
        return Err(IoError(failed))
    let buffer = owned_buffer_from_bytes(storage)
    let status: i64
    unsafe: status = close(handle.fd)
    # Live `buffer` is dropped automatically on this error return.
    if status < 0: return Err(IoError((0 - status) as i32))
    return Ok(buffer)
