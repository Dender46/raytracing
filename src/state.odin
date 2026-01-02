package raytracing

import "core:thread"
import "core:sync"
import rl "vendor:raylib"

state: ^State
State :: struct {
    window: Window,
    rt_tex                  : rl.RenderTexture,
    screen_tex              : rl.RenderTexture,
    normalized_buffer       : [dynamic]Vec3,
    texture_buffer          : [dynamic]rl.Color,
    cam                     : Camera,

    request_rerender        : bool,
    rerender_barrier        : sync.Barrier,
    hit_list                : [dynamic]Hittable,

    threads                 : [dynamic]^thread.Thread,
    threads_data            : [dynamic]ThreadData,

    unit_vec3_cache         : [1024]Vec3,
    unit_vec2_cache         : [1024]Vec3,

}

Window :: struct {
    name            : cstring,
    size            : [2]i32,
    size_f          : [2]f32,
    fps             : i32,
    config_flags    : rl.ConfigFlags,
}

ThreadData :: struct {
    // Buffer begin and end inidices of elements
    begin: i32,
    end: i32,
    samples_count_left: i32,
}
