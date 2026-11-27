# The helper runs on a private socket; all document data and edits are length-delimited.
use css
use process
use http
use fs
use sdl
use browser_fetch

const BROWSER_JS_INIT_MS: i64 = 750
const BROWSER_JS_CLICK_MS: i64 = 100
const BROWSER_JS_FETCH_MS: i64 = 3000
const BROWSER_JS_SCRIPT_LIMIT: i64 = 16
const BROWSER_JS_CODE_BYTES: i64 = 65536
const BROWSER_JS_DOM_BYTES: i64 = 16384
const BROWSER_JS_DOM_NODES: i64 = 128
const BROWSER_JS_REPLY_LIMIT: i64 = 40 + CSS_TEXT_OVERRIDE_LIMIT * (16 + CSS_OVERRIDE_BYTES) + BROWSER_JS_DOM_BYTES
const BROWSER_JS_POLICY: i64 = 3
const BROWSER_JS_WORKERS: i64 = 8
const BROWSER_JS_MSG_REPLY: i64 = 0
const BROWSER_JS_MSG_FETCH: i64 = 1
const BROWSER_JS_FETCH_BYTES: i64 = 262144
const BROWSER_JS_FRAME_LIMIT: i64 = BROWSER_JS_REPLY_LIMIT
const JS_SLOT_FREE: i32 = 0
const JS_SLOT_LIVE: i32 = 1
const JS_SLOT_RETIRED: i32 = 2
const JS_SLOT_REAPING: i32 = 3
const JS_FETCH_RUNNING: i32 = 0
const JS_FETCH_READY: i32 = 1
const JS_FETCH_ABANDONED: i32 = 2

struct BrowserJsChild:
    state: i32
    pidfd: i32
    pid: i64
    signalled: bool

struct BrowserWorker:
    pid: i64
    child: ptr<BrowserJsChild>
    fd: i64

struct BrowserJsFetchJob:
    state: i32
    deadline: i64
    method: i64
    body_len: i64
    origin: [8193]char
    url: [8193]char
    request_type: [129]char
    body: [262144]u8
    status: i64
    out: ByteBuffer
    content_type: [129]char
    final_url: [8193]char

struct BrowserJs:
    pid: i64
    child: ptr<BrowserJsChild>
    fd: i64
    target_count: i64
    targets: [64]i64
    text: ptr<CssTextOverrides>
    notice: i64
    origin: [8193]char
    fetch_job: ptr<BrowserJsFetchJob>
    dom_count: i64
    dom_ids: [128]i64
    dom_nodes: [128]i64

struct BrowserJsDocument:
    source: string
    nodes: ptr<HtmlNode>
    attributes: ptr<HtmlAttribute>
    node_count: i64

struct BrowserJsReply:
    text: ptr<CssTextOverrides>
    dom: ByteBuffer
    script_error: bool
    prevent_default: bool

struct BrowserJsClick:
    pid: i64
    deadline: i64
    request: [129]i64
    sent: i64
    received: i64
    length: i64
    phase: i64
    fetch_deadline: i64
    frame: ByteBuffer

struct BrowserJsScripts:
    frames: ByteBuffer
    count: i64
    source_bytes: i64

unsafe native fn __volt_js_readlink(path: ptr<char>, output: ptr<char>, capacity: i64) -> i64:
{
    mov eax, 89
    syscall
}

unsafe native fn __volt_js_socketpair(pair: ptr<i32>) -> i64:
{
    mov r10, rdi
    mov edi, 1                 # AF_UNIX
    mov esi, 0x80001           # SOCK_STREAM | SOCK_CLOEXEC
    xor edx, edx
    mov eax, 53
    syscall
}

unsafe native fn __volt_js_nonblock(fd: i64) -> i64:
{
    mov esi, 4                 # F_SETFL
    mov edx, 0x800             # O_NONBLOCK
    mov eax, 72
    syscall
}

unsafe native fn __volt_js_open_path(dir: i64, path: ptr<char>, flags: i64) -> i64:
{
    xor r10d, r10d
    mov eax, 257               # openat
    syscall
}

unsafe native fn __volt_js_dup(fd: i64) -> i64:
{
    mov esi, 1030              # F_DUPFD_CLOEXEC
    mov edx, 3
    mov eax, 72
    syscall
}

unsafe native fn __volt_js_euid() -> i64:
{
    mov eax, 107
    syscall
}

