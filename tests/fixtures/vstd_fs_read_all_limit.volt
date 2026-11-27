use fs
use owned_buffer

match fs.read_all("payload.bin", 4096):
    Ok(buffer): print("ok", owned_buffer_len(&buffer), owned_buffer_get(&buffer, 4095) as i64)
    Err(error): print("err", fs.errno(error))
