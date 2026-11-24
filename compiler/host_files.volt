use cv_text
use process
use bytes

let cc_error_file: i64 = 0
let cc_error_line: i64 = 1
let cc_root: i64 = 0
let cc_std: i64 = 0
let cc_cwd: i64 = 0

unsafe fn cc_error(msg: i64, file: i64, line: i64):
    let where: i64 = file
    let number: i64 = line
    if where == 0:
        where = cc_error_file
        if number == 0: number = cv_i(cc_error_line)
    if where != 0:
        let out: i64 = cv_list()
        cv_push(out, where)
        cv_push(out, cv_text(":"))
        if number == 0: number = cv_i(1)
        cv_push(out, cv_str(number))
        cv_push(out, cv_text(": ошибка: "))
        put_err(cv_cptr(cv_join(cv_text(""), out)) as string)
    else:
        put_err("volt: ")
    put_errnl(cv_cptr(msg) as string)
    exit(1)

unsafe native fn cc_getcwd(buf: ptr<char>, size: i64) -> i64:
{
    mov eax, 79
    syscall
}

unsafe native fn cc_readlink(path: ptr<char>, buf: ptr<char>, n: i64) -> i64:
{
    mov eax, 89
    syscall
}

unsafe native fn cc_rename(old: ptr<char>, new: ptr<char>) -> i64:
{
    mov eax, 82
    syscall
}

unsafe native fn cc_unlink(path: ptr<char>) -> i64:
{
    mov eax, 87
    syscall
}

unsafe native fn cc_mkdir(path: ptr<char>, mode: i64) -> i64:
{
    mov eax, 83
    syscall
}

unsafe native fn cc_chmod(fd: i64, mode: i64) -> i64:
{
    mov eax, 91
    syscall
}

unsafe native fn cc_access(path: ptr<char>, mode: i64) -> i64:
{
    mov eax, 21
    syscall
}

unsafe native fn cc_random(out: ptr<char>, count: i64) -> i64:
{
    xor edx, edx
    mov eax, 318
    syscall
}

unsafe native fn cc_isatty(fd: i64, state: ptr<char>) -> i64:
{
    mov rdx, rsi
    mov esi, 0x5401
    mov eax, 16
    syscall
}

unsafe fn cc_path_join(dir: i64, path: i64) -> i64:
    if cv_starts(path, cv_text("/")): return path
    if cv_len(dir) == 0: return path
    if cv_ends(dir, cv_text("/")): return cv_cat(dir, path)
    return cv_cat(cv_cat(dir, cv_text("/")), path)

unsafe fn cc_dirname(path: i64) -> i64:
    let n: i64 = cv_len(path)
    while n > 0:
        n -= 1
        if cv_byte(path, n) == '/': return cv_subtext(path, 0, max(1, n))
    return cv_text("")

unsafe fn cc_basename(path: i64) -> i64:
    let n: i64 = cv_len(path)
    let i: i64 = n
    while i > 0 and cv_byte(path, i - 1) != '/': i -= 1
    return cv_subtext(path, i, n - i)

unsafe fn cc_abspath(path: i64) -> i64:
    let absolute: i64 = cc_path_join(cc_cwd, path)
    let parts: i64 = cv_split(absolute, cv_text("/"), 0)
    let out: i64 = cv_list()
    for i in 0..cv_len(parts):
        let part: i64 = cv_at(parts, i)
        if cv_len(part) == 0 or cv_name(part, "."): continue
        if cv_name(part, ".."):
            if cv_len(out) != 0: cv_pop(out)
        else:
            cv_push(out, part)
    return cv_cat(cv_text("/"), cv_join(cv_text("/"), out))

unsafe fn cc_exists(path: i64) -> bool:
    return cc_access(cv_cptr(path), 4) == 0

unsafe fn cc_regular(path: i64) -> bool:
    let metadata: [32]u64
    if cc_file_metadata(cv_cptr(path), &metadata[0]) != 0: return false
    return (metadata[3] >> 32) & 0xf000 == 0x8000

unsafe native fn cc_file_metadata(path: ptr<char>, metadata: ptr<u64>) -> i64:
{
    mov r8, rsi
    mov rsi, rdi
    mov rdi, -100
    xor edx, edx
    mov r10d, 0x201
    mov eax, 332
    syscall
}

