use bytes

const __VOLT_BORROW_SCOPE_CHECK: __VoltBorrowScopeV2 = 0
const BORROW_BUFFER_SLOTS: i64 = 64
const BORROW_BUFFER_MAX_GENERATION: u64 = 288230376151711743

# Only this module can access the handle representation. Copies share a slot.
struct BorrowBuffer<T>:
    token: u64

struct BufferRead<T>:
    owner: BorrowBuffer<T>

struct BorrowBufferSlot:
    generation: u64
    live: bool
    readers: i64
    storage: ByteBuffer

# shortcut: a bounded process-wide registry until VOLT has noncopyable owners.
unsafe native fn borrow_buffer_slots() -> ptr<BorrowBufferSlot>:
{
    .lcomm VOLT_borrow_buffer_storage, 4096
    lea rax, [rip + VOLT_borrow_buffer_storage]
}

unsafe native fn borrow_buffer_lock():
{
    .lcomm VOLT_borrow_buffer_guard, 4
.Lborrow_buffer_lock:
    mov eax, 1
    xchg dword ptr [rip + VOLT_borrow_buffer_guard], eax
    test eax, eax
    jz .Lborrow_buffer_locked
    pause
    jmp .Lborrow_buffer_lock
.Lborrow_buffer_locked:
}

unsafe native fn borrow_buffer_unlock():
{
    mov dword ptr [rip + VOLT_borrow_buffer_guard], 0
}

# Callers hold the registry lock through validation and any use of the slot.
unsafe fn borrow_buffer_slot(token: u64) -> ptr<BorrowBufferSlot>:
    let generation: u64 = token / (BORROW_BUFFER_SLOTS as u64)
    if generation == 0: return 0 as ptr<BorrowBufferSlot>
    let index: i64 = (token % (BORROW_BUFFER_SLOTS as u64)) as i64
    let slot: ptr<BorrowBufferSlot> = borrow_buffer_slots() + index
    if not slot.live or slot.generation != generation: return 0 as ptr<BorrowBufferSlot>
    return slot

unsafe fn borrow_buffer_writable(slot: ptr<BorrowBufferSlot>) -> i64:
    if slot == (0 as ptr<BorrowBufferSlot>): return -9
    if slot.readers != 0: return -16
    return 0

fn borrow_buffer_new<T>(initial: []T) -> BorrowBuffer<T>:
    let width: i64 = sizeof(T)
    let count: i64 = len(initial)
    if width <= 0 or count > 9223372036854775807 / width: return BorrowBuffer(0)
    let size: i64 = count * width
    unsafe:
        if sizeof(BorrowBufferSlot) * BORROW_BUFFER_SLOTS > 4096: panic("BorrowBuffer registry size\n")
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slots: ptr<BorrowBufferSlot> = borrow_buffer_slots()
        for i in 0..BORROW_BUFFER_SLOTS:
            let slot: ptr<BorrowBufferSlot> = slots + i
            if not slot.live and slot.generation < BORROW_BUFFER_MAX_GENERATION:
                if bytes_reserve(&slot.storage, size) < 0: return BorrowBuffer(0)
                if count > 0:
                    let source: ptr<u8> = (&initial[0]) as ptr<u8>
                    for j in 0..size: slot.storage.data[j] = source[j]
                slot.storage.len = size
                slot.generation += 1
                slot.live = true
                return BorrowBuffer(slot.generation * (BORROW_BUFFER_SLOTS as u64) + (i as u64))
    return BorrowBuffer(0)

fn borrow_buffer_len<T>(buffer: BorrowBuffer<T>) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        if slot == (0 as ptr<BorrowBufferSlot>): return -9
        return slot.storage.len / sizeof(T)

fn borrow_buffer_reserve<T>(buffer: BorrowBuffer<T>, count: i64) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        let status: i64 = borrow_buffer_writable(slot)
        if status < 0: return status
        let width: i64 = sizeof(T)
        if count < 0: return -22
        if count > 9223372036854775807 / width: return -75
        return bytes_reserve(&slot.storage, count * width)

fn borrow_buffer_push<T>(buffer: BorrowBuffer<T>, value: T) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        let status: i64 = borrow_buffer_writable(slot)
        if status < 0: return status
        let width: i64 = sizeof(T)
        if slot.storage.len > 9223372036854775807 - width: return -75
        status = bytes_reserve(&slot.storage, slot.storage.len + width)
        if status < 0: return status
        let data: ptr<T> = slot.storage.data as ptr<T>
        data[slot.storage.len / width] = value
        slot.storage.len += width
        return 0

fn borrow_buffer_set<T>(buffer: BorrowBuffer<T>, index: i64, value: T) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        let status: i64 = borrow_buffer_writable(slot)
        if status < 0: return status
        if index < 0 or index >= slot.storage.len / sizeof(T): return -34
        let data: ptr<T> = slot.storage.data as ptr<T>
        data[index] = value
        return 0

fn borrow_buffer_drop<T>(buffer: BorrowBuffer<T>) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        let status: i64 = borrow_buffer_writable(slot)
        if status < 0: return status
        status = bytes_free(&slot.storage)
        if status == 0: slot.live = false
        return status

# The compiler permits acquisition only with a matching implicit block defer.
fn borrow_buffer_read<T>(buffer: BorrowBuffer<T>) -> BufferRead<T>:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(buffer.token)
        if slot == (0 as ptr<BorrowBufferSlot>): panic("invalid BorrowBuffer handle\n")
        if slot.readers == 9223372036854775807: panic("too many BorrowBuffer readers\n")
        slot.readers += 1
        return BufferRead(buffer)

unsafe fn borrow_buffer_read_slot(token: u64) -> ptr<BorrowBufferSlot>:
    let slot: ptr<BorrowBufferSlot> = borrow_buffer_slot(token)
    if slot == (0 as ptr<BorrowBufferSlot>) or slot.readers <= 0: panic("inactive BorrowBuffer reader\n")
    return slot

fn __volt_buffer_read_end<T>(view: BufferRead<T>):
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_read_slot(view.owner.token)
        slot.readers -= 1

fn buffer_read_len<T>(view: BufferRead<T>) -> i64:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_read_slot(view.owner.token)
        return slot.storage.len / sizeof(T)

fn buffer_read_get<T>(view: BufferRead<T>, index: i64) -> T:
    unsafe:
        borrow_buffer_lock()
        defer borrow_buffer_unlock()
        let slot: ptr<BorrowBufferSlot> = borrow_buffer_read_slot(view.owner.token)
        if index < 0 or index >= slot.storage.len / sizeof(T): panic("BorrowBuffer index out of bounds\n")
        let data: ptr<T> = slot.storage.data as ptr<T>
        return data[index]
