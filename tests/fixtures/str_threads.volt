use thread

struct StringJob:
    gate: ptr<Mutex>
    prefix: string
    values: [4096]string

unsafe fn build_strings(data: ptr<char>) -> ptr<char>:
    let job: ptr<StringJob> = data as ptr<StringJob>
    if mutex_lock(job.gate) != 0 or mutex_unlock(job.gate) != 0: panic("start gate")
    for i in 0..4096:
        let suffix: string = ":even"
        if i % 2 != 0: suffix = ":odd!"
        job.values[i] = str_repeat(job.prefix, 12) + suffix
    return data

unsafe:
    let gate: Mutex
    let workers: [4]Thread
    let jobs: [4]StringJob
    let prefixes: [4]string = ["a", "b", "c", "d"]
    if mutex_init(&gate) != 0 or mutex_lock(&gate) != 0: panic("init gate")
    for i in 0..4:
        jobs[i].gate = &gate
        jobs[i].prefix = prefixes[i]
        if thread_spawn(&workers[i], callback(build_strings), (&jobs[i]) as ptr<char>) != 0: panic("spawn")
    if mutex_unlock(&gate) != 0: panic("release gate")
    for i in 0..4:
        let joined = thread_join(&workers[i])
        match joined:
            Ok(data):
                if data != (&jobs[i]) as ptr<char>: panic("worker result")
            Err(error): panic("join")
    if mutex_destroy(&gate) != 0: panic("destroy gate")
    for i in 0..4:
        let prefix: string = prefixes[i] * 12
        let even: string = prefix + ":even"
        let odd: string = prefix + ":odd!"
        for j in 0..4096:
            let expected: string = even
            if j % 2 != 0: expected = odd
            if jobs[i].values[j] != expected: panic("concurrent string changed")
    print("thread strings ok")
