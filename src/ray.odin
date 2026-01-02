package raytracing

import rl "vendor:raylib"
import lg "core:math/linalg"
import "core:math/rand"
import "core:math"
import "core:fmt"

// Shlick's approximation for reflectance
reflectance :: proc(cosine, refraction_index: f64) -> f64 {
    r0 := (1 - refraction_index) / (1 + refraction_index)
    r0 *= r0
    return r0 + (1-r0)*math.pow((1-cosine), 5)
}

Ray :: struct {
    orig: Vec3,
    dir: Vec3,
}
RayHit :: struct {
    p: Vec3,
    normal: Vec3,
    t: f64,
    front_face: bool,
}
ray_at :: proc "contextless" (ray: Ray, t: f64) -> Vec3  {
    return ray.orig + ray.dir * t
}
ray_set_face_normal :: proc "contextless" (r_hit: ^RayHit, r: Ray, outward_normal: Vec3) {
    r_hit.front_face = lg.dot(r.dir, outward_normal) < 0
    r_hit.normal = r_hit.front_face ? outward_normal : -outward_normal
}



Interval_T :: f64
Interval :: struct {
    min, max: Interval_T
}
interval_contains :: proc "contextless" (i: Interval, x: Interval_T) -> bool {
    return i.min <= x && x <= i.max
}
interval_surrounds :: proc "contextless" (i: Interval, x: Interval_T) -> bool {
    return i.min < x && x < i.max
}
interval_size :: proc "contextless" (i: Interval) -> Interval_T {
    return i.max - i.min
}
interval_clamp :: proc "contextless" (i: Interval, x: Interval_T) -> Interval_T {
    if x < i.min { return i.min }
    if x > i.max { return i.max }
    return x
}
empty    := Interval{  math.F64_MAX, -math.F64_MAX }
universe := Interval{ -math.F64_MAX,  math.F64_MAX }



HittableType :: enum u8 { Sphere, BBox }
Hittable :: struct {
    // Sphere
    center: Vec3,
    radius: f64,
    // Bbox
    // uses center variable
    min: Vec3,
    max: Vec3,

    material: Material,
    type: HittableType,
}
MaterialType :: enum u8 { Lambertian, Metal, Dielectric, DiffuseLight, }
Material :: struct {
    albedo: Vec3,
    fuzz: f64,
    refraction_index: f64,
    type: MaterialType,
}

material_emission :: proc(mat: Material) -> Vec3 {
    return mat.type == .DiffuseLight ? mat.albedo : Vec3Zero
}

material_scatter :: proc(mat: Material, ray: Ray, ray_hit: RayHit, scattered: ^Ray, attenuation: ^Vec3) -> bool {
    switch mat.type {
    case .Lambertian: {
        scattered_dir := ray_hit.normal + vec3_rand_unit()
        if vec3_near_zero(scattered_dir) {
            scattered_dir = ray_hit.normal
        }
        scattered^ = {
            orig = ray_hit.p,
            dir = scattered_dir,
        }
        attenuation^ = mat.albedo
        return true
    }
    case .Metal: {
        reflected := lg.normalize(lg.reflect(ray.dir, ray_hit.normal))
        reflected += mat.fuzz * vec3_rand_unit()
        scattered^ = {
            orig = ray_hit.p,
            dir = reflected,
        }
        attenuation^ = mat.albedo
        return lg.dot(ray_hit.normal, reflected) > 0
    }
    case .Dielectric: {
        ri := ray_hit.front_face ? (1.0 / mat.refraction_index) : mat.refraction_index
        unit_dir := lg.normalize(ray.dir)
        cos_theta := min(lg.dot(-unit_dir, ray_hit.normal), 1.0)
        sin_theta := math.sqrt(1.0 - cos_theta*cos_theta)

        cannot_refract := ri * sin_theta > 1.0
        direction: Vec3
        if cannot_refract || reflectance(cos_theta, ri) > rand.float64_range(0, 1) {
            direction = lg.reflect(unit_dir, ray_hit.normal)
        } else {
            direction = lg.refract(unit_dir, ray_hit.normal, ri)
            direction += mat.fuzz * vec3_rand_unit()
        }

        scattered^ = {
            orig = ray_hit.p,
            dir = direction
        }
        attenuation^ = mat.albedo
        return true
    }
    case .DiffuseLight: {
        return false
    }
    }
    return false
}

