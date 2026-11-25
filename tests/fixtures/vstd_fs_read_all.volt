use fs
use owned_buffer

# The point of fs.read_all: propagate the buffer with `?` and never release
# it by hand; the live Ok is dropped automatically at the end of each match arm.
fn load(path: string, limit: i64) -> Result<OwnedBuffer, fs.IoError>:
    let buffer = fs.read_all(path, limit)?
    return Ok(buffer)

fn report(path: string, limit: i64):
    match load(path, limit):
        Ok(buffer):
            let sum: i64 = 0
            let i: i64 = 0
            while i < owned_buffer_len(&buffer):
                sum = sum + owned_buffer_get(&buffer, i) as i64
                i = i + 1
            print("ok", owned_buffer_len(&buffer), sum)
        Err(error):
            print("err", fs.errno(error))

report("payload.bin", 1024)   # binary bytes, read through `?`
report("missing.bin", 1024)   # ENOENT from open
report("payload.bin", 4)      # EFBIG: fstat sees 7 > 4 before any read
report("empty.bin", 16)       # empty file is valid
report("exact.bin", 6)        # exactly max_bytes is valid
report("exact.bin", 0)        # EINVAL: non-positive limit
report("exact.bin", -5)       # EINVAL: negative limit
report("adir", 1024)          # EISDIR from fstat on the open descriptor
report("pipe", 1024)          # ESPIPE: O_NONBLOCK open, fstat rejects the FIFO
print("done")
