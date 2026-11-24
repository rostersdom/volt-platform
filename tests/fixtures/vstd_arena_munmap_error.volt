use arena

# Seal only this fixture's own mapping to make the kernel reject munmap.
unsafe native fn arena_test_mseal(data: ptr<u8>, size: i64, flags: i64) -> i64:
{
    mov eax, 462
    syscall
}

unsafe:
    let slot: Arena
    if arena_init(&slot, 4096) != 0: panic("init")
    let first: ptr<u8>
    let first_result = arena_alloc(&slot, 8, 1)
    match first_result:
        Ok(data): first = data
        Err(status): panic("initial allocation")
    first[0] = 56

    let sealed = arena_test_mseal(first, 4096, 0)
    # Older kernels and sandbox filters may not expose mseal (Linux >= 6.10).
    if sealed == -38 or sealed == -1 or sealed == -13: exit(77)
    if sealed != 0: panic("mseal")
    if arena_drop(&slot) != -1: panic("drop did not return EPERM")
    if first[0] != 56: panic("drop error did not preserve data")
    if arena_init(&slot, 4096) != -22: panic("drop error cleared the slot")

    let tail_result = arena_alloc(&slot, 4088, 1)
    match tail_result:
        Ok(data):
            if data != first + 8: panic("drop error changed the cursor")
            data[4087] = 97
            if data[4087] != 97 or first[0] != 56: panic("drop error damaged storage")
        Err(status): panic("allocate after drop error")

    # The seal cannot be removed; the process exits with the mapping still live.
    if arena_drop(&slot) != -1: panic("retry did not return EPERM")
    print("arena munmap error ok")