# Only raw syscalls between clone and exec, even when the parent has SDL threads.
unsafe native fn __volt_js_child_stdio(fd: i64, helper: i64, input: i64) -> i64:
{
    mov r8, rsi
    mov r9, rdx
    test rdi, rdi
    jz .Lvolt_js_clear_cloexec
    xor esi, esi
    xor edx, edx
    mov eax, 292               # dup3(fd, 0, 0)
    syscall
    jmp .Lvolt_js_close_deferred
.Lvolt_js_clear_cloexec:
    mov esi, 2                 # fcntl(0, F_SETFD, 0)
    xor edx, edx
    mov eax, 72
    syscall
.Lvolt_js_close_deferred:
    test rax, rax
    js .Lvolt_js_stdio_done
    mov edi, 1
    test r9, r9
    js .Lvolt_worker_close_fds
    mov rdi, r9
    mov esi, 1
    xor edx, edx
    mov eax, 292               # dup3(input, 1, 0) for the media worker
    syscall
    test rax, rax
    js .Lvolt_js_stdio_done
    mov edi, 2
.Lvolt_worker_close_fds:
    lea rsi, [r8-1]
    cmp rsi, rdi
    jb .Lvolt_worker_close_high
    xor edx, edx
    mov eax, 436               # close_range, Linux >= 5.9
    syscall
    test rax, rax
    js .Lvolt_js_stdio_done
.Lvolt_worker_close_high:
    lea rdi, [r8+1]
    mov esi, -1
    xor edx, edx
    mov eax, 436
    syscall
    test rax, rax
    js .Lvolt_js_stdio_done
    mov edi, 38                # PR_SET_NO_NEW_PRIVS before exec
    mov esi, 1
    xor r8d, r8d
    xor r10d, r10d
    mov eax, 157
    syscall
.Lvolt_js_stdio_done:
}

unsafe native fn __volt_js_exec(fd: i64, path: ptr<char>, args: ptr<ptr<char>>, env: ptr<ptr<char>>) -> i64:
{
    mov r10, rcx
    mov r8d, 0x1000            # AT_EMPTY_PATH: execute the verified open file.
    mov eax, 322               # execveat
    syscall
}

unsafe native fn __volt_js_fork(pidfd: ptr<i32>) -> i64:
{
    mov rdx, rdi
    mov edi, 0x1011            # clone(CLONE_PIDFD | SIGCHLD, NULL, pidfd, NULL, 0)
    xor esi, esi
    xor r10d, r10d
    xor r8d, r8d
    mov eax, 56
    syscall
}

unsafe native fn __volt_js_kill(pidfd: i64) -> i64:
{
    mov esi, 9
    xor edx, edx
    xor r10d, r10d
    mov eax, 424               # pidfd_send_signal; never signal a reused PID.
    syscall
}

unsafe native fn __volt_js_workers() -> ptr<BrowserJsChild>:
{
    .lcomm VOLT_js_workers, 256
    lea rax, [rip + VOLT_js_workers]
}

unsafe native fn __volt_js_transition(state: ptr<i32>, prior: i32, next: i32) -> bool:
{
    mov eax, esi
    lock cmpxchg dword ptr [rdi], edx
    sete al
    movzx eax, al
}

unsafe fn browser_js_reap():
    # Reap retired workers without blocking paint, navigation, or input.
    let slots: ptr<BrowserJsChild> = __volt_js_workers()
    let i: i64 = 0
    while i < BROWSER_JS_WORKERS:
        let child: ptr<BrowserJsChild> = &slots[i]
        i += 1
        if http_load_state(&child.state) != JS_SLOT_RETIRED or not __volt_js_transition(&child.state, JS_SLOT_RETIRED, JS_SLOT_REAPING): continue
        if not child.signalled:
            let sent: i64 = __volt_js_kill(child.pidfd as i64)
            child.signalled = sent == 0 or sent == -3
        let status: i32 = 0
        let waited: i64 = __volt_process_wait4(child.pid, &status, 1, 0 as ptr<char>)  # WNOHANG
        if waited == child.pid or waited == -10:
            close(child.pidfd as i64)
            __volt_js_transition(&child.state, JS_SLOT_REAPING, JS_SLOT_FREE)
        else:
            __volt_js_transition(&child.state, JS_SLOT_REAPING, JS_SLOT_RETIRED)

unsafe fn browser_js_claim() -> ptr<BrowserJsChild>:
    if sizeof(BrowserJsChild) * BROWSER_JS_WORKERS > 256: panic("JS worker registry size")
    browser_js_reap()
    let slots: ptr<BrowserJsChild> = __volt_js_workers()
    let i: i64 = 0
    while i < BROWSER_JS_WORKERS:
        let child: ptr<BrowserJsChild> = &slots[i]
        if __volt_js_transition(&child.state, JS_SLOT_FREE, JS_SLOT_LIVE):
            child.signalled = false
            return child
        i += 1
    return 0 as ptr<BrowserJsChild>

unsafe fn browser_js_text_free(text: ptr<CssTextOverrides>):
    if text != (0 as ptr<CssTextOverrides>): munmap(text as ptr<char>, sizeof(CssTextOverrides))

unsafe fn browser_js_temp_record(js: ptr<BrowserJs>, id: i64, node: i64) -> i64:
    if id <= 0 or node <= 0: return -22
    if browser_js_temp_node(js, id) > 0: return 0
    if js.dom_count >= BROWSER_JS_DOM_NODES: return -7
    js.dom_ids[js.dom_count] = id
    js.dom_nodes[js.dom_count] = node
    js.dom_count += 1
    return 0

