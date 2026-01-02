package raytracing

import "core:math"
import "core:math/rand"
import lg "core:math/linalg"

Vec4 :: [4]f64
Vec3 :: [3]f64
Vec2 :: [2]f64
Vec4Zero :: [4]f64{0, 0, 0, 0}
Vec3Zero :: [3]f64{0, 0, 0}
Vec2Zero :: [2]f64{0, 0}
Vec4One :: [4]f64{1, 1, 1, 1}
Vec3One :: [3]f64{1, 1, 1}
Vec2One :: [2]f64{1, 1}

// Functions to precompute random unit vectors (is it really better?)
generate_rand_unit_vectors_3d :: proc(result: []Vec3) {
    for &v, idx in result {
        len: f64
        for len == 0.0 || len >= 1 {
            v = vec3_rand(-1, 1)
            len = lg.length2(v)
        }
        // v = lg.normalize0(v)
    }
    assert(result[0] != Vec3Zero)
}
generate_rand_unit_vectors_2d :: proc(result: []Vec3) {
    for &v, idx in result {
        len: f64
        for len == 0.0 || len >= 1 {
            v = vec3_rand(-1, 1)
            v.z = 0.0
            len = lg.length2(v)
        }
        // v = lg.normalize0(v)
    }
    assert(result[0] != Vec3Zero)
}

vec3_near_zero :: proc(v: Vec3) -> bool {
    s :: 1e-8
    return abs(v.x) < s && abs(v.y) < s && abs(v.z) < s
}

vec3_rand :: proc(min, max: f64) -> Vec3 {
    return { rand.float64_range(min, max), rand.float64_range(min, max), rand.float64_range(min, max) }
}
vec3_rand_unit :: proc() -> Vec3 {
    return rand.choice(state.unit_vec3_cache[:])
}
vec3_rand_in_unit_disk :: proc() -> Vec3 {
    return rand.choice(state.unit_vec2_cache[:])
}

vec3_rotate_by_axis_angle :: proc (v: Vec3, axis: Vec3, angle: f64) -> Vec3 {
    axis, angle := axis, angle

    axis = lg.normalize0(axis)

    angle *= 0.5
    a := math.sin(angle)
    b := axis.x*a
    c := axis.y*a
    d := axis.z*a
    a = math.cos(angle)
    w := Vec3{b, c, d}

    wv := lg.cross(w, v)
    wwv := lg.cross(w, wv)

    a *= 2
    wv *= a

    wwv *= 2

    return v + wv + wwv

}