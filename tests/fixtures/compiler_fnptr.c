#include <stdbool.h>
#include <stdint.h>

// a12 spills while three SSE registers are still free. a16 and a17 spill
// afterwards, leaving three eight-byte stack slots and one alignment slot.
int8_t volt_fnptr_check(int8_t a1, double a2, uint8_t a3, float a4, int16_t a5,
                        double a6, uint16_t a7, float a8, int32_t a9, double a10,
                        uint32_t a11, int8_t a12, float a13, double a14, float a15,
                        float a16, const int64_t *a17)
{
    if ((uintptr_t)__builtin_frame_address(0) % 16 != 0)
        return 1;
    if (a1 != -7 || a2 != 1.25 || a3 != 251 || a4 != -2.5f || a5 != -12345 ||
        a6 != 3.75 || a7 != 54321 || a8 != 4.25f || a9 != -123456789 ||
        a10 != -5.5 || a11 != 4000000001u || a13 != 6.75f || a14 != -7.25 || a15 != 8.5f || !a17)
        return 2;
    // The nested call must not overwrite any stack argument of the outer call.
    if (a12 == -93 && a16 == 20.5f && *a17 == 44)
        return -101;
    if (a12 == -103 && a16 == -101.0f && *a17 == 37)
        return -109;
    return 3;
}

// Model an untyped address from dlsym; the others return typed C pointers.
void *volt_fnptr_mixed(void) { return (void *)volt_fnptr_check; }

static uint16_t narrow_unsigned(void) { return 60001; }
static bool is_zero(uint64_t value) { return value == 0; }
static float half(float value) { return value * 0.5f; }
static int64_t *same_pointer(int64_t *value) { return value; }

uint16_t (*volt_fnptr_unsigned(void))(void) { return narrow_unsigned; }
bool (*volt_fnptr_bool(void))(uint64_t) { return is_zero; }
float (*volt_fnptr_float(void))(float) { return half; }
int64_t *(*volt_fnptr_ptr(void))(int64_t *) { return same_pointer; }
