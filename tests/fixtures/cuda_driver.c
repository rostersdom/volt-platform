/* CPU-only Driver API stand-in: check the ABI and log resource order. */
#include <assert.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifdef VOLT_TEST_CUDA_NO_LIBRARY
void *dlopen(const char *name, int flags) {
    assert(strcmp(name, "libcuda.so.1") == 0 && flags == (RTLD_NOW | RTLD_LOCAL));
    return NULL;
}
#else

static char context, module, kernel;
static uint32_t word;
static const uint64_t address = UINT64_C(0xfedcba9876543210);

static int mode(const char *expected) {
    const char *current = getenv("VOLT_TEST_CUDA_MODE");
    return current && strcmp(current, expected) == 0;
}

static void trace(const char *line) {
    size_t size = strlen(line);
    assert(write(STDERR_FILENO, line, size) == (ssize_t)size);
}

__attribute__((destructor)) static void unloaded(void) {
    trace("dlclose\n");
}

int cuInit(unsigned flags) {
    assert(flags == 0);
    trace("init\n");
    return mode("no-device") ? 100 : 0;
}

int cuDeviceGetCount(int *count) {
    trace("count\n");
    *count = mode("zero-devices") ? 0 : 1;
    return 0;
}

int cuDeviceGet(int *device, int ordinal) {
    assert(ordinal == 0);
    *device = 7;
    return 0;
}

int cuDeviceGetName(char *name, int length, int device) {
    const char text[] = "fixture GPU";
    assert(device == 7 && length >= (int)sizeof text);
    memcpy(name, text, sizeof text);
    return 0;
}

int cuCtxCreate_v2(void **out, unsigned flags, int device) {
    assert(flags == 0 && device == 7);
    trace("context\n");
    *out = &context;
    return 0;
}

int cuCtxDestroy_v2(void *handle) {
    assert(handle == &context);
    trace("destroy\n");
    return 0;
}

int cuCtxSynchronize(void) {
    trace("sync\n");
    return 0;
}

int cuMemAlloc_v2(uint64_t *out, size_t bytes) {
    assert(bytes == sizeof word);
    trace("alloc\n");
    *out = address;
    return 0;
}

int cuMemFree_v2(uint64_t ptr) {
    assert(ptr == address);
    trace("free\n");
    return mode("free-fails") ? 1 : 0;
}

int cuMemcpyHtoD_v2(uint64_t dst, const void *src, size_t bytes) {
    assert(dst == address && bytes == sizeof word);
    trace("HtoD\n");
    memcpy(&word, src, bytes);
    return 0;
}

int cuMemcpyDtoH_v2(void *dst, uint64_t src, size_t bytes) {
    assert(src == address && bytes == sizeof word);
    trace("DtoH\n");
    memcpy(dst, &word, bytes);
    return 0;
}

int cuModuleLoadData(void **out, const void *image) {
    assert(strstr(image, ".visible .entry volt_add") != NULL);
    trace("module\n");
    *out = &module;
    return 0;
}

int cuModuleGetFunction(void **out, void *handle, const char *name) {
    assert(handle == &module && strcmp(name, "volt_add") == 0);
    *out = &kernel;
    return 0;
}

int cuModuleUnload(void *handle) {
    assert(handle == &module);
    trace("unload\n");
    return 0;
}

#ifndef VOLT_TEST_CUDA_MISSING_SYMBOL
int cuLaunchKernel(void *fn, unsigned gx, unsigned gy, unsigned gz,
                   unsigned bx, unsigned by, unsigned bz, unsigned shared,
                   void *stream, void **params, void **extra) {
    assert(fn == &kernel && gx == 1 && gy == 1 && gz == 1);
    assert(bx == 1 && by == 1 && bz == 1 && shared == 0);
    assert(stream == NULL && extra == NULL && params != NULL);
    assert(*(const uint64_t *)params[0] == address);
    uint32_t increment = *(const uint32_t *)params[1];
    assert(word == 19 && increment == 23);
    trace("launch\n");
    if (mode("launch-fails")) return 701;
    word += increment;
    return 0;
}
#endif

int cuGetErrorName(int status, const char **name) {
    assert(status == 701);
    *name = "CUDA_ERROR_LAUNCH_OUT_OF_RESOURCES";
    return 0;
}
#endif
