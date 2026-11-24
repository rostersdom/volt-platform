use bytes

const BYTE_VEC_SLOTS: i64 = 64
const BYTE_VEC_MAX_GENERATION: u64 = 288230376151711743

struct ByteVec:
    token: u64

struct ByteView:
    owner: ByteVec
    start: i64
    length: i64

struct ByteVecSlot:
    generation: u64
    live: bool
    buffer: ByteBuffer

# shortcut: a fixed process-wide registry until VOLT has noncopyable heap owners.
# Safe code sees handles only; a copied handle cannot keep a freed allocation alive.
unsafe native fn byte_vec_slots() -> ptr<ByteVecSlot>:
{
    .lcomm VOLT_byte_vec_storage, 4096
    lea rax, [rip + VOLT_byte_vec_storage]
}

unsafe native fn byte_vec_lock():
{
    .lcomm VOLT_byte_vec_guard, 4
.Lbyte_vec_lock:
    mov eax, 1
    xchg dword ptr [rip + VOLT_byte_vec_guard], eax
    test eax, eax
    jz .Lbyte_vec_locked
    pause
    jmp .Lbyte_vec_lock
.Lbyte_vec_locked:
}

unsafe native fn byte_vec_unlock():
{
    mov dword ptr [rip + VOLT_byte_vec_guard], 0
}

unsafe fn byte_vec_slot(bytes: ByteVec) -> ptr<ByteVecSlot>:
    let generation: u64 = bytes.token / (BYTE_VEC_SLOTS as u64)
    if generation == 0: return 0 as ptr<ByteVecSlot>
    let index: i64 = (bytes.token % (BYTE_VEC_SLOTS as u64)) as i64
    let slot: ptr<ByteVecSlot> = byte_vec_slots() + index
    if not slot.live or slot.generation != generation: return 0 as ptr<ByteVecSlot>
    return slot

fn byte_vec_new() -> ByteVec:
    unsafe:
        if sizeof(ByteVecSlot) * BYTE_VEC_SLOTS > 4096: panic("ByteVec registry size")
        byte_vec_lock()
        defer byte_vec_unlock()
        let slots: ptr<ByteVecSlot> = byte_vec_slots()
        let i: i64 = 0
        while i < BYTE_VEC_SLOTS:
            let slot: ptr<ByteVecSlot> = slots + i
            if not slot.live and slot.generation < BYTE_VEC_MAX_GENERATION:
                slot.generation += 1
                slot.live = true
                return ByteVec(slot.generation * (BYTE_VEC_SLOTS as u64) + (i as u64))
            i += 1
        return ByteVec(0)

fn byte_vec_drop(bytes: ByteVec) -> i64:
    unsafe:
        byte_vec_lock()
        defer byte_vec_unlock()
        let slot: ptr<ByteVecSlot> = byte_vec_slot(bytes)
        if slot == (0 as ptr<ByteVecSlot>): return -9
        let status: i64 = bytes_free(&slot.buffer)
        if status == 0: slot.live = false
        return status

fn byte_vec_len(bytes: ByteVec) -> i64:
    unsafe:
        byte_vec_lock()
        defer byte_vec_unlock()
        let slot: ptr<ByteVecSlot> = byte_vec_slot(bytes)
        if slot == (0 as ptr<ByteVecSlot>): return -9
        return slot.buffer.len

fn byte_vec_push(bytes: ByteVec, value: u8) -> i64:
    unsafe:
        byte_vec_lock()
        defer byte_vec_unlock()
        let slot: ptr<ByteVecSlot> = byte_vec_slot(bytes)
        if slot == (0 as ptr<ByteVecSlot>): return -9
        return bytes_push(&slot.buffer, value)

fn byte_vec_get(bytes: ByteVec, index: i64) -> Result<u8, i32>:
    unsafe:
        byte_vec_lock()
        defer byte_vec_unlock()
        let slot: ptr<ByteVecSlot> = byte_vec_slot(bytes)
        if slot == (0 as ptr<ByteVecSlot>): return Err(9 as i32)
        if index < 0 or index >= slot.buffer.len: return Err(34 as i32)
        return Ok(slot.buffer.data[index])

fn byte_vec_set(bytes: ByteVec, index: i64, value: u8) -> i64:
    unsafe:
        byte_vec_lock()
        defer byte_vec_unlock()
        let slot: ptr<ByteVecSlot> = byte_vec_slot(bytes)
        if slot == (0 as ptr<ByteVecSlot>): return -9
        if index < 0 or index >= slot.buffer.len: return -34
        slot.buffer.data[index] = value
        return 0

fn byte_vec_view(bytes: ByteVec, start: i64, end: i64) -> ByteView:
    let length: i64 = byte_vec_len(bytes)
    if start < 0 or end < start or end > length: return ByteView(bytes, 0, -1)
    return ByteView(bytes, start, end - start)

fn byte_view_len(view: ByteView) -> i64:
    let length: i64 = byte_vec_len(view.owner)
    if length < 0: return length
    if view.start < 0 or view.start > length or view.length < 0 or view.length > length - view.start: return -34
    return view.length

fn byte_view_get(view: ByteView, index: i64) -> Result<u8, i32>:
    let length: i64 = byte_view_len(view)
    if length < 0: return Err((-length) as i32)
    if index < 0 or index >= length: return Err(34 as i32)
    # A concurrent drop after the length check is caught by the generation check on get.
    return byte_vec_get(view.owner, view.start + index)
