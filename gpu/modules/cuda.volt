# Optional NVIDIA CUDA Driver API for Linux x86-64 SysV. Only the system
# loader is linked; libcuda.so.1 is opened by cuda_open at runtime.
link "-lc"

unsafe extern fn dlopen(path: ptr<char>, flags: i32) -> ptr<char>
unsafe extern fn dlsym(library: ptr<char>, symbol: ptr<char>) -> ptr<char>
unsafe extern fn dlclose(library: ptr<char>) -> i32

const CUDA_SUCCESS: i64 = 0
const CUDA_ERROR_INVALID_VALUE: i64 = 1
const CUDA_ERROR_NOT_INITIALIZED: i64 = 3
const CUDA_ERROR_STUB_LIBRARY: i64 = 34
const CUDA_ERROR_NO_DEVICE: i64 = 100
const CUDA_ERROR_SYSTEM_DRIVER_MISMATCH: i64 = 803
const CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE: i64 = 804
const CUDA_DRIVER_UNAVAILABLE: i64 = -1
const CUDA_DRIVER_INCOMPATIBLE: i64 = -2
const CUDA_DRIVER_CLOSE_FAILED: i64 = -3

struct CudaDriver:
    library: ptr<char>
    device_count: ptr<char>
    device_get: ptr<char>
    device_name: ptr<char>
    context_create: ptr<char>
    context_destroy: ptr<char>
    synchronize: ptr<char>
    alloc: ptr<char>
    free: ptr<char>
    copy_to_device: ptr<char>
    copy_to_host: ptr<char>
    module_load: ptr<char>
    module_function: ptr<char>
    module_unload: ptr<char>
    launch: ptr<char>
    error_name: ptr<char>

# shortcut: replace these stubs when the driver symbols are bound to typed fnptr signatures.
# Every target here (other than launch) takes 0–3 integer-class arguments
# and returns a 32-bit CUresult in eax. The native prologue aligns rsp.
unsafe native fn __volt_cuda_call(entry: ptr<char>, a: u64, b: u64, c: u64) -> i64:
{
    mov rax, rdi
    mov rdi, rsi
    mov rsi, rdx
    mov rdx, rcx
    call rax
    movsxd rax, eax
}

# Five stack slots for blockDimZ=1, sharedMemBytes=0, hStream=NULL,
# kernelParams=args, extra=NULL; the sixth slot preserves 16-byte alignment.
unsafe native fn __volt_cuda_launch_1d(entry: ptr<char>, kernel: ptr<char>, blocks: u32, threads: u32, args: ptr<ptr<char>>) -> i64:
{
    mov rax, rdi
    sub rsp, 48
    mov qword ptr [rsp], 1
    mov qword ptr [rsp + 8], 0
    mov qword ptr [rsp + 16], 0
    mov qword ptr [rsp + 24], r8
    mov qword ptr [rsp + 32], 0
    mov rdi, rsi
    mov esi, edx
    mov edx, 1
    mov r8d, ecx
    mov ecx, 1
    mov r9d, 1
    call rax
    add rsp, 48
    movsxd rax, eax
}

unsafe fn __volt_cuda_bind(library: ptr<char>, name: string, entry: ptr<ptr<char>>) -> bool:
    *entry = dlsym(library, name as ptr<char>)
    return *entry != (0 as ptr<char>)

unsafe fn __volt_cuda_resolve(driver: ptr<CudaDriver>, library: ptr<char>) -> i64:
    let init: ptr<char>
    if not __volt_cuda_bind(library, "cuInit", &init): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuDeviceGetCount", &driver.device_count): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuDeviceGet", &driver.device_get): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuDeviceGetName", &driver.device_name): return CUDA_DRIVER_INCOMPATIBLE
    # Bind the versioned context/memory ABI, never its unsuffixed predecessors.
    if not __volt_cuda_bind(library, "cuCtxCreate_v2", &driver.context_create): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuCtxDestroy_v2", &driver.context_destroy): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuCtxSynchronize", &driver.synchronize): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuMemAlloc_v2", &driver.alloc): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuMemFree_v2", &driver.free): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuMemcpyHtoD_v2", &driver.copy_to_device): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuMemcpyDtoH_v2", &driver.copy_to_host): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuModuleLoadData", &driver.module_load): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuModuleGetFunction", &driver.module_function): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuModuleUnload", &driver.module_unload): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuLaunchKernel", &driver.launch): return CUDA_DRIVER_INCOMPATIBLE
    if not __volt_cuda_bind(library, "cuGetErrorName", &driver.error_name): return CUDA_DRIVER_INCOMPATIBLE
    return __volt_cuda_call(init, 0, 0, 0)

unsafe fn __volt_cuda_ready(driver: ptr<CudaDriver>) -> bool:
    return driver != (0 as ptr<CudaDriver>) and driver.library != (0 as ptr<char>)

# Start with a zero-initialized CudaDriver. Keep exactly one owner of each open.
unsafe fn cuda_open(driver: ptr<CudaDriver>) -> i64:
    if driver == (0 as ptr<CudaDriver>) or __volt_cuda_ready(driver): return CUDA_ERROR_INVALID_VALUE
    let library: ptr<char> = dlopen("libcuda.so.1" as ptr<char>, 2)  # RTLD_NOW | RTLD_LOCAL
    if library == (0 as ptr<char>): return CUDA_DRIVER_UNAVAILABLE
    let loaded: CudaDriver
    let status: i64 = __volt_cuda_resolve(&loaded, library)
    if status != CUDA_SUCCESS:
        dlclose(library)
        return status
    loaded.library = library
    *driver = loaded
    return CUDA_SUCCESS