unsafe fn browser_js_temp_node(js: ptr<BrowserJs>, id: i64) -> i64:
    if id <= 0: return 0
    let i: i64 = 0
    while i < js.dom_count:
        if js.dom_ids[i] == id: return js.dom_nodes[i]
        i += 1
    return 0

unsafe fn browser_js_temp_for_node(js: ptr<BrowserJs>, node: i64) -> i64:
    if node <= 0: return 0
    let i: i64 = 0
    while i < js.dom_count:
        if js.dom_nodes[i] == node: return js.dom_ids[i]
        i += 1
    return 0

unsafe fn browser_js_stop(js: ptr<BrowserJs>):
    browser_js_fetch_abandon(js.fetch_job)
    js.fetch_job = 0 as ptr<BrowserJsFetchJob>
    let worker: BrowserWorker = BrowserWorker(js.pid, js.child, js.fd)
    browser_worker_stop(&worker)
    js.pid = worker.pid
    js.child = worker.child

unsafe fn browser_worker_stop(worker: ptr<BrowserWorker>):
    if worker.pid <= 0: return
    close(worker.fd)
    __volt_js_transition(&worker.child.state, JS_SLOT_LIVE, JS_SLOT_RETIRED)
    worker.pid = 0
    worker.child = 0 as ptr<BrowserJsChild>
    browser_js_reap()

unsafe fn browser_js_close(js: ptr<BrowserJs>):
    browser_js_stop(js)
    browser_js_text_free(js.text)
    js.text = 0 as ptr<CssTextOverrides>
    js.notice = 0
    js.origin[0] = 0 as char
    js.dom_count = 0

unsafe fn browser_js_trusted(fd: i64, kind: i64) -> bool:
    let metadata: [32]u64
    if __volt_fs_statx(fd, "" as ptr<char>, 0x1000, 11, &metadata[0]) < 0 or (metadata[0] & 11) != 11: return false
    let owner: i64 = (metadata[2] >> 32) as i64
    let mode: i64 = (metadata[3] >> 32 & 0xffff) as i64
    return (owner == 0 or owner == __volt_js_euid()) and (mode & 0xf000) == kind and (mode & 0x12) == 0

unsafe fn browser_worker_helper(name: string) -> i64:
    let path: [4096]char
    let size: i64 = __volt_js_readlink("/proc/self/exe" as ptr<char>, &path[0], 4096)
    if size < 1 or size == 4096: return -2
    let at: i64 = size
    while at > 0 and path[at - 1] != '/': at -= 1
    if at < 1: return -2
    path[at] = '\0'
    let dir: i64 = __volt_js_open_path(AT_FDCWD, &path[0], 0x290000)  # O_PATH | O_DIRECTORY | O_CLOEXEC
    if dir < 0: return dir
    defer close(dir)
    if not browser_js_trusted(dir, 0x4000): return -13
    let file: i64 = __volt_js_open_path(dir, name as ptr<char>, 0x2a0000)  # O_PATH | O_NOFOLLOW | O_CLOEXEC
    if file < 0: return file
    defer close(file)
    if not browser_js_trusted(file, 0x8000): return -13
    return __volt_js_dup(file)

unsafe fn browser_js_spawn(js: ptr<BrowserJs>) -> i64:
    let worker: BrowserWorker
    let status: i64 = browser_worker_spawn("volt-js-modern", -1, "", &worker)
    if status == -2: status = browser_worker_spawn("volt-js", -1, "", &worker)
    if status < 0: return status
    js.pid = worker.pid
    js.child = worker.child
    js.fd = worker.fd
    return 0

unsafe fn browser_worker_spawn(name: string, input: i64, mode: string, worker: ptr<BrowserWorker>) -> i64:
    let helper: i64 = browser_worker_helper(name)
    if helper < 0: return helper
    defer close(helper)
    let media: i64 = -1
    if input >= 0:
        media = __volt_js_dup(input)
        if media < 0: return media
    defer browser_worker_close_input(media)
    let args: [3]ptr<char>
    args[0] = name as ptr<char>
    if mode != "": args[1] = mode as ptr<char>
    let env: [1]ptr<char>
    let pair: [2]i32
    let status: i64 = __volt_js_socketpair(&pair[0])
    if status < 0: return status
    status = __volt_js_nonblock(pair[0] as i64)
    if status < 0:
        close(pair[0] as i64)
        close(pair[1] as i64)
        return status
    let child: ptr<BrowserJsChild> = browser_js_claim()
    if child == (0 as ptr<BrowserJsChild>):
        close(pair[0] as i64)
        close(pair[1] as i64)
        return -16
    let pid: i64 = __volt_js_fork(&child.pidfd)
    if pid == 0:
        if __volt_js_child_stdio(pair[1] as i64, helper, media) == 0: __volt_js_exec(helper, "" as ptr<char>, &args[0], &env[0])
        __volt_process_exit(127)
    close(pair[1] as i64)
    if pid < 0:
        close(pair[0] as i64)
        __volt_js_transition(&child.state, JS_SLOT_LIVE, JS_SLOT_FREE)
        return pid
    child.pid = pid
    worker.pid = pid
    worker.child = child
    worker.fd = pair[0] as i64
    return 0

