link "-lm"

unsafe extern fn modf(value: f64, whole: ptr<f64>) -> f64
unsafe extern fn modff(value: f32, whole: ptr<f32>) -> f32

let whole64: f64 = 99.0
let whole32: f32 = 99.0 as f32
unsafe:
    let fraction64 = modf(-12.75, &whole64)
    let fraction32 = modff(8.625 as f32, &whole32)
    print(whole64, fraction64)
    print(whole32, fraction32)
