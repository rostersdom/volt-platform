use math

struct Vec2:
    x: f64
    y: f64

struct Vec3:
    x: f64
    y: f64
    z: f64

# Operations write into `out` to keep these vector helpers allocation-free.
unsafe fn vec2_add(a: Vec2, b: Vec2, out: ptr<Vec2>):
    out.x = a.x + b.x
    out.y = a.y + b.y

unsafe fn vec2_scale(v: Vec2, scale: f64, out: ptr<Vec2>):
    out.x = v.x * scale
    out.y = v.y * scale

fn vec2_dot(a: Vec2, b: Vec2) -> f64:
    return a.x * b.x + a.y * b.y

# Column-major: values[column * 4 + row].
struct Mat4:
    values: [16]f64

unsafe fn vec3_add(a: Vec3, b: Vec3, out: ptr<Vec3>):
    out.x = a.x + b.x
    out.y = a.y + b.y
    out.z = a.z + b.z

unsafe fn vec3_sub(a: Vec3, b: Vec3, out: ptr<Vec3>):
    out.x = a.x - b.x
    out.y = a.y - b.y
    out.z = a.z - b.z

unsafe fn vec3_scale(v: Vec3, scale: f64, out: ptr<Vec3>):
    out.x = v.x * scale
    out.y = v.y * scale
    out.z = v.z * scale

fn vec3_dot(a: Vec3, b: Vec3) -> f64:
    return a.x * b.x + a.y * b.y + a.z * b.z

unsafe fn vec3_cross(a: Vec3, b: Vec3, out: ptr<Vec3>):
    out.x = a.y * b.z - a.z * b.y
    out.y = a.z * b.x - a.x * b.z
    out.z = a.x * b.y - a.y * b.x

unsafe fn vec3_normalize(v: Vec3, out: ptr<Vec3>):
    let length: f64 = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    if length == 0.0:
        out.x = 0.0
        out.y = 0.0
        out.z = 0.0
    else:
        out.x = v.x / length
        out.y = v.y / length
        out.z = v.z / length

unsafe fn mat4_identity(out: ptr<Mat4>):
    for i in 0..16:
        out.values[i] = 0.0
    out.values[0] = 1.0
    out.values[5] = 1.0
    out.values[10] = 1.0
    out.values[15] = 1.0

unsafe fn mat4_multiply(a: Mat4, b: Mat4, out: ptr<Mat4>):
    let values: [16]f64
    for column in 0..4:
        for row in 0..4:
            let value: f64 = 0.0
            for k in 0..4:
                value = value + a.values[k * 4 + row] * b.values[column * 4 + k]
            values[column * 4 + row] = value
    for i in 0..16:
        out.values[i] = values[i]

unsafe fn mat4_transform_point(matrix: Mat4, point: Vec3, out: ptr<Vec3>):
    let x: f64 = matrix.values[0] * point.x + matrix.values[4] * point.y + matrix.values[8] * point.z + matrix.values[12]
    let y: f64 = matrix.values[1] * point.x + matrix.values[5] * point.y + matrix.values[9] * point.z + matrix.values[13]
    let z: f64 = matrix.values[2] * point.x + matrix.values[6] * point.y + matrix.values[10] * point.z + matrix.values[14]
    let w: f64 = matrix.values[3] * point.x + matrix.values[7] * point.y + matrix.values[11] * point.z + matrix.values[15]
    if w != 0.0:
        x = x / w
        y = y / w
        z = z / w
    out.x = x
    out.y = y
    out.z = z
