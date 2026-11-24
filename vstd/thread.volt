# Opt-in Linux x86-64 LP64 / SysV ABI. Requires glibc >= 2.34 (pthread in libc).
# Uses the dynamic loader with VOLT's own _start, not the C runtime entry point.
# Programs without this import do not acquire a libc dependency from it.
link "-lc"

# glibc pthread_t is unsigned long (8 bytes); attr is always NULL.
unsafe extern fn pthread_create(out: ptr<u64>, attr: ptr<char>, entry: fnptr<(ptr<char>) -> ptr<char>>, data: ptr<char>) -> i32
unsafe extern fn pthread_join(id: u64, out: ptr<ptr<char>>) -> i32

const THREAD_EINVAL: i32 = 22

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
unsafe extern fn pthread_mutex_unlock(storage: ptr<u64>) -> i32
unsafe extern fn pthread_mutex_destroy(storage: ptr<u64>) -> i32

# Start with a zeroed Mutex. Init before sharing its address; never move it,
# copy it or mutate its fields while initialized. Nonrecursive, process-local;
# only the thread holding the lock may unlock. Destroy only when unlocked and
# no caller can be using or entering it. No automatic cleanup.
# Returns 0 or a pthread error number. Invalid slot state (including repeat
# init/destroy) returns EINVAL without calling pthread; misuse of a held lock
# is not diagnosed. Failed init/destroy does not change the address marker.
unsafe fn mutex_init(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != (0 as ptr<Mutex>): return THREAD_EINVAL
    let status: i32 = pthread_mutex_init(&mutex.storage[0], 0 as ptr<char>)
    if status == 0: mutex.address = mutex
    return status

unsafe fn mutex_lock(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_mutex_lock(&mutex.storage[0])

unsafe fn mutex_unlock(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    return pthread_mutex_unlock(&mutex.storage[0])

unsafe fn mutex_destroy(mutex: ptr<Mutex>) -> i32:
    if mutex == (0 as ptr<Mutex>) or mutex.address != mutex: return THREAD_EINVAL
    let status: i32 = pthread_mutex_destroy(&mutex.storage[0])
    if status == 0: mutex.address = 0 as ptr<Mutex>
    return status
