use thread

const QUEUE_WORKERS: i64 = 4
const QUEUE_ROUNDS: i64 = 24
const QUEUE_ITEMS: i64 = 2048
const QUEUE_CAPACITY: i64 = 8

struct WorkQueue:
    lock: Mutex
    readable: Condition
    changed: Condition
    items: [8]i64
    seen: [2048]bool
    head: i64
    used: i64
    waiting: i64
    wakeups: i64
    consumed: i64
    closed: bool

unsafe fn consume(data: ptr<char>) -> ptr<char>:
    let queue: ptr<WorkQueue> = data as ptr<WorkQueue>
    while true:
        if mutex_lock(&queue.lock) != 0: panic("consumer lock")
        if queue.used == 0 and not queue.closed:
            queue.waiting += 1
            if condition_signal(&queue.changed) != 0: panic("report waiting")
            while queue.used == 0 and not queue.closed:
                if condition_wait(&queue.readable, &queue.lock) != 0: panic("await item")
                queue.wakeups += 1
                if condition_signal(&queue.changed) != 0: panic("report wakeup")
            queue.waiting -= 1
        if queue.used == 0:
            if mutex_unlock(&queue.lock) != 0: panic("consumer final unlock")
            return data
        let item: i64 = queue.items[queue.head]
        queue.head = (queue.head + 1) % QUEUE_CAPACITY
        queue.used -= 1
        if item < 0 or item >= QUEUE_ITEMS or queue.seen[item]: panic("bad or duplicate item")
        queue.seen[item] = true
        queue.consumed += 1
        if condition_signal(&queue.changed) != 0: panic("report consumed")
        if mutex_unlock(&queue.lock) != 0: panic("consumer unlock")
    return 0 as ptr<char>

# Single producer; called with queue.lock held. The wait releases it when full.
unsafe fn put(queue: ptr<WorkQueue>, value: i64):
    while queue.used == QUEUE_CAPACITY:
        if condition_wait(&queue.changed, &queue.lock) != 0: panic("await queue space")
    queue.items[(queue.head + queue.used) % QUEUE_CAPACITY] = value
    queue.used += 1
    if condition_signal(&queue.readable) != 0: panic("notify consumer")

unsafe:
    let queue: WorkQueue
    let workers: [4]Thread
    let total: i64
    for round in 0..QUEUE_ROUNDS:
        queue.head = 0
        queue.used = 0
        queue.waiting = 0
        queue.wakeups = 0
        queue.consumed = 0
        queue.closed = false
        for item in 0..QUEUE_ITEMS: queue.seen[item] = false
        if mutex_init(&queue.lock) != 0: panic("init queue mutex")
        if condition_init(&queue.readable) != 0 or condition_init(&queue.changed) != 0:
            panic("init queue conditions")
        if mutex_lock(&queue.lock) != 0: panic("producer lock")
        for i in 0..QUEUE_WORKERS:
            if thread_spawn(&workers[i], callback(consume), (&queue) as ptr<char>) != 0:
                panic("spawn consumer")

        while queue.waiting != QUEUE_WORKERS:
            if condition_wait(&queue.changed, &queue.lock) != 0: panic("await all consumers")
        # Wake with no predicate change: a consumer must go back to waiting.
        let prior_wakeups: i64 = queue.wakeups
        if condition_signal(&queue.readable) != 0: panic("signal empty queue")
        while queue.wakeups == prior_wakeups:
            if condition_wait(&queue.changed, &queue.lock) != 0: panic("await empty wakeup")
        if queue.consumed != 0 or queue.waiting != QUEUE_WORKERS: panic("ignored predicate")

        put(&queue, 0)
        while queue.consumed == 0:
            if condition_wait(&queue.changed, &queue.lock) != 0: panic("await first item")
        for item in 1..QUEUE_ITEMS: put(&queue, item)
        while queue.waiting != QUEUE_WORKERS or queue.used != 0:
            if condition_wait(&queue.changed, &queue.lock) != 0: panic("await drained queue")
        queue.closed = true
        if condition_broadcast(&queue.readable) != 0: panic("close queue")
        if mutex_unlock(&queue.lock) != 0: panic("producer unlock")

        for i in 0..QUEUE_WORKERS:
            match thread_join(&workers[i]):
                Ok(data):
                    if data != ((&queue) as ptr<char>): panic("bad consumer result")
                Err(status): panic("join consumer")
        if queue.consumed != QUEUE_ITEMS or queue.waiting != 0: panic("lost items or waiters")
        total += queue.consumed
        if condition_destroy(&queue.changed) != 0 or condition_destroy(&queue.readable) != 0:
            panic("destroy queue conditions")
        if mutex_destroy(&queue.lock) != 0: panic("destroy queue mutex")
    print(QUEUE_WORKERS, QUEUE_ROUNDS, total)