unsafe fn browser_worker_close_input(fd: i64):
    if fd >= 0: close(fd)

unsafe fn browser_js_send(js: ptr<BrowserJs>, bytes: ptr<char>, length: i64, time: ptr<HttpTransfer>) -> bool:
    return http_write_all(js.fd, bytes as ptr<u8>, length, time) == length

unsafe fn browser_js_read(js: ptr<BrowserJs>, bytes: ptr<char>, length: i64, time: ptr<HttpTransfer>) -> bool:
    let done: i64 = 0
    while done < length:
        if http_transfer_remaining(time) < 0: return false
        let n: i64 = read(js.fd, bytes + done, length - done)
        if n == -4: continue
        if n == HTTP_EAGAIN:
            if http_wait(js.fd, HTTP_POLLIN as i16, time) < 0: return false
        elif n <= 0: return false
        else: done += n
    return true

unsafe fn browser_js_read_reply(js: ptr<BrowserJs>, time: ptr<HttpTransfer>, reply: ptr<BrowserJsReply>) -> i64:
    while true:
        let length: i64 = 0
        if not browser_js_read(js, (&length) as ptr<char>, 8, time): return -5
        if length < 8 or length > BROWSER_JS_FRAME_LIMIT: return -22
        let frame: ByteBuffer
        bytes_init(&frame)
        if bytes_reserve(&frame, length) < 0:
            bytes_free(&frame)
            return -12
        if not browser_js_read(js, frame.data as ptr<char>, length, time):
            bytes_free(&frame)
            return -5
        let kind: ptr<i64> = frame.data as ptr<i64>
        if kind[0] == BROWSER_JS_MSG_FETCH:
            let handled: i64 = browser_js_reply_fetch(js, frame.data as ptr<char>, length, time)
            bytes_free(&frame)
            if handled < 0: return handled
            continue
        if kind[0] != BROWSER_JS_MSG_REPLY:
            bytes_free(&frame)
            return -22
        let status: i64 = browser_js_parse_reply(js, frame.data as ptr<char>, length, reply)
        bytes_free(&frame)
        return status
    return -5

# Perform one same-origin fetch requested by the worker and send the reply.
unsafe fn browser_js_fetch_free(job: ptr<BrowserJsFetchJob>):
    if job == (0 as ptr<BrowserJsFetchJob>): return
    bytes_free(&job.out)
    munmap(job as ptr<char>, sizeof(BrowserJsFetchJob))

unsafe fn browser_js_fetch_abandon(job: ptr<BrowserJsFetchJob>):
    if job == (0 as ptr<BrowserJsFetchJob>): return
    if SDL_AtomicSet(&job.state, JS_FETCH_ABANDONED) == JS_FETCH_READY: browser_js_fetch_free(job)

unsafe fn browser_js_fetch_run(data: ptr<char>) -> i32:
    let job: ptr<BrowserJsFetchJob> = data as ptr<BrowserJsFetchJob>
    let verb: string = "GET"
    if job.method == 1: verb = "POST"
    # The job state doubles as the transport cancellation flag: 0 runs, 2 aborts.
    let transfer: HttpTransfer = HttpTransfer(job.deadline, &job.state, 1, 0, false, false)
    job.status = browser_fetch_perform((&job.origin[0]) as string, verb, (&job.url[0]) as string, &job.body[0], job.body_len, (&job.request_type[0]) as string, &job.out, &job.content_type[0], &job.final_url[0], &transfer)
    if SDL_AtomicSet(&job.state, JS_FETCH_READY) == JS_FETCH_ABANDONED: browser_js_fetch_free(job)
    return 0

unsafe fn browser_js_fetch_start(js: ptr<BrowserJs>, data: ptr<char>, length: i64, deadline: i64) -> i64:
    if js.fetch_job != (0 as ptr<BrowserJsFetchJob>): return -16
    if length < 40: return -22
    let header: ptr<i64> = data as ptr<i64>
    if header[0] != BROWSER_JS_MSG_FETCH: return -22
    let method: i64 = header[1]
    let url_len: i64 = header[2]
    let type_len: i64 = header[3]
    let body_len: i64 = header[4]
    if method < 0 or method > 1: return -22
    if url_len < 1 or url_len > 8192: return -22
    if type_len < 0 or type_len > 128: return -22
    if body_len < 0 or body_len > BROWSER_JS_FETCH_BYTES: return -22
    if length != 40 + url_len + type_len + body_len: return -22
    let job: ptr<BrowserJsFetchJob> = mmap(sizeof(BrowserJsFetchJob)) as ptr<BrowserJsFetchJob>
    if (job as i64) <= 0: return -12
    job.state = JS_FETCH_RUNNING
    job.deadline = deadline
    job.method = method
    job.body_len = body_len
    job.status = 0
    bytes_init(&job.out)
    job.content_type[0] = 0 as char
    job.final_url[0] = 0 as char
    let i: i64 = 0
    while i <= 8192:
        job.origin[i] = js.origin[i]
        i += 1
    i = 0
    while i < url_len:
        job.url[i] = data[40 + i]
        i += 1
    job.url[url_len] = 0 as char
    i = 0
    while i < type_len:
        job.request_type[i] = data[40 + url_len + i]
        i += 1
    job.request_type[type_len] = 0 as char
    let body: ptr<u8> = (data + 40 + url_len + type_len) as ptr<u8>
    i = 0
    while i < body_len:
        job.body[i] = body[i]
        i += 1
    let thread: ptr<char> = SDL_CreateThread(callback(browser_js_fetch_run), "volt-js-fetch" as ptr<char>, job as ptr<char>)
    if thread == (0 as ptr<char>):
        browser_js_fetch_free(job)
        return -12
    SDL_DetachThread(thread)
    js.fetch_job = job
    return 0