unsafe fn cc_read_file(path: i64, buf: ptr<ByteBuffer>, limit: i64):
    let fd: i64 = open(cv_cptr(path) as string, 0x80000, 0)
    if fd < 0: cc_error(cv_cat(cv_text("не удалось открыть "), path), 0, 0)
    defer close(fd)
    while true:
        let count: i64 = min(65536, limit - buf.len + 1)
        if count <= 0: cc_error(cv_cat(cv_text("слишком большой файл "), path), 0, 0)
        if bytes_reserve(buf, buf.len + count + 1) < 0: panic("volt: out of memory\n")
        let n: i64 = read(fd, (buf.data + buf.len) as ptr<char>, count)
        if n == -4: continue
        if n < 0: cc_error(cv_cat(cv_text("не удалось прочитать "), path), 0, 0)
        if n == 0: break
        buf.len += n
    if buf.len > limit: cc_error(cv_cat(cv_text("слишком большой файл "), path), 0, 0)

unsafe fn cc_read_text(path: i64) -> i64:
    if not cc_regular(path): cc_error(cv_cat(cv_text("файл не найден: "), path), 0, 0)
    let buffer: ByteBuffer
    cc_read_file(path, &buffer, 8388608)
    for i in 0..buffer.len:
        if buffer.data[i] == 0: cc_error(cv_text("в исходном файле недопустим NUL"), path, cv_i(1))
    let text: i64 = cv_text(cv_cstring(buffer.data as ptr<char>, buffer.len))
    bytes_free(&buffer)
    return text

unsafe fn cc_environment(name: i64) -> i64:
    let values: ptr<ptr<char>> = environment()
    let prefix: i64 = cv_cat(name, cv_text("="))
    let n: i64 = cv_len(prefix)
    let i: i64 = 0
    while values[i] != (0 as ptr<char>):
        if cv_starts(cv_text(values[i] as string), prefix): return cv_text((values[i] + n) as string)
        i += 1
    return 0

unsafe fn cc_find_root():
    let buffer: [4096]char
    if cc_getcwd(&buffer[0], 4096) < 0: panic("volt: cannot resolve working directory\n")
    cc_cwd = cv_text(cv_cstring(&buffer[0], __volt_strlen(&buffer[0])))
    let length: i64 = cc_readlink("/proc/self/exe" as ptr<char>, &buffer[0], 4096)
    if length <= 0 or length == 4096: panic("volt: cannot resolve compiler path\n")
    let directory: i64 = cc_dirname(cv_text(cv_cstring(&buffer[0], length)))
    while not cc_exists(cc_path_join(directory, cv_text("vstd/io.volt"))):
        let parent: i64 = cc_dirname(directory)
        if cv_equal(parent, directory) or cv_len(parent) == 0: panic("volt: vstd/io.volt not found beside compiler or above it\n")
        directory = parent
    cc_root = directory
    cc_std = cc_path_join(directory, cv_text("vstd"))

unsafe fn cc_mkdirs(dir: i64):
    if cv_len(dir) == 0 or cc_exists(dir): return
    cc_mkdirs(cc_dirname(dir))
    if cc_mkdir(cv_cptr(dir), 511) < 0 and not cc_exists(dir):
        cc_error(cv_cat(cv_text("не удалось создать каталог "), dir), 0, 0)

struct CCOutput:
    fd: i64
    path: i64

unsafe fn cc_open_output(dir: i64, prefix: string) -> CCOutput:
    for attempt in 0..16:
        let token: u64 = 0
        let n: i64 = cc_random((&token) as ptr<char>, 8)
        if n != 8:
            if n == -4: continue
            panic("volt: cannot generate temporary filename\n")
        let name: i64 = cv_cat(cv_text(prefix), cv_digits(cv_u(token), 16))
        let path: i64 = cc_path_join(dir, name)
        let fd: i64 = open(cv_cptr(path) as string, 0x800c1, 384)
        if fd >= 0: return CCOutput(fd, path)
        if fd != -17: break
    cc_error(cv_cat(cv_text("не удалось создать временный файл в "), dir), 0, 0)
    return CCOutput(-1, 0)

unsafe fn cc_store(file: CCOutput, data: ptr<char>, size: i64, mode: i64):
    let written: i64 = write_all(file.fd, data, size)
    let status: i64 = cc_chmod(file.fd, mode)
    let closed: i64 = close(file.fd)
    if written != size or status < 0 or closed < 0:
        cc_unlink(cv_cptr(file.path))
        cc_error(cv_cat(cv_text("не удалось записать "), file.path), 0, 0)

unsafe fn cc_write_file(path: i64, data: ptr<char>, size: i64, mode: i64):
    let dir: i64 = cc_dirname(cc_abspath(path))
    cc_mkdirs(dir)
    let file: CCOutput = cc_open_output(dir, ".volt-output-")
    cc_store(file, data, size, mode)
    if cc_rename(cv_cptr(file.path), cv_cptr(path)) < 0:
        cc_unlink(cv_cptr(file.path))
        cc_error(cv_cat(cv_text("не удалось сохранить "), path), 0, 0)
