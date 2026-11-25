use fs

# fs.read_into keeps the raw descriptor inside the OwnedFd: the slice carries
# both the pointer and the length, Ok(0) is end of file, and a directory
# descriptor surfaces the kernel's EISDIR. The `if true` blocks end each
# mutable slice borrow before the underlying array is read again.
match fs.open_owned("payload.bin"):
    Ok(handle):
        let space: [16]u8
        let first: Result<i64, fs.IoError> = Ok(0)
        if true: first = fs.read_into(&handle, mut space[0..16])
        match first:
            Ok(n):
                let sum: i64 = 0
                let i: i64 = 0
                while i < n:
                    sum = sum + space[i] as i64
                    i = i + 1
                print("first", n, sum)
            Err(error): panic("read failed")
        let second: Result<i64, fs.IoError> = Ok(0)
        if true: second = fs.read_into(&handle, mut space[0..16])
        match second:
            Ok(n): print("eof", n)
            Err(error): panic("read failed")
        let empty: Result<i64, fs.IoError> = Ok(0)
        if true: empty = fs.read_into(&handle, mut space[0..0])
        match empty:
            Ok(n): panic("empty slice must not read")
            Err(error): print("empty", fs.errno(error))
    Err(error): panic("open failed")
match fs.open_owned("adir"):
    Ok(handle):
        let tiny: [4]u8
        let dirstat: Result<i64, fs.IoError> = Ok(0)
        if true: dirstat = fs.read_into(&handle, mut tiny[0..4])
        match dirstat:
            Ok(n): panic("directory must not read")
            Err(error): print("dir", fs.errno(error))
    Err(error): panic("open failed")
print("done")