unsafe fn browser_js_fetch_send(js: ptr<BrowserJs>, job: ptr<BrowserJsFetchJob>, time: ptr<HttpTransfer>) -> i64:
    let code: i64 = 0
    if job.status > 0: code = job.status
    let ct_len: i64 = __volt_strlen((&job.content_type[0]) as string)
    let body_out: i64 = job.out.len
    let url_out: i64 = __volt_strlen((&job.final_url[0]) as string)
    let payload: i64 = 40 + ct_len + body_out + url_out
    let frame_length: [1]i64 = [payload]
    let head: [5]i64 = [BROWSER_JS_MSG_FETCH, code, ct_len, body_out, url_out]
    let ok: bool = browser_js_send(js, (&frame_length[0]) as ptr<char>, 8, time)
    if ok: ok = browser_js_send(js, (&head[0]) as ptr<char>, 40, time)
    if ok and ct_len > 0: ok = browser_js_send(js, &job.content_type[0], ct_len, time)
    if ok and body_out > 0: ok = browser_js_send(js, job.out.data as ptr<char>, body_out, time)
    if ok and url_out > 0: ok = browser_js_send(js, &job.final_url[0], url_out, time)
    js.fetch_job = 0 as ptr<BrowserJsFetchJob>
    browser_js_fetch_free(job)
    if not ok: return -5
    return 0

# The initial script phase runs inside the background load job, so waiting here
# does not block the window. Click-time fetches use the same job asynchronously.
unsafe fn browser_js_reply_fetch(js: ptr<BrowserJs>, data: ptr<char>, length: i64, time: ptr<HttpTransfer>) -> i64:
    let started: i64 = browser_js_fetch_start(js, data, length, time.deadline)
    if started < 0: return started
    let job: ptr<BrowserJsFetchJob> = js.fetch_job
    while SDL_AtomicGet(&job.state) == JS_FETCH_RUNNING:
        if http_transfer_remaining(time) < 0:
            browser_js_fetch_abandon(job)
            js.fetch_job = 0 as ptr<BrowserJsFetchJob>
            return HTTP_TIMEOUT
        sdl_delay(1)
    if SDL_AtomicGet(&job.state) != JS_FETCH_READY:
        js.fetch_job = 0 as ptr<BrowserJsFetchJob>
        return -5
    return browser_js_fetch_send(js, job, time)

unsafe fn browser_js_parse_reply(js: ptr<BrowserJs>, data: ptr<char>, length: i64, reply: ptr<BrowserJsReply>) -> i64:
    if length < 40 or length > BROWSER_JS_REPLY_LIMIT: return -22
    let header: ptr<i64> = data as ptr<i64>
    if header[0] != BROWSER_JS_MSG_REPLY or header[1] < 0 or header[1] > 1 or header[2] < 0 or header[2] > 1: return -22
    let text_count: i64 = header[3]
    let dom_len: i64 = header[4]
    if text_count < 0 or text_count > CSS_TEXT_OVERRIDE_LIMIT: return -22
    if dom_len < 0 or dom_len > BROWSER_JS_DOM_BYTES: return -22
    let dom_start: i64 = length - dom_len
    if dom_start < 40: return -22
    reply.script_error = header[1] == 1
    reply.prevent_default = header[2] == 1
    reply.text = 0 as ptr<CssTextOverrides>
    bytes_init(&reply.dom)
    if text_count > 0:
        let text: ptr<CssTextOverrides> = mmap(sizeof(CssTextOverrides)) as ptr<CssTextOverrides>
        if (text as i64) <= 0: return -12
        let status: i64 = browser_js_decode_edits(js, text, data, dom_start, text_count)
        if status < 0:
            browser_js_text_free(text)
            return status
        reply.text = text
    else:
        if dom_start != 40: return -22
    if dom_len > 0:
        if bytes_reserve(&reply.dom, dom_len) < 0:
            browser_js_text_free(reply.text)
            reply.text = 0 as ptr<CssTextOverrides>
            return -12
        let i: i64 = 0
        while i < dom_len:
            reply.dom.data[i] = data[dom_start + i] as u8
            i += 1
        reply.dom.len = dom_len
    return 0

