use fs

# Importing fs must not make the legacy event names collide with our own.
fn poll() -> i64:
    return 0

fn check_pipe() -> Result<i64, fs.IoError>:
    let handle = fs.open_owned("pipe")?
    let ready = fs.wait_readable(&handle, poll())?
    let data: [1]u8
    let count = fs.read_into(&handle, mut data[0..1])?
    let after = fs.wait_readable(&handle, 0)?
    print(ready, count, data[0], after)
    return fs.wait_readable(&handle, -2)

match check_pipe():
    Ok(flags): panic("accepted an invalid timeout\n")
    Err(error): print("err", fs.errno(error))
