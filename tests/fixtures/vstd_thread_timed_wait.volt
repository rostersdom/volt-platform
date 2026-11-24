use thread
use time

struct WaitState:
    mutex: Mutex
    condition: Condition
    ready: bool

fn test_now_ms() -> i64:
    match monotonic_ms():
        Ok(now): return now
        Err(status): panic("monotonic clock failed")
    return 0

unsafe fn notify(data: ptr<char>) -> ptr<char>:
    let state: ptr<WaitState> = data as ptr<WaitState>
    if mutex_lock(&state.mutex) != 0: panic("notifier lock")
    state.ready = true
    if condition_signal(&state.condition) != 0: panic("notifier signal")
    if mutex_unlock(&state.mutex) != 0: panic("notifier unlock")
    return data

unsafe fn expect_invalid_condition(condition: ptr<Condition>, held: ptr<Mutex>):
    if condition_wait(condition, held) != THREAD_EINVAL: panic("invalid condition wait")
    if condition_timed_wait(condition, held, 0) != THREAD_EINVAL: panic("invalid condition timed wait")
    if condition_signal(condition) != THREAD_EINVAL: panic("invalid condition signal")
    if condition_broadcast(condition) != THREAD_EINVAL: panic("invalid condition broadcast")
    if condition_destroy(condition) != THREAD_EINVAL: panic("invalid condition destroy")

unsafe fn expect_invalid_mutex(condition: ptr<Condition>, mutex: ptr<Mutex>):
    if condition_wait(condition, mutex) != THREAD_EINVAL: panic("condition wait with invalid mutex")
    if condition_timed_wait(condition, mutex, 0) != THREAD_EINVAL: panic("timed wait with invalid mutex")

unsafe fn expect_timeout(state: ptr<WaitState>, deadline: i64):
    let status: i32 = condition_timed_wait(&state.condition, &state.mutex, deadline)
    while status == 0:
        status = condition_timed_wait(&state.condition, &state.mutex, deadline)
    if status != THREAD_ETIMEDOUT or test_now_ms() < deadline: panic("wrong deadline or timeout status")
    # No other thread can hold this mutex here. EBUSY proves this caller still owns it.
    if mutex_try_lock(&state.mutex) != THREAD_EBUSY: panic("timeout did not reacquire the mutex")

unsafe:
    let state: WaitState
    let worker: Thread
    let blank_mutex: Mutex
    let blank_condition: Condition
    if sizeof(Condition) != 56 or alignof(Condition) != 8: panic("wrong Condition layout")
    if mutex_init(&state.mutex) != 0: panic("init wait mutex")

    # Copy idle live slots before sharing. Only the originals may reach glibc.
    if condition_init(&state.condition) != 0: panic("init condition")
    let mutex_copy: Mutex = state.mutex
    let condition_copy: Condition = state.condition
    if condition_init(0 as ptr<Condition>) != THREAD_EINVAL: panic("null condition init")
    if condition_init(&state.condition) != THREAD_EINVAL: panic("repeat condition init")
    if condition_init(&condition_copy) != THREAD_EINVAL: panic("copied condition init")
    expect_invalid_mutex(&state.condition, 0 as ptr<Mutex>)
    expect_invalid_mutex(&state.condition, &blank_mutex)
    expect_invalid_mutex(&state.condition, &mutex_copy)

    if mutex_lock(&state.mutex) != 0: panic("mutex before invalid waits")
    expect_invalid_condition(0 as ptr<Condition>, &state.mutex)
    expect_invalid_condition(&blank_condition, &state.mutex)
    expect_invalid_condition(&condition_copy, &state.mutex)
    if condition_timed_wait(&state.condition, &state.mutex, -1) != THREAD_EINVAL: panic("negative deadline")
    if mutex_try_lock(&state.mutex) != THREAD_EBUSY: panic("validation released the mutex")
    if mutex_unlock(&state.mutex) != 0: panic("unlock after invalid waits")

    # Signaling with nobody waiting is allowed; an unset predicate still times out.
    if condition_signal(&state.condition) != 0 or condition_broadcast(&state.condition) != 0:
        panic("notification without waiters")
    if mutex_lock(&state.mutex) != 0: panic("lock for timeouts")
    expect_timeout(&state, 0)
    expect_timeout(&state, test_now_ms() + 25)
    if mutex_unlock(&state.mutex) != 0: panic("unlock after timeouts")

    for round in 0..4:
        if condition_destroy(&state.condition) != 0: panic("destroy condition")
        if mutex_lock(&state.mutex) != 0: panic("lock for destroyed condition")
        expect_invalid_condition(&state.condition, &state.mutex)
        if condition_init(&state.condition) != 0: panic("reinit condition")
        state.ready = false
        if thread_spawn(&worker, callback(notify), (&state) as ptr<char>) != 0: panic("spawn notifier")
        # The notifier cannot set ready until timed wait releases this mutex.
        let deadline: i64 = test_now_ms() + 5000
        while not state.ready:
            let status: i32 = condition_timed_wait(&state.condition, &state.mutex, deadline)
            if status != 0: panic("timed wait did not wake on signal")
        # The notifier will not acquire the mutex again. Join first so EBUSY
        # below cannot mean the notifier still owns it.
        match thread_join(&worker):
            Ok(data):
                if data != ((&state) as ptr<char>): panic("notifier result")
            Err(status): panic("notifier join")
        if mutex_try_lock(&state.mutex) != THREAD_EBUSY: panic("signal did not reacquire mutex")
        if mutex_unlock(&state.mutex) != 0: panic("unlock after signal")
    if mutex_destroy(&state.mutex) != 0: panic("destroy mutex")
    expect_invalid_mutex(&state.condition, &state.mutex)
    if condition_destroy(&state.condition) != 0: panic("final condition destroy")
    print("condition timeout ok")
