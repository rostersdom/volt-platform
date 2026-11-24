use cuda

unsafe fn cuda_smoke_check(driver: ptr<CudaDriver>, operation: string, status: i64, failed: ptr<bool>) -> bool:
    if status == CUDA_SUCCESS: return true
    print("CUDA:", operation, "failed:", status, cuda_error_name(driver, status))
    *failed = true
    return false

unsafe fn cuda_smoke_compute(driver: ptr<CudaDriver>, device: i32, failed: ptr<bool>):
    # One GPU thread adds the second parameter to the u32 at the first parameter.
    let ptx: string = (
        ".version 6.0\n.target sm_50\n.address_size 64\n" +
        ".visible .entry volt_add(.param .u64 data, .param .u32 amount) {\n" +
        ".reg .b64 %p, %g;\n.reg .b32 %v, %a;\n" +
        "ld.param.u64 %p, [data];\nld.param.u32 %a, [amount];\n" +
        "cvta.to.global.u64 %g, %p;\nld.global.u32 %v, [%g];\n" +
        "add.u32 %v, %v, %a;\nst.global.u32 [%g], %v;\nret;\n}\n"
    )
    let context: ptr<char>
    if not cuda_smoke_check(driver, "cuCtxCreate_v2", cuda_context_create(driver, &context, device), failed): return
    defer cuda_smoke_check(driver, "cuCtxDestroy_v2", cuda_context_destroy(driver, context), failed)

    let address: u64
    let bytes: u64 = sizeof(u32) as u64
    if not cuda_smoke_check(driver, "cuMemAlloc_v2", cuda_alloc(driver, &address, bytes), failed): return
    defer cuda_smoke_check(driver, "cuMemFree_v2", cuda_free(driver, address), failed)
    let input: u32 = 19
    let increment: u32 = 23
    if not cuda_smoke_check(driver, "cuMemcpyHtoD_v2", cuda_copy_to_device(driver, address, (&input) as ptr<char>, bytes), failed): return

    let module: ptr<char>
    if not cuda_smoke_check(driver, "cuModuleLoadData", cuda_module_load_ptx(driver, &module, ptx), failed): return
    defer cuda_smoke_check(driver, "cuModuleUnload", cuda_module_unload(driver, module), failed)
    let kernel: ptr<char>
    if not cuda_smoke_check(driver, "cuModuleGetFunction", cuda_module_function(driver, &kernel, module, "volt_add"), failed): return
    let args: [2]ptr<char> = [(&address) as ptr<char>, (&increment) as ptr<char>]
    if not cuda_smoke_check(driver, "cuLaunchKernel", cuda_launch_1d(driver, kernel, 1, 1, &args[0]), failed): return
    if not cuda_smoke_check(driver, "cuCtxSynchronize", cuda_synchronize(driver), failed): return

    let output: u32
    if not cuda_smoke_check(driver, "cuMemcpyDtoH_v2", cuda_copy_to_host(driver, (&output) as ptr<char>, address, bytes), failed): return
    if output != 42:
        print("CUDA: wrong GPU result, expected 42, got", output)
        *failed = true

unsafe fn cuda_smoke_device(driver: ptr<CudaDriver>, failed: ptr<bool>) -> i64:
    let count: i32
    let status: i64 = cuda_device_count(driver, &count)
    if status == CUDA_SUCCESS and count == 0: status = CUDA_ERROR_NO_DEVICE
    if not cuda_smoke_check(driver, "cuDeviceGetCount", status, failed):
        if status == CUDA_ERROR_NO_DEVICE: return 77
        return 1
    let device: i32
    if not cuda_smoke_check(driver, "cuDeviceGet", cuda_device_get(driver, &device, 0), failed): return 1
    let name: [128]char
    if not cuda_smoke_check(driver, "cuDeviceGetName", cuda_device_name(driver, &name[0], sizeof([128]char) as i32, device), failed): return 1
    print("CUDA device:", (&name[0]) as string, "- visible devices:", count)
    cuda_smoke_compute(driver, device, failed)
    return 0

fn main() -> i64:
    unsafe:
        let driver: CudaDriver
        let failed: bool = false
        let status: i64 = cuda_open(&driver)
        if not cuda_smoke_check(&driver, "cuda_open", status, &failed):
            if status == CUDA_DRIVER_UNAVAILABLE or status == CUDA_ERROR_NO_DEVICE: return 77
            return 1
        let outcome: i64 = cuda_smoke_device(&driver, &failed)
        if not cuda_smoke_check(&driver, "cuda_close", cuda_close(&driver), &failed): return 1
        if outcome != 0: return outcome
        if failed: return 1
        print("CUDA PTX smoke passed: 19 + 23 = 42")
    return 0
