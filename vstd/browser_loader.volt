use browser_controller

const BROWSER_LOAD_RUNNING: i32 = 0
const BROWSER_LOAD_READY: i32 = 1
const BROWSER_LOAD_ABANDONED: i32 = 2
const BROWSER_LOAD_WORKER_LIMIT: i32 = 4
let browser_load_workers: i32 = 0

struct BrowserLoad:
    target: [8193]char
    resource_length: i64
    history_index: i64
    reload: bool
    youtube_lookup: bool

struct BrowserLoadJob:
    page: BrowserPage
    source: ByteBuffer
    address: [8193]char
    resource_length: i64
    viewport: BrowserViewport
    deadline: i64
    result: i64
    state: i32
    youtube_lookup: bool

unsafe fn browser_load_job_free(job: ptr<BrowserLoadJob>):
    browser_page_free(job.page.storage)
    bytes_free(&job.source)
    munmap(job as ptr<char>, sizeof(BrowserLoadJob))
    SDL_AtomicAdd(&browser_load_workers, -1)

unsafe fn browser_load_job_abandon(job: ptr<BrowserLoadJob>):
    if job == (0 as ptr<BrowserLoadJob>): return
    if SDL_AtomicSet(&job.state, BROWSER_LOAD_ABANDONED) == BROWSER_LOAD_READY:
        browser_load_job_free(job)

unsafe fn browser_load_job_run(data: ptr<char>) -> i32:
    let job: ptr<BrowserLoadJob> = data as ptr<BrowserLoadJob>
    if browser_page_allocate(&job.page) == (0 as ptr<BrowserPageStorage>):
        job.result = -12
    else:
        let transfer: HttpTransfer = HttpTransfer(job.deadline, &job.state, BROWSER_HTTP_RESPONSE_LIMIT, HTML_DOCUMENT_LIMIT, false, false)
        let address: string = (&job.address[0]) as string
        if job.youtube_lookup:
            job.result = browser_youtube_load(&job.page, &job.source, address, job.viewport, &transfer)
        else:
            job.result = browser_load_candidate(&job.page, &job.source, address, job.resource_length, job.viewport, &transfer)
    # Publishing the result transfers ownership to the window unless it already closed.
    if SDL_AtomicSet(&job.state, BROWSER_LOAD_READY) == BROWSER_LOAD_ABANDONED:
        browser_load_job_free(job)
    return 0

unsafe fn browser_load_job_start(load: ptr<BrowserLoad>, view: BrowserViewport, options: ptr<BrowserPage>, out: ptr<ptr<BrowserLoadJob>>) -> i64:
    let deadline: i64 = http_deadline_after(HTTP_DEFAULT_TIMEOUT_MS)
    if deadline < 0: return deadline
    # A cancelled blocking DNS lookup may still be running; bound detached jobs.
    if SDL_AtomicAdd(&browser_load_workers, 1) >= BROWSER_LOAD_WORKER_LIMIT:
        SDL_AtomicAdd(&browser_load_workers, -1)
        return -16
    let job: ptr<BrowserLoadJob> = mmap(sizeof(BrowserLoadJob)) as ptr<BrowserLoadJob>
    if (job as i64) <= 0:
        SDL_AtomicAdd(&browser_load_workers, -1)
        return -12
    job.state = BROWSER_LOAD_RUNNING
    job.resource_length = load.resource_length
    job.youtube_lookup = load.youtube_lookup
    job.viewport = view
    job.deadline = deadline
    job.page.scripts_enabled = options.scripts_enabled
    job.page.visual = options.visual
    if browser_copy_address(&job.address[0], (&load.target[0]) as string) < 0:
        browser_load_job_free(job)
        return -90
    let thread: ptr<char> = SDL_CreateThread(callback(browser_load_job_run), "volt-page-load" as ptr<char>, job as ptr<char>)
    if thread == (0 as ptr<char>):
        browser_load_job_free(job)
        return -12
    SDL_DetachThread(thread)
    out[0] = job
    return 0
