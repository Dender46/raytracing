#+feature using-stmt
package raytracing

import "core:math"
import "core:math/rand"
import lg "core:math/linalg"
import rl "vendor:raylib"

Camera :: struct {
    position: Vec3,
    look_at: Vec3,
    up: Vec3,
    vFov: f64,

    viewport_size: Vec2,

    pixel_delta_u: Vec3,
    pixel_delta_v: Vec3,

    viewport_upper_left: Vec3,
    pixel_00_loc: Vec3,

    defocus_angle: f64,
    focus_dist: f64,
    defocus_disk_u: Vec3,
    defocus_disk_v: Vec3,
}

new_camera :: proc() -> (cam: Camera) {
    using cam

    position = { 0, 0, 0 }
    look_at  = { 0, 0, -1 }
    up       = { 0, 1, 0 }

    vFov = 90.0

    defocus_angle = 10.0
    focus_dist = 3.4

    return
}

get_ray_from_camera :: proc(cam: Camera, x, y: f64) -> (ray: Ray) {
    offset_x := rand.float64_range(-0.5, 0.5)
    offset_y := rand.float64_range(-0.5, 0.5)
    pixel_sample := cam.pixel_00_loc +
        ((x + offset_x) * cam.pixel_delta_u) +
        ((y + offset_y) * cam.pixel_delta_v)

    if cam.defocus_angle <= 0 {
        ray.orig = cam.position
    } else {
        // defocus disk sample
        p := vec3_rand_in_unit_disk()
        ray.orig = cam.position + (p.x * cam.defocus_disk_u) + (p.y * cam.defocus_disk_v)
    }
    ray.dir = pixel_sample - ray.orig
    return
}

get_straight_ray_from_camera :: proc "contextless" (cam: Camera, x, y: f64) -> (ray: Ray) {
    pixel_sample := cam.pixel_00_loc + (x * cam.pixel_delta_u) + (y * cam.pixel_delta_v)

    ray.orig = cam.position
    ray.dir = pixel_sample - ray.orig
    return
}

camera_controls :: proc() -> (changed: bool) {
    move_speed := 1 * f64(rl.GetFrameTime())
    if rl.IsKeyDown(.LEFT_SHIFT) {
        move_speed *= 3
    }
    move_dir: Vec3
    if rl.IsKeyDown(.W) { move_dir.z = move_speed }
    if rl.IsKeyDown(.S) { move_dir.z = -move_speed }

    if rl.IsKeyDown(.A) { move_dir.x = -move_speed }
    if rl.IsKeyDown(.D) { move_dir.x = move_speed }

    if rl.IsKeyDown(.LEFT_CONTROL) { move_dir.y = -move_speed }
    if rl.IsKeyDown(.SPACE) { move_dir.y = move_speed }

    camera_move_x(&state.cam, move_dir.x)
    camera_move_y(&state.cam, move_dir.y)
    camera_move_z(&state.cam, move_dir.z)

    mouse_delta: Vec2
    if rl.IsMouseButtonDown(.RIGHT) {
        mouse_delta = Vec2{ f64(rl.GetMouseDelta().x), f64(rl.GetMouseDelta().y) }
        if mouse_delta != Vec2Zero {
            rl.DisableCursor()
            mouse_sensitivity := 0.2 * f64(rl.GetFrameTime())
            camera_yaw(&state.cam, -mouse_delta.x * mouse_sensitivity)
            camera_pitch(&state.cam, -mouse_delta.y * mouse_sensitivity)
        }
    } else {
        if rl.IsCursorHidden() { rl.EnableCursor() }
    }

    changed = move_dir != Vec3Zero || mouse_delta != Vec2Zero

    return
}

camera_update :: proc(cam: ^Camera) {
    using cam

    theta := math.RAD_PER_DEG * vFov
    h := math.tan(theta / 2)
    viewport_size.y = 2 * h * focus_dist
    viewport_size.x = viewport_size.y * (f64(image_size.x) / f64(image_size.y))

    w := lg.normalize(position - look_at) // -forward
    u := lg.normalize(lg.cross(up, w))    // -right
    v := lg.cross(u, w)                   // up

    viewport_u := viewport_size.x * u
    viewport_v := viewport_size.y * v

    pixel_delta_u = viewport_u / f64(image_size.x)
    pixel_delta_v = viewport_v / f64(image_size.y)

    viewport_upper_left = position - (focus_dist * w) - viewport_u/2 - viewport_v/2
    pixel_00_loc = viewport_upper_left + 0.5 * (pixel_delta_u + pixel_delta_v)

    defocus_radius := focus_dist * math.tan(math.RAD_PER_DEG * (defocus_angle / 2))
    defocus_disk_u = u * defocus_radius
    defocus_disk_v = -v * defocus_radius
}

camera_move_x :: proc(cam: ^Camera, speed: f64) {
    using cam
    forward := lg.normalize(look_at - position)

    right := lg.normalize(lg.cross(forward, up)) * speed
    position += right
    look_at += right
}

camera_move_y :: proc(cam: ^Camera, speed: f64) {
    using cam
    up_world := Vec3{0, 1, 0} * speed
    position += up_world
    look_at += up_world
}

camera_move_z :: proc(cam: ^Camera, speed: f64) {
    using cam
    forward := lg.normalize(look_at - position) * speed
    position += forward
    look_at += forward
}

// Rotates the camera around its up vector
// Yaw is "looking left and right"
// Note: angle must be provided in radians
camera_yaw :: proc(cam: ^Camera, angle: f64) {
    using cam

    target_position := look_at - position
    target_position = vec3_rotate_by_axis_angle(target_position, up, angle)

    look_at = position + target_position
}

// Rotates the camera around its right vector
// Pitch is "looking up and down"
// NOTE: angle must be provided in radians
camera_pitch :: proc(cam: ^Camera, angle: f64) {
    using cam
    angle := angle

    target_position := look_at - position

    // Clamp view up
    max_angle_up := lg.angle_between(up, target_position)
    max_angle_up -= 0.001 // avoid numerical errors
    if (angle > max_angle_up) {
        angle = max_angle_up
    }

    // Clamp view down
    max_angle_down := lg.angle_between(-up, target_position)
    max_angle_down *= -1.0 // downwards angle is negative
    max_angle_down += 0.001 // avoid numerical errors
    if (angle < max_angle_down) {
        angle = max_angle_down
    }

    // Rotation axis
    forward := lg.normalize(look_at - position)
    right := lg.normalize(lg.cross(forward, up))

    // Rotate view vector around right axis
    target_position = vec3_rotate_by_axis_angle(target_position, right, angle)

    look_at = position + target_position
}

// Rotates the camera around its forward vector
// Roll is "turning your head sideways to the left or right"
// Note: angle must be provided in radians
camera_roll :: proc(cam: ^Camera, angle: f64) {
    using cam
    forward := lg.normalize(look_at - position)
    up = vec3_rotate_by_axis_angle(up, forward, angle)
}
