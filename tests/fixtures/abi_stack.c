#include <stddef.h>
#include <stdint.h>

// a12 spills while a13 through a15 still use SSE registers. Then GP and SSE
// spill in source order, for nine eight-byte stack slots in total.
#define ABI_PARAMS \
    int8_t a1, double a2, uint8_t a3, float a4, int16_t a5, double a6, \
    uint16_t a7, float a8, int32_t a9, double a10, uint32_t a11, int8_t a12, \
    float a13, double a14, float a15, double a16, uint16_t a17, float a18, \
    int16_t a19, double a20, uint8_t a21, float a22, int64_t a23

typedef int64_t (*abi_callback)(ABI_PARAMS);

// Return -1 for misalignment, the first mismatched argument's index, or 673.
int64_t volt_abi_check(ABI_PARAMS)
{
    // With a frame pointer, the call return address and saved rbp occupy 16 bytes.
    if ((uintptr_t)__builtin_frame_address(0) % 16 != 0)
        return -1;
    const int matches[] = {
        a1 == -7, a2 == 1.25, a3 == 251, a4 == -2.5f, a5 == -12345,
        a6 == 3.75, a7 == 54321, a8 == 4.25f, a9 == -123456789, a10 == -5.5,
        a11 == 4000000001u, a12 == -101, a13 == 6.75f, a14 == -7.25, a15 == 8.5f,
        a16 == -9.75, a17 == 65521, a18 == 10.25f, a19 == -23456, a20 == 11.5,
        a21 == 245, a22 == -12.75f, a23 == -1099511627899,
    };
    for (size_t i = 0; i < sizeof matches / sizeof matches[0]; ++i) {
        if (!matches[i])
            return (int64_t)i + 1;
    }
    return 673;
}

int64_t volt_abi_invoke(abi_callback callback)
{
    return callback(-7, 1.25, 251, -2.5f, -12345, 3.75, 54321, 4.25f, -123456789,
                    -5.5, 4000000001u, -101, 6.75f, -7.25, 8.5f, -9.75, 65521,
                    10.25f, -23456, 11.5, 245, -12.75f, -1099511627899);
}
