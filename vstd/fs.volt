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

# O_RDONLY | O_CLOEXEC | O_NONBLOCK: open(2) never waits on a FIFO without a
# writer; the fstat on the returned descriptor decides whether read_all may
# read it. O_NONBLOCK does not change read(2) on a regular file.
unsafe native fn open_readonly_nonblock(path: ptr<char>) -> i64:
{
    mov eax, 2
    mov esi, 0x80800
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

# &handle is accepted only as an immediate argument to these readers.
pub fn owned_fd_number(handle: ptr<OwnedFd>) -> i64:
    unsafe: return handle.fd

# One read(2) attempt from the owned descriptor into dst. Ok(n) counts bytes
# and Ok(0) is end of file; an empty dst is rejected with Err(EINVAL) so Ok(0)
# never means an empty buffer. Other positive errnos (including EINTR) are
# returned as-is; retry after EINTR if desired. The raw descriptor number
# never leaves the OwnedFd.
pub fn read_into(handle: ptr<OwnedFd>, dst: []mut u8) -> Result<i64, IoError>:
    if len(dst) == 0: return Err(IoError(22))  # EINVAL
    let n: i64
    unsafe: n = read(handle.fd, &dst[0], len(dst))
    if n < 0: return Err(IoError((0 - n) as i32))
    return Ok(n)

# Reader-shaped helper for close_owned: hand out the raw descriptor and mark
# the owner consumed, so the automatic drop below skips it.
fn __volt_owned_fd_take(handle: ptr<OwnedFd>) -> i64:
    let raw: i64
    unsafe:
        raw = handle.fd
        handle.fd = -1
    return raw

# Close the descriptor explicitly, consuming its owner: the moved argument is
# gone from the caller's scope, and the automatic drop will not close the
# descriptor again. A close(2) error is returned as Err, but the owner is
# still considered consumed — on Linux a failed close leaves the descriptor
# state unknown and must not be retried.
pub fn close_owned(handle: OwnedFd) -> Result<i64, IoError>:
    let raw = __volt_owned_fd_take(&handle)
    let status: i64
    unsafe: status = close(raw)
    if status < 0: return Err(IoError((0 - status) as i32))
    return Ok(status)

# Automatic drop; the close error is deliberately ignored. A descriptor
# consumed by close_owned carries fd = -1 and is not closed again.
fn __volt_owned_fd_close(handle: ptr<OwnedFd>):
    unsafe:
        if handle.fd >= 0: close(handle.fd)

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
# code the kernel uses for a file too large for the offset/type limits),
# EISDIR for a directory and ESPIPE for any other non-regular file (FIFO,
# socket, device): read_all reads only regular files.
const ERR_INVALID_LIMIT: i32 = 22
const ERR_FILE_TOO_LARGE: i32 = 27
const ERR_DIRECTORY: i32 = 21
const ERR_NOT_REGULAR: i32 = 29

# Read a whole regular file into a fresh OwnedBuffer, at most max_bytes bytes.
# Never panics and never hangs on a FIFO: the file is opened with O_NONBLOCK,
# then fstat on the OPEN descriptor (no stat→open race) rejects every
# non-regular file before any read — EISDIR for a directory, ESPIPE for a
# FIFO, socket or device. The size and the limit come from the same fstat.
# A missing or unreadable file, an allocation failure (ENOMEM from mmap) and
# a short I/O error all surface as Err with a positive errno. The limit is
# enforced by the fstat before reading (EFBIG) and again while reading, so a
# file that grows past max_bytes mid-read is rejected too. An empty file and
# a file of exactly max_bytes are valid; max_bytes <= 0 is Err(EINVAL).
# On a mid-read error the descriptor is closed and the partial buffer freed
# before Err returns; once the bytes become an OwnedBuffer, its automatic
# drop covers the remaining error paths, so no path leaks.
pub fn read_all(path: string, max_bytes: i64) -> Result<OwnedBuffer, IoError>:
    if max_bytes <= 0: return Err(IoError(ERR_INVALID_LIMIT))
    let fd: i64
    unsafe: fd = open_readonly_nonblock(path as ptr<char>)
    if fd < 0: return Err(IoError((0 - fd) as i32))
    let failed: i32 = 0
    let metadata: [32]u64
    unsafe:
        match fd_stat(fd, &metadata[0]):
            Ok(status):
                let base = &metadata[0]
                let words = base as ptr<u32>
                let mode: i64 = (words[7] & 0xffff) as i64
                if (mode & 0xf000) == 0x4000:
                    failed = ERR_DIRECTORY
                elif (mode & 0xf000) != 0x8000:
                    failed = ERR_NOT_REGULAR
                elif metadata[5] > 0x7fffffffffffffff:
                    failed = 75  # EOVERFLOW, как в file_size
                elif (metadata[5] as i64) > max_bytes:
                    failed = ERR_FILE_TOO_LARGE
            Err(code): failed = code
    if failed != 0:
        unsafe: close(fd)
        return Err(IoError(failed))
    let storage: ByteBuffer
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
                let n: i64 = read(fd, storage.data + storage.len, room)
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
        unsafe: close(fd)
        return Err(IoError(failed))
    unsafe:
        let buffer = owned_buffer_from_bytes(&storage)
        let status: i64 = close(fd)
        # Live `buffer` is dropped automatically on this error return.
        if status < 0: return Err(IoError((0 - status) as i32))
        return Ok(buffer)
