use arena

const MAX_SIZE: i64 = 9223372036854775807

struct ArenaHeader:
    kind: u8
    length: i64

struct ArenaPoint:
    x: i32
    y: i32

unsafe fn require_block(result: Result<ptr<u8>, i64>, label: string) -> ptr<u8>:
    match result:
        Ok(data): return data
        Err(status):
            panic(label)
            return 0 as ptr<u8>

unsafe fn expect_error(result: Result<ptr<u8>, i64>, expected: i64, label: string):
    match result:
        Ok(data): panic(label)
        Err(status):
            if status != expected: panic(label)

unsafe fn test_lifecycle():
    let slot: Arena
    let null_slot: ptr<Arena> = 0 as ptr<Arena>
    if arena_init(null_slot, 256) != -22 or arena_reset(null_slot) != -22 or arena_drop(null_slot) != -22:
        panic("null slot")
    expect_error(arena_alloc(null_slot, 1, 1), -22, "allocate through null slot")
    if arena_reset(&slot) != -22 or arena_drop(&slot) != -22: panic("empty slot")
    expect_error(arena_alloc(&slot, 1, 1), -22, "allocate before init")
    if arena_init(&slot, 0) != -22 or arena_init(&slot, -1) != -22: panic("nonpositive capacity")
    if arena_init(&slot, MAX_SIZE) != -12: panic("mmap should refuse an oversized mapping")
    if arena_init(&slot, 256) != 0: panic("init")

    let header = require_block(arena_alloc(&slot, sizeof(ArenaHeader), alignof(ArenaHeader)), "header") as ptr<ArenaHeader>
    header.kind = 7
    header.length = 9000000000

    let point = require_block(arena_alloc(&slot, sizeof(ArenaPoint), 32), "point") as ptr<ArenaPoint>
    point.x = -103
    point.y = 530

    let base: i64 = header as i64
    if base % alignof(ArenaHeader) != 0 or (point as i64) % 32 != 0: panic("alignment")
    if (point as i64) < base + sizeof(ArenaHeader): panic("allocations overlap")

    if arena_init(&slot, 128) != -22: panic("double init")
    let copy: Arena = slot
    if arena_init(&copy, 128) != -22 or arena_reset(&copy) != -22 or arena_drop(&copy) != -22:
        panic("copied live slot")
    expect_error(arena_alloc(&copy, 1, 1), -22, "allocate through copied live slot")

    expect_error(arena_alloc(&slot, 0, 1), -22, "zero size")
    expect_error(arena_alloc(&slot, -1, 1), -22, "negative size")
    expect_error(arena_alloc(&slot, 1, 0), -22, "zero alignment")
    expect_error(arena_alloc(&slot, 1, -8), -22, "negative alignment")
    expect_error(arena_alloc(&slot, 1, 24), -22, "not a power of two")
    expect_error(arena_alloc(&slot, MAX_SIZE, 32), -28, "oversized allocation must not overflow")
    expect_error(arena_alloc(&slot, 129, 128), -28, "size fits but padding does not")

    # The header uses 16 bytes and the point occupies offsets 32 through 39.
    let tail = require_block(arena_alloc(&slot, 216, 1), "exact remaining capacity")
    if (tail as i64) != (point as i64) + sizeof(ArenaPoint): panic("failed allocation changed cursor")
    tail[0] = 15
    tail[215] = 62
    expect_error(arena_alloc(&slot, 1, 1), -28, "full arena")
    if header.kind != 7 or header.length != 9000000000: panic("header contents")
    if point.x != -103 or point.y != 530: panic("point contents")
    if tail[0] != 15 or tail[215] != 62: panic("tail contents")

    if arena_reset(&slot) != 0: panic("reset")
    let reused = require_block(arena_alloc(&slot, 256, 1), "reuse whole arena")
    if (reused as i64) != base: panic("reset moved mapping")
    reused[255] = 48
    if reused[255] != 48: panic("reused storage")
    if arena_drop(&slot) != 0: panic("drop")
    expect_error(arena_alloc(&slot, 1, 1), -22, "allocate after drop")
    if arena_reset(&slot) != -22 or arena_drop(&slot) != -22: panic("dropped slot")
    if arena_init(&slot, 7) != 0: panic("reinit after drop")
    require_block(arena_alloc(&slot, 7, 1), "new capacity")
    expect_error(arena_alloc(&slot, 1, 1), -28, "old capacity survived reinit")
    if arena_drop(&slot) != 0: panic("drop after reinit")

# Observe whether a page is mapped without dereferencing an expired allocation.
unsafe native fn arena_test_mincore(page: ptr<u8>, length: i64, state: ptr<u8>) -> i64:
{
    mov eax, 27
    syscall
}

unsafe fn test_overalignment_and_unmap():
    let slot: Arena
    if arena_init(&slot, 16385) != 0: panic("multi-page init")
    # Offset zero is aligned, but the actual address cannot be aligned to 2^62.
    expect_error(arena_alloc(&slot, 1, 4611686018427387904), -28, "absolute alignment required")
    let first = require_block(arena_alloc(&slot, 1, 1), "first byte")
    let word = require_block(arena_alloc(&slot, 8, 8192), "overaligned word") as ptr<i64>
    let base: i64 = first as i64
    if (word as i64) <= base or (word as i64) % 8192 != 0: panic("overalignment")
    first[0] = 91
    *word = 9100000000
    if first[0] != 91 or *word != 9100000000: panic("overaligned contents")

    let last_page: i64 = base + 16384
    let state: u8
    if arena_test_mincore(last_page as ptr<u8>, 1, &state) != 0: panic("missing last page")
    if arena_drop(&slot) != 0: panic("multi-page drop")
    if arena_test_mincore(base as ptr<u8>, 1, &state) != -12 or arena_test_mincore(last_page as ptr<u8>, 1, &state) != -12:
        panic("drop left pages mapped")

unsafe:
    test_lifecycle()
    test_overalignment_and_unmap()
    print("arena lifecycle ok")