unsafe fn cuda_close(driver: ptr<CudaDriver>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_SUCCESS
    if dlclose(driver.library) != 0: return CUDA_DRIVER_CLOSE_FAILED
    let closed: CudaDriver
    *driver = closed
    return CUDA_SUCCESS

# Non-static names belong to the driver and are valid only while it is open.
unsafe fn cuda_error_name(driver: ptr<CudaDriver>, status: i64) -> string:
    if status == CUDA_SUCCESS: return "CUDA_SUCCESS"
    if status == CUDA_ERROR_INVALID_VALUE: return "CUDA_ERROR_INVALID_VALUE"
    if status == CUDA_ERROR_NOT_INITIALIZED: return "CUDA_ERROR_NOT_INITIALIZED"
    if status == CUDA_ERROR_STUB_LIBRARY: return "CUDA_ERROR_STUB_LIBRARY"
    if status == CUDA_ERROR_NO_DEVICE: return "CUDA_ERROR_NO_DEVICE"
    if status == CUDA_ERROR_SYSTEM_DRIVER_MISMATCH: return "CUDA_ERROR_SYSTEM_DRIVER_MISMATCH"
    if status == CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE: return "CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE"
    if status == CUDA_DRIVER_UNAVAILABLE: return "libcuda.so.1 could not be loaded"
    if status == CUDA_DRIVER_INCOMPATIBLE: return "libcuda.so.1 is missing required Driver API symbols"
    if status == CUDA_DRIVER_CLOSE_FAILED: return "libcuda.so.1 could not be closed"
    if status > 0 and status <= 2147483647 and __volt_cuda_ready(driver):
        let name: ptr<char>
        if __volt_cuda_call(driver.error_name, status as u64, (&name) as u64, 0) == CUDA_SUCCESS and name != (0 as ptr<char>):
            return name as string
    return "unknown CUDA Driver API error"

unsafe fn cuda_device_count(driver: ptr<CudaDriver>, count: ptr<i32>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if count == (0 as ptr<i32>): return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.device_count, count as u64, 0, 0)

unsafe fn cuda_device_get(driver: ptr<CudaDriver>, device: ptr<i32>, ordinal: i32) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if device == (0 as ptr<i32>) or ordinal < 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.device_get, device as u64, ordinal as u64, 0)

unsafe fn cuda_device_name(driver: ptr<CudaDriver>, name: ptr<char>, capacity: i32, device: i32) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if name == (0 as ptr<char>) or capacity <= 0 or device < 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.device_name, name as u64, capacity as u64, device as u64)

# Creating a context makes it current on the calling thread.
unsafe fn cuda_context_create(driver: ptr<CudaDriver>, context: ptr<ptr<char>>, device: i32) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if context == (0 as ptr<ptr<char>>) or device < 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.context_create, context as u64, 0, device as u64)

unsafe fn cuda_context_destroy(driver: ptr<CudaDriver>, context: ptr<char>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if context == (0 as ptr<char>): return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.context_destroy, context as u64, 0, 0)

unsafe fn cuda_synchronize(driver: ptr<CudaDriver>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    return __volt_cuda_call(driver.synchronize, 0, 0, 0)

# CUdeviceptr is a 64-bit value, not a host pointer; size_t is u64 here.
unsafe fn cuda_alloc(driver: ptr<CudaDriver>, address: ptr<u64>, bytes: u64) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if address == (0 as ptr<u64>) or bytes == 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.alloc, address as u64, bytes, 0)

unsafe fn cuda_free(driver: ptr<CudaDriver>, address: u64) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if address == 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.free, address, 0, 0)

unsafe fn cuda_copy_to_device(driver: ptr<CudaDriver>, address: u64, host: ptr<char>, bytes: u64) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if address == 0 or host == (0 as ptr<char>) or bytes == 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.copy_to_device, address, host as u64, bytes)

unsafe fn cuda_copy_to_host(driver: ptr<CudaDriver>, host: ptr<char>, address: u64, bytes: u64) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if address == 0 or host == (0 as ptr<char>) or bytes == 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.copy_to_host, host as u64, address, bytes)

unsafe fn cuda_module_load_ptx(driver: ptr<CudaDriver>, module: ptr<ptr<char>>, ptx: string) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if module == (0 as ptr<ptr<char>>) or (ptx as ptr<char>) == (0 as ptr<char>): return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.module_load, module as u64, (ptx as ptr<char>) as u64, 0)

unsafe fn cuda_module_function(driver: ptr<CudaDriver>, kernel: ptr<ptr<char>>, module: ptr<char>, name: string) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if kernel == (0 as ptr<ptr<char>>) or module == (0 as ptr<char>) or (name as ptr<char>) == (0 as ptr<char>):
        return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.module_function, kernel as u64, module as u64, (name as ptr<char>) as u64)

unsafe fn cuda_module_unload(driver: ptr<CudaDriver>, module: ptr<char>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if module == (0 as ptr<char>): return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_call(driver.module_unload, module as u64, 0, 0)

unsafe fn cuda_launch_1d(driver: ptr<CudaDriver>, kernel: ptr<char>, blocks: u32, threads: u32, args: ptr<ptr<char>>) -> i64:
    if not __volt_cuda_ready(driver): return CUDA_ERROR_NOT_INITIALIZED
    if kernel == (0 as ptr<char>) or blocks == 0 or threads == 0: return CUDA_ERROR_INVALID_VALUE
    return __volt_cuda_launch_1d(driver.launch, kernel, blocks, threads, args)