unsafe fn browser_js_reply_free(reply: ptr<BrowserJsReply>):
    browser_js_text_free(reply.text)
    reply.text = 0 as ptr<CssTextOverrides>
    bytes_free(&reply.dom)

unsafe fn browser_js_valid_text(data: ptr<char>, size: i64) -> bool:
    let i: i64 = 0
    while i < size:
        let prior: i64 = i
        let ch: i64 = utf8_next(data, &i, size)
        if ch == 0 or (ch == 0xfffd and i - prior == 1): return false
    return true

unsafe fn browser_js_decode_edits(js: ptr<BrowserJs>, text: ptr<CssTextOverrides>, data: ptr<char>, length: i64, count: i64) -> i64:
    let pos: i64 = 40
    let slot: i64 = 0
    let record: i64 = 0
    while record < count:
        if length - pos < 16 or text.count >= CSS_TEXT_OVERRIDE_LIMIT: return -22
        let pair: ptr<i64> = (data + pos) as ptr<i64>
        let node: i64 = pair[0]
        let size: i64 = pair[1]
        pos += 16
        if size < 0 or size > CSS_OVERRIDE_BYTES or size > length - pos: return -22
        while slot < js.target_count and js.targets[slot] < node: slot += 1
        if slot == js.target_count or js.targets[slot] != node: return -22
        slot += 1
        let entry: ptr<CssTextOverride> = &text.entries[text.count]
        if not browser_js_valid_text(data + pos, size): return -22
        let i: i64 = 0
        while i < size:
            entry.text[i] = data[pos + i]
            i += 1
        entry.node = node
        entry.length = size
        text.count += 1
        text.total += size
        pos += size
        record += 1
    if pos != length: return -22
    return 0

unsafe fn browser_js_inert(doc: ptr<BrowserJsDocument>, node: i64) -> bool:
    let parent: i64 = doc.nodes[node].parent
    while parent > 0:
        let tag: ptr<HtmlNode> = &doc.nodes[parent]
        if tag.name_start >= 0 and html_name_in(doc.source, tag.name_start, tag.name_length, "template noscript svg math textarea title xmp iframe noembed noframes plaintext"): return true
        parent = doc.nodes[parent].parent
    return false

unsafe fn browser_js_classic(doc: ptr<BrowserJsDocument>, node: ptr<HtmlNode>, source_length: i64) -> bool:
    if not html_name_equal(doc.source, node, "script"): return false
    let index: i64 = css_find_html_attribute(doc.source, node, doc.attributes, "type")
    if index < 0 or not doc.attributes[index].has_value: return true
    let type: [65]char
    let attr: ptr<HtmlAttribute> = &doc.attributes[index]
    let length: i64 = html_decode_range(doc.source as ptr<char>, source_length, attr.value_start, attr.value_length, &type[0], 65)
    if length < 0: return false
    let left: i64 = css_trim_start(&type[0], 0, length)
    let right: i64 = css_trim_end(&type[0], left, length)
    return left == right or http_frame_equal(&type[0], left, right, "text/javascript") or http_frame_equal(&type[0], left, right, "application/javascript")

unsafe fn browser_js_external_tag(doc: ptr<BrowserJsDocument>, node: ptr<HtmlNode>) -> bool:
    if node.name_start != node.raw_start + 1: return false
    # shortcut: don't ignore attributes that require different scheduling or verification.
    for i in node.attribute_start..node.attribute_start + node.attribute_count:
        let attr: ptr<HtmlAttribute> = &doc.attributes[i]
        if html_name_in(doc.source, attr.name_start, attr.name_length, "async defer nomodule integrity charset language event for"): return false
    return true

unsafe fn browser_js_external_allowed(doc: ptr<BrowserJsDocument>, source_length: i64, time: ptr<HttpTransfer>) -> bool:
    # shortcut: refuse external loads for bases and raw-text constructs our HTML parser cannot disambiguate.
    let source: ptr<char> = doc.source as ptr<char>
    for i in 0..source_length:
        if i % 4096 == 0 and http_transfer_remaining(time) < 0: return false
        if source[i] == 12 as char or (source[i] == '<' and html_match(source, i, source_length, "<![CDATA[")): return false
    for i in 1..doc.node_count:
        if i % 256 == 0 and http_transfer_remaining(time) < 0: return false
        let node: ptr<HtmlNode> = &doc.nodes[i]
        if node.kind != HTML_ELEMENT: continue
        if html_name_equal(doc.source, node, "base") and css_find_html_attribute(doc.source, node, doc.attributes, "href") >= 0: return false
        if node.first_child < 0 or not html_name_equal(doc.source, node, "script"): continue
        let child: ptr<HtmlNode> = &doc.nodes[node.first_child]
        let end: i64 = child.text_start + child.text_length
        for at in child.text_start..end:
            if at % 4096 == 0 and http_transfer_remaining(time) < 0: return false
            if source[at] == '<' and html_match(source, at, end, "<!--"): return false
    return true

