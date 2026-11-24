# Opt-in Linux x86-64 LP64 / SysV ABI. Requires glibc >= 2.34 (pthread in libc).
# Uses the dynamic loader with VOLT's own _start, not the C runtime entry point.
# Programs without this import do not acquire a libc dependency from it.
link "-lc"

# glibc pthread_t is unsigned long (8 bytes); attr is always NULL.
unsafe extern fn pthread_create(out: ptr<u64>, attr: ptr<char>, entry: fnptr<(ptr<char>) -> ptr<char>>, data: ptr<char>) -> i32
unsafe extern fn pthread_join(id: u64, out: ptr<ptr<char>>) -> i32

const THREAD_EBUSY: i32 = 16
const THREAD_EINVAL: i32 = 22
const THREAD_ETIMEDOUT: i32 = 110

# Start with a zeroed Thread (`let task: Thread`). Each slot owns one joinable
# thread. Keep the slot at a stable address and use it only from the spawning
# thread; never share it with the worker or copy it while live. Do not touch its
# internal fields. The address check rejects a copied live slot and a second
# join after a successful one.
struct Thread:
    id: u64
    address: ptr<Thread>

# Pass callback(named_function): (ptr<char>) -> ptr<char>, C's void *(*)(void *).
# The worker may run before spawn returns. `data` (which may be NULL) is not
# copied or freed: its pointees must stay alive until a successful join and
# any concurrent accesses must be synchronized by the caller. The entry must
# return normally. Do not change glibc's default (joinable) thread attributes
# or use raw pthread join/detach/cancel on this thread. Use only operations
# that are safe to call concurrently; no Send/Sync/lifetime checks.
# Returns 0 on success, EINVAL for a null slot/entry or a nonempty slot, and
# otherwise the pthread error number (not errno). Failure leaves the slot empty
# if it was empty on entry.
unsafe fn thread_spawn(slot: ptr<Thread>, entry: fnptr<(ptr<char>) -> ptr<char>>, data: ptr<char>) -> i32:
    if slot == (0 as ptr<Thread>) or slot.address != (0 as ptr<Thread>) or not entry:
        return THREAD_EINVAL
    let id: u64
    let status: i32 = pthread_create(&id, 0 as ptr<char>, entry, data)
    if status == 0:
        slot.id = id
        slot.address = slot
    return status

# Join every successful spawn before exiting the process. On success the worker
# has terminated, its writes are visible, pthread reclaims its own resources,
# and the slot is reusable. Ok may contain NULL; never return a pointer into the
# worker's stack. The caller owns any result storage, and VOLT never frees it.
# Err(EINVAL) for a null/empty/copied slot; a pthread error leaves a live slot
# unchanged and is not permission to reclaim the worker's data.
unsafe fn thread_join(slot: ptr<Thread>) -> Result<ptr<char>, i32>:
    if slot == (0 as ptr<Thread>) or slot.address != slot:
        return Err(THREAD_EINVAL)
    let value: ptr<char>
    let status: i32 = pthread_join(slot.id, &value)
    if status != 0: return Err(status)
    slot.id = 0
    slot.address = 0 as ptr<Thread>
    return Ok(value)

# glibc x86-64 LP64 pthread_mutex_t: 40 bytes, 8-byte alignment. pthread only
# sees `storage`; the address marker is separate. No heap allocation or copying.
struct Mutex:
    storage: [5]u64
    address: ptr<Mutex>

unsafe extern fn pthread_mutex_init(storage: ptr<u64>, attr: ptr<char>) -> i32
unsafe extern fn pthread_mutex_lock(storage: ptr<u64>) -> i32
unsafe extern fn pthread_mutex_trylock(storage: ptr<u64>) -> i32
unsafe extern fn pthread_mutex_unlock(storage: ptr<u64>) -> i32
unsafe extern fn pthread_mutex_destroy(storage: ptr<u64>) -> i32