new_sphere :: proc "contextless" (center: Vec3, radius: f64, material: Material) -> (sphere: Hittable) {
    sphere.center = center
    sphere.radius = math.max(0, radius)
    sphere.material = material
    sphere.type = .Sphere
    return
}
new_bbox :: proc "contextless" (min, max: Vec3, material: Material) -> (bbox: Hittable) {
    bbox.min = min
    bbox.max = max
    bbox.center = lg.lerp(bbox.min, bbox.max, 0.5)
    bbox.material = material
    bbox.type = .BBox
    return
}

hit_sphere :: proc "contextless" (sphere: Hittable, inter: Interval, r: Ray) -> (result: RayHit, hit: bool) {
    c_o := sphere.center - r.orig
    a := lg.dot(r.dir, r.dir)
    h := lg.dot(r.dir, c_o)
    c := lg.dot(c_o, c_o) - sphere.radius*sphere.radius
    discriminant := h*h - a*c
    if discriminant < 0 {
        return {}, false
    }

    sqrtd := math.sqrt(discriminant)
    root := (h - sqrtd) / a
    // NOTE: why surrounds() instead of contains()?
    if !interval_surrounds(inter, root) {
        root = (h + sqrtd) / a
        if !interval_surrounds(inter, root) {
            return {}, false
        }
    }

    result.t = root
    result.p = ray_at(r, root)
    outward_normal := (result.p - sphere.center) / sphere.radius
    ray_set_face_normal(&result, r, outward_normal)

    return result, true
}

// Almost copy of rl.GetRayCollisionBoundingBox
hit_bbox :: proc(bbox: Hittable, inter: Interval, ray: Ray) -> (result: RayHit, hit: bool) {
    t: [11]f64

    t[8] = 1.0/ray.dir.x
    t[9] = 1.0/ray.dir.y
    t[10] = 1.0/ray.dir.z

    t[0] = (bbox.min.x - ray.orig.x)*t[8]
    t[1] = (bbox.max.x - ray.orig.x)*t[8]
    t[2] = (bbox.min.y - ray.orig.y)*t[9]
    t[3] = (bbox.max.y - ray.orig.y)*t[9]
    t[4] = (bbox.min.z - ray.orig.z)*t[10]
    t[5] = (bbox.max.z - ray.orig.z)*t[10]
    t[6] = math.max(math.max(math.min(t[0], t[1]), math.min(t[2], t[3])), math.min(t[4], t[5]))
    t[7] = math.min(math.min(math.max(t[0], t[1]), math.max(t[2], t[3])), math.max(t[4], t[5]))

    if !interval_surrounds(inter, t[6]) {
        return {}, false
    }
    hit = !((t[7] < 0) || (t[6] > t[7]))
    result.t = t[6]
    result.p = ray.orig + ray.dir * result.t

    // Get vector center point->hit point
    result.normal = result.p - bbox.center
    // Scale vector to unit cube
    // NOTE: We use an additional .01 to fix numerical errors
    result.normal = result.normal * 2.01
    result.normal = result.normal / (bbox.max - bbox.min)
    // The relevant elements of the vector are now slightly larger than 1.0 (or smaller than -1.0)
    // and the others are somewhere between -1.0 and 1.0 casting to int is exactly our wanted normal!
    result.normal.x = f64(i32(result.normal.x))
    result.normal.y = f64(i32(result.normal.y))
    result.normal.z = f64(i32(result.normal.z))
    result.normal = lg.normalize(result.normal)
    return
}
