use thread

const WORKERS: i64 = 4
const ROUNDS: i64 = 24
const INCREMENTS: i64 = 2000

struct Counter:
    lock: Mutex
    value: i64

struct ThreadJob:
    counter: ptr<Counter>
    tid: i64

unsafe native fn test_gettid() -> i64:
{
    mov eax, 186
    syscall
}

unsafe fn increment(data: ptr<char>) -> ptr<char>:
    let job: ptr<ThreadJob> = data as ptr<ThreadJob>
    let counter: ptr<Counter> = job.counter
    job.tid = test_gettid()
    for i in 0..INCREMENTS:
        if mutex_lock(&counter.lock) != 0: return 0 as ptr<char>
        counter.value += 1
        if mutex_unlock(&counter.lock) != 0: return 0 as ptr<char>
    return data

unsafe fn echo_thread_data(data: ptr<char>) -> ptr<char>:
    return data

unsafe fn try_busy_mutex(data: ptr<char>) -> ptr<char>:
    if mutex_try_lock(data as ptr<Mutex>) != THREAD_EBUSY: panic("try-lock missed contention")
    return data

unsafe fn expect_invalid_join(slot: ptr<Thread>):
    let result = thread_join(slot)
    match result:
        Ok(value): panic("join unexpectedly succeeded")
        Err(status):
            if status != THREAD_EINVAL: panic("expected EINVAL from join")

unsafe:
    let counter: Counter
    let jobs: [4]ThreadJob
    let slots: [4]Thread
    let empty: fnptr<(ptr<char>) -> ptr<char>>
    let main_tid: i64 = test_gettid()
    if sizeof(Thread) != 16 or alignof(Thread) != 8: panic("wrong Thread layout")
    if sizeof(Mutex) != 48 or alignof(Mutex) != 8: panic("wrong Mutex layout")
    expect_invalid_join(0 as ptr<Thread>)
    expect_invalid_join(&slots[0])
    if thread_spawn(&slots[0], empty, 0 as ptr<char>) != THREAD_EINVAL: panic("null callback")
    if thread_spawn(0 as ptr<Thread>, callback(echo_thread_data), 0 as ptr<char>) != THREAD_EINVAL: panic("null thread slot")

    if mutex_init(0 as ptr<Mutex>) != THREAD_EINVAL: panic("null mutex")
    if mutex_try_lock(0 as ptr<Mutex>) != THREAD_EINVAL: panic("null try-lock")
    if mutex_lock(&counter.lock) != THREAD_EINVAL: panic("uninitialized lock")
    if mutex_try_lock(&counter.lock) != THREAD_EINVAL: panic("uninitialized try-lock")
    if mutex_unlock(&counter.lock) != THREAD_EINVAL: panic("uninitialized unlock")
    if mutex_destroy(&counter.lock) != THREAD_EINVAL: panic("uninitialized destroy")

    if mutex_init(&counter.lock) != 0: panic("init try-lock fixture")
    # Copy before publication, so the test does not read concurrently used pthread storage.
    let mutex_copy: Mutex = counter.lock
    if mutex_init(&mutex_copy) != THREAD_EINVAL or mutex_destroy(&mutex_copy) != THREAD_EINVAL:
        panic("copied mutex lifecycle")
    if mutex_lock(&mutex_copy) != THREAD_EINVAL or mutex_try_lock(&mutex_copy) != THREAD_EINVAL or mutex_unlock(&mutex_copy) != THREAD_EINVAL:
        panic("copied mutex operation")
    if mutex_try_lock(&counter.lock) != 0: panic("uncontended try-lock")
    if thread_spawn(&slots[0], callback(try_busy_mutex), (&counter.lock) as ptr<char>) != 0:
        panic("spawn try-lock worker")
    # Hold the mutex until join: blocking in place of returning EBUSY hangs this test.
    match thread_join(&slots[0]):
        Ok(data):
            if data != ((&counter.lock) as ptr<char>): panic("try-lock worker result")
        Err(status): panic("join try-lock worker")
    if mutex_unlock(&counter.lock) != 0: panic("unlock after try-lock contention")
    if mutex_try_lock(&counter.lock) != 0: panic("try-lock after unlock")
    if mutex_unlock(&counter.lock) != 0 or mutex_destroy(&counter.lock) != 0: panic("cleanup try-lock fixture")
    if mutex_try_lock(&counter.lock) != THREAD_EINVAL: panic("try-lock after destroy")

    for round in 0..ROUNDS:
        if mutex_init(&counter.lock) != 0: panic("mutex_init")
        if mutex_init(&counter.lock) != THREAD_EINVAL: panic("double init")

        # No worker can finish while this lock is held; start all before joining.
        if mutex_lock(&counter.lock) != 0: panic("parent lock")
        for i in 0..WORKERS:
            jobs[i].counter = &counter
            if thread_spawn(&slots[i], callback(increment), (&jobs[i]) as ptr<char>) != 0:
                panic("thread_spawn")
        let copy: Thread = slots[0]
        expect_invalid_join(&copy)
        if thread_spawn(&copy, callback(echo_thread_data), 0 as ptr<char>) != THREAD_EINVAL:
            panic("spawn into a copied live slot")
        if thread_spawn(&slots[0], callback(echo_thread_data), 0 as ptr<char>) != THREAD_EINVAL:
            panic("spawn over an occupied slot")
        if mutex_unlock(&counter.lock) != 0: panic("parent unlock")

        for i in 0..WORKERS:
            let result = thread_join(&slots[i])
            match result:
                Ok(data):
                    if data != ((&jobs[i]) as ptr<char>): panic("wrong callback result")
                Err(status): panic("thread_join")
            expect_invalid_join(&slots[i])
            # Only read each worker's private result after its join.
            let tid: i64 = jobs[i].tid
            if tid <= 0 or tid == main_tid: panic("callback did not run on a worker")
            for previous in 0..i:
                if jobs[previous].tid == tid: panic("workers did not have distinct TIDs")
        if counter.value != (round + 1) * WORKERS * INCREMENTS: panic("lost increments")
        if mutex_destroy(&counter.lock) != 0: panic("mutex_destroy")
        if mutex_destroy(&counter.lock) != THREAD_EINVAL: panic("double destroy")
        if mutex_lock(&counter.lock) != THREAD_EINVAL: panic("lock after destroy")

    if thread_spawn(&slots[0], callback(echo_thread_data), 0 as ptr<char>) != 0: panic("null data")
    let null_result = thread_join(&slots[0])
    match null_result:
        Ok(data):
            if data != (0 as ptr<char>): panic("wrong null result")
        Err(status): panic("join for null data")
    print(WORKERS, ROUNDS, counter.value)
