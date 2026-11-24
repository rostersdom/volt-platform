use cv_text
use process
use bytes
use utf8

let cc_error_file: i64 = 0
let cc_error_line: i64 = 1
let cc_sources: i64 = 0
let cc_root: i64 = 0
let cc_std: i64 = 0
let cc_cwd: i64 = 0

# Escape terminal controls and malformed UTF-8 without changing ordinary text.
unsafe fn cc_diag_text(p: ptr<char>, size: i64, mark: i64, excerpt: bool) -> i64:
    let hex: ptr<char> = "0123456789abcdef" as ptr<char>
    let escaped: [4]char = ['\\', 'x', '0', '0']
    let pos: i64 = 0
    let pending: i64 = 0
    let width: i64 = 0
    let caret: i64 = -1
    while pos < size:
        let at: i64 = pos
        if at == mark: caret = width
        let code: i64 = utf8_next(p, &pos, size)
        let control: bool = code < 32 or (code >= 127 and code <= 159) or (code == 0xfffd and pos == at + 1)
        let bidi: bool = code == 0x061c or code == 0x200e or code == 0x200f or (code >= 0x2028 and code <= 0x202e) or (code >= 0x2066 and code <= 0x2069)
        if control or bidi:
            if at > pending: write_all(2, p + pending, at - pending)
            if excerpt and code == 9:
                put_err("    ")
            else:
                let byte: i64 = p[at] as i64
                escaped[2] = hex[byte >> 4]
                escaped[3] = hex[byte & 15]
                write_all(2, &escaped[0], 4)
            pos = at + 1
            pending = pos
            if width >= 0: width += 4
        elif code >= 128:
            # shortcut: report the exact byte column without a caret if terminal cell widths are unknown.
            width = -1
        elif width >= 0:
            width += 1
    if size > pending: write_all(2, p + pending, size - pending)
    if mark == size: return width
    return caret

unsafe fn cc_diag_excerpt(p: ptr<char>, size: i64, line: i64, column: i64):
    let begin: i64 = 0
    let number: i64 = 1
    while number < line and begin < size:
        if p[begin] == '\n': number += 1
        begin += 1
    if number != line: return
    let end: i64 = begin
    while end < size and p[end] != '\n': end += 1
    if end > begin and p[end - 1] == '\r': end -= 1
    let mark: i64 = -1
    if column > 0 and column <= end - begin + 1: mark = begin + column - 1
    let left: i64 = max(begin, min(mark - 60, end - 120))
    let right: i64 = min(end, left + 120)
    # Do not split a UTF-8 sequence at a truncation marker.
    for i in 0..3:
        if left > begin and p[left] & 0xc0 == 0x80: left += 1
        if right < end and p[right] & 0xc0 == 0x80: right -= 1
    put_err("  | ")
    if left > begin: put_err("...")
    let offset: i64 = cc_diag_text(p + left, right - left, mark - left, true)
    if right < end: put_err("...")
    put_err("\n")
    if mark < 0:
        put_errnl("  = колонка неизвестна")
        return
    if offset >= 0:
        if left > begin: offset += 3
        put_err("  | ")
        put_err(cv_cptr(cv_pad(cv_text(""), offset, ' ')) as string)
        put_err("^ ")
    else:
        put_err("  = ")
    put_err("байтовая колонка ")
    put_errnl(cv_cptr(cv_str(cv_i(column))) as string)

unsafe fn cc_diagnostic(msg: i64, file: i64, line: i64, column: i64, source: ptr<char>, size: i64):
    if file != 0:
        cc_diag_text(cv_cptr(file), cv_len(file), -1, false)
        put_err(":")
        put_err(cv_cptr(cv_str(cv_i(max(1, line)))) as string)
        put_err(": ошибка: ")
    else:
        put_err("volt: ")
    let message: ptr<char> = cv_cptr(msg)
    let length: i64 = cv_len(msg)
    let shown: i64 = min(length, 512)
    while shown < length and message[shown] & 0xc0 == 0x80 and shown > 509: shown -= 1
    cc_diag_text(message, shown, -1, false)
    if shown < length: put_err("...")
    put_err("\n")
    if source != (0 as ptr<char>) and line > 0: cc_diag_excerpt(source, size, line, column)
    exit(1)

# line is the existing tagged CV value; column is a 1-based byte index, or 0 if unknown.
unsafe fn cc_error_at(msg: i64, file: i64, line: i64, column: i64):
    let where: i64 = file
    let number: i64 = line
    if where == 0:
        where = cc_error_file
        if number == 0: number = cv_i(cc_error_line)
    let line_number: i64 = 0
    if where != 0 and number != 0: line_number = cv_index(number)
    let source: i64 = 0
    # A diagnostic file can also be a library path; never reopen it as source.
    if where != 0: source = cv_get(cc_sources, where, 0)
    if source != 0:
        cc_diagnostic(msg, where, line_number, column, cv_cptr(source), cv_len(source))
    else:
        cc_diagnostic(msg, where, line_number, column, 0 as ptr<char>, 0)

unsafe fn cc_error(msg: i64, file: i64, line: i64):
    cc_error_at(msg, file, line, 0)

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
    mov r10d, 0x301    # STATX_TYPE | STATX_INO | STATX_SIZE
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

unsafe fn cc_read_text_limit(path: i64, limit: i64) -> i64:
    if not cc_regular(path): cc_error(cv_cat(cv_text("файл не найден: "), path), 0, 0)
    let buffer: ByteBuffer
    cc_read_file(path, &buffer, limit)
    let line: i64 = 1
    let begin: i64 = 0
    for i in 0..buffer.len:
        if buffer.data[i] == 0:
            cc_diagnostic(cv_text("в исходном файле недопустим NUL"), path, line, i - begin + 1, buffer.data as ptr<char>, buffer.len)
        if buffer.data[i] == 10:
            line += 1
            begin = i + 1
    let text: i64 = cv_text(cv_cstring(buffer.data as ptr<char>, buffer.len))
    bytes_free(&buffer)
    if cc_sources == 0: cc_sources = cv_dict()
    cv_set(cc_sources, path, text)
    return text

unsafe fn cc_read_text(path: i64) -> i64:
    return cc_read_text_limit(path, 8388608)

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