# Start with a zeroed Mutex. Init before sharing its address; never move it,
# copy it or mutate its fields while initialized. Nonrecursive, process-local;
# only the thread holding the lock may unlock. Destroy only when unlocked and
# no caller can be using or entering it, including through a condition wait.
# No automatic cleanup.
# Returns 0 or a pthread error number. Invalid slot state (including repeat
# init/destroy) returns EINVAL without calling pthread. Failed init leaves the
# slot uninitialized; failed destroy leaves it live. Do not rely on destroy
# checking for concurrent users.
unsafe fn mutex_init(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != (0 as ptr<Mutex>): return THREAD_EINVAL
    let status: i32 = pthread_mutex_init(&mutex.storage[0], 0 as ptr<char>)
    if status == 0: mutex.address = mutex
    return status

unsafe fn mutex_lock(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_mutex_lock(&mutex.storage[0])

# Returns 0 with the lock acquired, or EBUSY without acquiring it if held.
unsafe fn mutex_try_lock(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_mutex_trylock(&mutex.storage[0])

unsafe fn mutex_unlock(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_mutex_unlock(&mutex.storage[0])

unsafe fn mutex_destroy(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    let status: i32 = pthread_mutex_destroy(&mutex.storage[0])
    if status == 0: mutex.address = 0 as ptr<Mutex>
    return status

# glibc x86-64 LP64 pthread_cond_t: 48 bytes, 8-byte alignment. As with Mutex,
# zero the slot before first init, keep it at a stable address and don't copy
# it or touch the fields. Init/destroy must be exclusive; only on success do
# they change whether the caller-owned slot is live. Errors are pthread codes
# (not errno), or EINVAL for a null, copied or wrongly initialized slot.
struct Condition:
    storage: [6]u64
    address: ptr<Condition>

unsafe extern fn pthread_cond_init(storage: ptr<u64>, attr: ptr<char>) -> i32
unsafe extern fn pthread_cond_wait(storage: ptr<u64>, mutex: ptr<u64>) -> i32
unsafe extern fn pthread_cond_clockwait(storage: ptr<u64>, mutex: ptr<u64>, clock: i32, deadline: ptr<i64>) -> i32
unsafe extern fn pthread_cond_signal(storage: ptr<u64>) -> i32
unsafe extern fn pthread_cond_broadcast(storage: ptr<u64>) -> i32
unsafe extern fn pthread_cond_destroy(storage: ptr<u64>) -> i32

unsafe fn condition_init(condition: ptr<Condition>) -> i32:
    if condition == (0 as ptr<Condition>) or condition.address != (0 as ptr<Condition>): return THREAD_EINVAL
    let status: i32 = pthread_cond_init(&condition.storage[0], 0 as ptr<char>)
    if status == 0: condition.address = condition
    return status

# The caller must hold mutex; all concurrent waiters on this condition must
# use the same mutex. Wait atomically releases it and reacquires it before
# returning 0.
# Success may be a spurious wakeup: always recheck the predicate in a loop.
# Invalid slots are rejected without releasing the mutex.
unsafe fn condition_wait(condition: ptr<Condition>, mutex: ptr<Mutex>) -> i32:
    if condition == (0 as ptr<Condition>) or condition.address != condition: return THREAD_EINVAL
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_cond_wait(&condition.storage[0], &mutex.storage[0])

# Same preconditions as condition_wait. Pass an absolute CLOCK_MONOTONIC
# deadline in milliseconds (see monotonic_ms from `use time`). A negative
# deadline returns EINVAL without unlocking. On 0 or ETIMEDOUT the mutex is
# held again; reacquiring it may block past the deadline.
unsafe fn condition_timed_wait(condition: ptr<Condition>, mutex: ptr<Mutex>, deadline_ms: i64) -> i32:
    if deadline_ms < 0: return THREAD_EINVAL
    if condition == (0 as ptr<Condition>) or condition.address != condition: return THREAD_EINVAL
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    # glibc LP64 timespec is two signed 64-bit longs. Normalize without overflow.
    let deadline: [2]i64
    deadline[0] = deadline_ms / 1000
    deadline[1] = (deadline_ms % 1000) * 1000000
    return pthread_cond_clockwait(&condition.storage[0], &mutex.storage[0], 1 as i32, &deadline[0])  # CLOCK_MONOTONIC

# Change the predicate while holding the waiters' mutex. A notification with
# no waiters is not remembered. Neither function changes mutex ownership.
unsafe fn condition_signal(condition: ptr<Condition>) -> i32:
    if condition == (0 as ptr<Condition>) or condition.address != condition: return THREAD_EINVAL
    return pthread_cond_signal(&condition.storage[0])

unsafe fn condition_broadcast(condition: ptr<Condition>) -> i32:
    if condition == (0 as ptr<Condition>) or condition.address != condition: return THREAD_EINVAL
    return pthread_cond_broadcast(&condition.storage[0])

# Destroy only after all wait/signal/broadcast calls have returned and no new
# caller can enter. This is not a way to wake or diagnose active waiters.
unsafe fn condition_destroy(condition: ptr<Condition>) -> i32:
    if condition == (0 as ptr<Condition>) or condition.address != condition: return THREAD_EINVAL
    let status: i32 = pthread_cond_destroy(&condition.storage[0])
    if status == 0: condition.address = 0 as ptr<Condition>
    return status