unsafe fn browser_js_closed(doc: ptr<BrowserJsDocument>, node: ptr<HtmlNode>, source_length: i64) -> bool:
    let end: i64 = node.raw_start + node.raw_length
    if node.first_child >= 0:
        let child: ptr<HtmlNode> = &doc.nodes[node.first_child]
        if child.kind != HTML_TEXT_NODE or child.text_start != end: return false
        end += child.text_length
    let token: HtmlToken
    return html_next_range(doc.source as ptr<char>, source_length, &end, &token) == HTML_END_TAG and html_token_is(doc.source, &token, "script")

unsafe fn browser_js_targets(doc: ptr<BrowserJsDocument>, js: ptr<BrowserJs>, out: ptr<ByteBuffer>, time: ptr<HttpTransfer>) -> i64:
    let i: i64 = 1
    let source_length: i64 = __volt_strlen(doc.source)
    while i < doc.node_count and js.target_count < CSS_TEXT_OVERRIDE_LIMIT:
        if i % 256 == 0 and http_transfer_remaining(time) < 0: return HTTP_CANCELLED
        let node: ptr<HtmlNode> = &doc.nodes[i]
        if node.kind == HTML_ELEMENT and node.attribute_count > 0 and html_name_in(doc.source, node.name_start, node.name_length, "a article b blockquote button code div em footer h1 h2 h3 h4 h5 h6 header i label li main p pre section small span strong") and not browser_js_inert(doc, i):
            let attr: i64 = css_find_html_attribute(doc.source, node, doc.attributes, "id")
            if attr >= 0 and doc.attributes[attr].has_value:
                let id: [257]char
                let id_length: i64 = html_decode_range(doc.source as ptr<char>, source_length, doc.attributes[attr].value_start, doc.attributes[attr].value_length, &id[0], 257)
                if id_length > 0 and browser_js_valid_text(&id[0], id_length):
                    let text: [4097]char
                    let length: i64 = browser_js_initial_text(doc, i, &text[0], source_length)
                    if length >= 0:
                        let header: [3]i64 = [i, id_length, length]
                        if browser_js_append(out, (&header[0]) as ptr<char>, 24) < 0 or browser_js_append(out, &id[0], id_length) < 0 or browser_js_append(out, &text[0], length) < 0: return -12
                        js.targets[js.target_count] = i
                        js.target_count += 1
        i += 1
    return 0

unsafe fn browser_js_initial_text(doc: ptr<BrowserJsDocument>, node: i64, text: ptr<char>, source_length: i64) -> i64:
    # shortcut: only text-only elements until the bridge supports structural DOM edits.
    let used: i64 = 0
    let i: i64 = doc.nodes[node].first_child
    while i >= 0:
        let child: ptr<HtmlNode> = &doc.nodes[i]
        if child.kind != HTML_TEXT_NODE: return -22
        let added: i64 = html_decode_range(doc.source as ptr<char>, source_length, child.text_start, child.text_length, text + used, CSS_OVERRIDE_BYTES + 1 - used)
        if added < 0: return added
        used += added
        i = child.next_sibling
    return used

unsafe fn browser_js_append(buffer: ptr<ByteBuffer>, data: ptr<char>, length: i64) -> i64:
    let status: i64 = bytes_reserve(buffer, buffer.len + length)
    if status < 0: return status
    let i: i64 = 0
    while i < length:
        buffer.data[buffer.len + i] = data[i] as u8
        i += 1
    buffer.len += length
    return 0

unsafe fn browser_js_add_script(scripts: ptr<BrowserJsScripts>, data: ptr<char>, length: i64) -> i64:
    if length == 0: return 0
    if scripts.count == BROWSER_JS_SCRIPT_LIMIT or length > BROWSER_JS_CODE_BYTES - scripts.source_bytes: return -7
    if browser_js_append(&scripts.frames, (&length) as ptr<char>, 8) < 0 or browser_js_append(&scripts.frames, data, length) < 0: return -12
    scripts.count += 1
    scripts.source_bytes += length
    return 0

