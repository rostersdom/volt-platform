link "-L. -lvolt_fnptr_fixture"

unsafe extern fn volt_fnptr_check(a1: i8, a2: f64, a3: u8, a4: f32, a5: i16, a6: f64, a7: u16, a8: f32, a9: i32, a10: f64, a11: u32, a12: i8, a13: f32, a14: f64, a15: f32, a16: f32, a17: ptr<i64>) -> i8
unsafe extern fn volt_fnptr_mixed() -> ptr<char>
unsafe extern fn volt_fnptr_unsigned() -> fnptr<() -> u16>
unsafe extern fn volt_fnptr_bool() -> fnptr<(u64) -> bool>
unsafe extern fn volt_fnptr_float() -> fnptr<(f32) -> f32>
unsafe extern fn volt_fnptr_ptr() -> fnptr<(ptr<i64>) -> ptr<i64>>

unsafe fn step(order: ptr<i64>, expected: i64, value: i64) -> i64:
    if *order != expected: panic("argument evaluation order\n")
    *order += 1
    return value

unsafe fn clear_target(slot: ptr<fnptr<(i8, f64, u8, f32, i16, f64, u16, f32, i32, f64, u32, i8, f32, f64, f32, f32, ptr<i64>) -> i8>>, order: ptr<i64>, payload: ptr<i64>) -> ptr<i64>:
    step(order, 3, 0)
    let empty: fnptr<(i8, f64, u8, f32, i16, f64, u16, f32, i32, f64, u32, i8, f32, f64, f32, f32, ptr<i64>) -> i8>
    *slot = empty
    return payload

unsafe:
    let call = volt_fnptr_mixed() as fnptr<(i8, f64, u8, f32, i16, f64, u16, f32, i32, f64, u32, i8, f32, f64, f32, f32, ptr<i64>) -> i8>
    let order: i64 = 0
    let payload: i64 = 37
    let inner_payload: i64 = 44
    print(volt_fnptr_check(-7, 1.25, 251, -2.5, -12345, 3.75, 54321, 4.25,
                           -123456789, -5.5, 4000000001, -93, 6.75, -7.25, 8.5, 20.5, &inner_payload) as i64)
    # A nested indirect call also uses all three spill slots. The last argument
    # replaces the local callee with null after the outer address was captured.
    let result = call(step(&order, 0, -7), 1.25, 251, -2.5, -12345, 3.75, 54321, 4.25,
                      -123456789, -5.5, 4000000001, step(&order, 1, -103), 6.75, -7.25, 8.5,
                      call(step(&order, 2, -7), 1.25, 251, -2.5, -12345, 3.75, 54321, 4.25,
                           -123456789, -5.5, 4000000001, -93, 6.75, -7.25, 8.5, 20.5, &inner_payload),
                      clear_target(&call, &order, &payload)) as i64
    print(result, not call, order)
    let unsigned_result = volt_fnptr_unsigned()
    let bool_result = volt_fnptr_bool()
    let float_result = volt_fnptr_float()
    let ptr_result = volt_fnptr_ptr()
    defer print(float_result(-19.5))
    if bool_result(256): panic("unused bits corrupted bool result\n")
    print(unsigned_result() as u64, bool_result(256), bool_result(0), *ptr_result(&payload))
