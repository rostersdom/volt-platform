#include <stddef.h>
#include <stdint.h>

struct small {
    int8_t code;
    int16_t delta;
    uint32_t mask;
};

int64_t c_struct_small_layout(int64_t size, int64_t align, int64_t code,
                              int64_t delta, int64_t mask) {
    return size == sizeof(struct small) && align == _Alignof(struct small) &&
           code == offsetof(struct small, code) && delta == offsetof(struct small, delta) &&
           mask == offsetof(struct small, mask);
}

int64_t c_struct_small_arg(struct small value) {
    return value.code == -117 && value.delta == -12345 && value.mask == UINT32_C(4000000001);
}

struct small c_struct_small_result(int64_t which) {
    if (which == 57)
        return (struct small){-101, -23456, UINT32_C(3900000001)};
    return (struct small){0, 0, 0};
}

struct tiny { uint8_t a, b, c; };
struct pair { int64_t left, right; };
struct mixed { double value; int32_t tag; };
struct floats { double a, b; };
struct packed_eightbyte { float value; int32_t tag; };

struct tiny c_struct_tiny(struct tiny x) {
    return (struct tiny){x.c, x.a, x.b};
}

struct pair c_struct_pair(struct pair x) {
    return (struct pair){x.right + 10, x.left + 20};
}

struct mixed c_struct_mixed(struct mixed x) {
    return (struct mixed){x.value + 0.75, x.tag + 4};
}

struct floats c_struct_floats(struct floats x) {
    return (struct floats){x.b + 0.25, x.a + 0.5};
}

struct packed_eightbyte c_struct_merge(struct packed_eightbyte x) {
    return (struct packed_eightbyte){x.value * 2.0f, x.tag + 1};
}

int64_t c_struct_spill(int64_t a, int64_t b, int64_t c, int64_t d, int64_t e,
                       struct pair value, int64_t tail, struct tiny last) {
    return a == 1 && b == 2 && c == 3 && d == 4 && e == 5 &&
           value.left == 31 && value.right == 77 && tail == 90 &&
           last.a == 123 && last.b == 12 && last.c == 45;
}

int64_t c_struct_spill_sse(double a, double b, double c, double d, double e, double f,
                           double g, double h, struct mixed value, int64_t tail) {
    return a + b + c + d + e + f + g + h == 36 && value.value == 2.5 &&
           value.tag == 90 && tail == 55;
}

int64_t c_struct_snapshot(struct tiny first, int64_t later) {
    return first.a + first.b + first.c + later;
}