# Returns 0 on success or no script, 1 on JS exception, 2 if the sandbox/limits fail.
unsafe fn browser_js_begin(js: ptr<BrowserJs>, doc: ptr<BrowserJsDocument>, url: string, time: ptr<HttpTransfer>, scripts: ptr<BrowserJsScripts>, dom: ptr<ByteBuffer>) -> i64:
    if scripts.count == 0: return 0
    let snapshot: ByteBuffer
    defer bytes_free(&snapshot)
    js.target_count = 0
    let origin_length: i64 = __volt_strlen(url)
    if origin_length < 1 or origin_length > 8192: return 2
    let origin: ptr<char> = url as ptr<char>
    let oi: i64 = 0
    while oi < origin_length:
        js.origin[oi] = origin[oi]
        oi += 1
    js.origin[origin_length] = 0 as char
    if browser_js_targets(doc, js, &snapshot, time) < 0 or http_transfer_remaining(time) < 0: return 2
    if browser_js_spawn(js) < 0: return 2
    let header: [3]i64 = [1, js.target_count, scripts.count]
    if not browser_js_send(js, (&header[0]) as ptr<char>, 24, time) or not browser_js_send(js, snapshot.data as ptr<char>, snapshot.len, time) or not browser_js_send(js, scripts.frames.data as ptr<char>, scripts.frames.len, time):
        browser_js_close(js)
        return 2
    let reply: BrowserJsReply
    if browser_js_read_reply(js, time, &reply) < 0 or http_transfer_remaining(time) < 0:
        browser_js_reply_free(&reply)
        browser_js_close(js)
        return 2
    js.text = reply.text
    if reply.dom.len > 0 and dom != (0 as ptr<ByteBuffer>):
        if bytes_reserve(dom, reply.dom.len) < 0:
            bytes_free(&reply.dom)
            browser_js_close(js)
            return 2
        let i: i64 = 0
        while i < reply.dom.len:
            dom.data[i] = reply.dom.data[i]
            i += 1
        dom.len = reply.dom.len
    bytes_free(&reply.dom)
    if reply.script_error: return 1
    return 0

# Nonblocking progress on the window thread, at most one outstanding click per page.
unsafe fn browser_js_poll_click(js: ptr<BrowserJs>, click: ptr<BrowserJsClick>, reply: ptr<BrowserJsReply>) -> i64:
    if js.fetch_job != (0 as ptr<BrowserJsFetchJob>):
        # A click-time fetch runs in its own thread; the window keeps polling.
        let job: ptr<BrowserJsFetchJob> = js.fetch_job
        let state: i32 = SDL_AtomicGet(&job.state)
        if state == JS_FETCH_READY:
            let transfer: HttpTransfer = HttpTransfer(click.deadline, 0 as ptr<i32>, 1, 0, false, false)
            let sent: i64 = browser_js_fetch_send(js, job, &transfer)
            click.received = 0
            click.length = 0
            click.frame.len = 0
            if sent < 0: return sent
            return 0
        if state == JS_FETCH_ABANDONED:
            js.fetch_job = 0 as ptr<BrowserJsFetchJob>
            return -5
        if http_remaining_ms(click.deadline) < 0:
            browser_js_fetch_abandon(job)
            js.fetch_job = 0 as ptr<BrowserJsFetchJob>
            return HTTP_TIMEOUT
        return 0
    let time: i64 = http_remaining_ms(click.deadline)
    if time < 0: return time
    if click.phase == 0:
        if click.frame.len == 0:
            let count: i64 = click.request[0]
            let words: i64 = count + 3
            if bytes_reserve(&click.frame, words * 8) < 0: return -12
            let out: ptr<i64> = click.frame.data as ptr<i64>
            out[0] = 8 * (count + 2)
            out[1] = 0
            out[2] = count
            let i: i64 = 0
            while i < count:
                out[3 + i] = click.request[1 + i]
                i += 1
            click.frame.len = words * 8
            click.sent = 0
        let size: i64 = click.frame.len
        let n: i64 = __volt_http_send(js.fd, click.frame.data + click.sent, size - click.sent)
        if n == -4 or n == HTTP_EAGAIN: return 0
        if n <= 0: return -5
        click.sent += n
        if click.sent < size: return 0
        click.phase = 1
        click.received = 0
        click.length = 0
        click.frame.len = 0
    if click.received < 8:
        let n: i64 = read(js.fd, ((&click.length) as ptr<char>) + click.received, 8 - click.received)
        if n == -4 or n == HTTP_EAGAIN: return 0
        if n <= 0: return -5
        click.received += n
        if click.received < 8: return 0
        if click.length < 8 or click.length > BROWSER_JS_FRAME_LIMIT: return -22
        if bytes_reserve(&click.frame, click.length) < 0: return -12
    let used: i64 = click.received - 8
    let n: i64 = read(js.fd, click.frame.data + used, click.length - used)
    if n == -4 or n == HTTP_EAGAIN: return 0
    if n <= 0: return -5
    click.received += n
    if click.received - 8 < click.length: return 0
    let kind: i64 = (click.frame.data as ptr<i64>)[0]
    if kind == BROWSER_JS_MSG_FETCH:
        # All fetches in one click share one absolute deadline, so a handler
        # cannot keep the worker alive indefinitely with back-to-back requests.
        if click.fetch_deadline <= 0: click.fetch_deadline = http_deadline_after(BROWSER_JS_FETCH_MS)
        let extended: i64 = click.fetch_deadline
        if extended < click.deadline: extended = click.deadline
        let started: i64 = browser_js_fetch_start(js, click.frame.data as ptr<char>, click.length, extended)
        click.received = 0
        click.length = 0
        click.frame.len = 0
        if started < 0: return started
        click.deadline = extended
        return 0
    if kind != BROWSER_JS_MSG_REPLY: return -22
    let status: i64 = browser_js_parse_reply(js, click.frame.data as ptr<char>, click.length, reply)
    if status < 0: return status
    click.phase = 0
    return 1
