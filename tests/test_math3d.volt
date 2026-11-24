use math3d

fn main() -> i64:
    unsafe:
        let uv = Vec2(0.5, 1.5)
        let uv_result = Vec2(0.0, 0.0)
        vec2_add(uv, Vec2(1.0, 2.0), &uv_result)
        print("vec2:", uv_result.x, uv_result.y, vec2_dot(uv, uv_result))

        let a = Vec3(1.0, 2.0, 3.0)
        let b = Vec3(4.0, 5.0, 6.0)
        let result = Vec3(0.0, 0.0, 0.0)

        vec3_add(a, b, &result)
        print("add:", result.x, result.y, result.z)
        vec3_sub(a, b, &result)
        print("sub:", result.x, result.y, result.z)
        vec3_scale(a, 2.0, &result)
        print("scale:", result.x, result.y, result.z)
        print("dot:", vec3_dot(a, b))
        vec3_cross(a, b, &result)
        print("cross:", result.x, result.y, result.z)
        vec3_normalize(a, &result)
        print("normalize:", result.x, result.y, result.z)
        vec3_normalize(Vec3(0.0, 0.0, 0.0), &result)
        print("normalize zero:", result.x, result.y, result.z)

        let identity: Mat4
        let translation: Mat4
        let scale: Mat4
        let product: Mat4
        mat4_identity(&identity)
        let point = Vec3(7.0, -2.0, 5.0)
        mat4_transform_point(identity, point, &result)
        print("identity:", result.x, result.y, result.z)
        mat4_identity(&translation)
        translation.values[12] = 10.0
        translation.values[13] = 20.0
        translation.values[14] = 30.0
        mat4_identity(&scale)
        scale.values[0] = 2.0
        scale.values[5] = 3.0
        scale.values[10] = 4.0
        mat4_multiply(scale, translation, &product)
        mat4_transform_point(product, point, &result)
        print("composed:", result.x, result.y, result.z)
        mat4_multiply(scale, translation, &translation)
        mat4_transform_point(translation, point, &result)
        print("alias:", result.x, result.y, result.z)
        return 0
