use fs
use owned_buffer

# A FIFO without a writer: read_all must fail fast (O_NONBLOCK open, then the
# fstat rejects the FIFO with ESPIPE) instead of blocking in open(2).
match fs.read_all("pipe", 1024):
    Ok(buffer): print("ok", owned_buffer_len(&buffer))
    Err(error): print("err", fs.errno(error))
