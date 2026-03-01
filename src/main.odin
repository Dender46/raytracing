package raytracing

import rl "vendor:raylib"
import lg "core:math/linalg"
import "core:math/rand"
import "core:math"
import "core:fmt"
import "core:thread"
import "core:time"
import "core:sync"
import "core:os"

ray_hit_any :: proc(ray: Ray) -> (hit_idx: int, ray_hit: RayHit) {
    hit_idx = -1

    t_interval := Interval{ 0.001, math.F64_MAX }
    for hittable, idx in state.hit_list {
        temp_hit: RayHit
        hit: bool
        switch hittable.type {
        case .Sphere: {
            temp_hit, hit = hit_sphere(hittable, t_interval, ray)
        }
        case .BBox: {
            temp_hit, hit = hit_bbox(hittable, t_interval, ray)
        }
        }
        if hit {
            hit_idx = idx
            t_interval.max = temp_hit.t // closest so far value
            ray_hit = temp_hit
        }
    }
    return
}

ray_color :: proc(ray: Ray, iter: i32) -> Vec3 {
    if iter > 5 {
        return Vec3One
    }
    hit_idx, ray_hit := ray_hit_any(ray)

    if hit_idx == -1 {
        unit_dir := lg.normalize(ray.dir)
        a := 0.5*(unit_dir.y + 1.0)
        return (1.0-a) * Vec3One + a * Vec3{0.5, 0.7, 1.0}
        // return (1.0-a) * Vec3{0.89, 0.65, 0.34} + a * Vec3{0.77, 0.63, 0.95}

    }

    scattered: Ray
    attenuation: Vec3
    hit_mat := state.hit_list[hit_idx].material
    material_emission := material_emission(hit_mat)
    if !material_scatter(hit_mat, ray, ray_hit, &scattered, &attenuation) {
        return material_emission
    }
    return attenuation * ray_color(scattered, iter+1)
}

SAMPLES_PER_PIXEL :: 500

window_size := [2]i32{ 800, 1200 }
image_scale := f32(1)
image_size := [2]i32{
    i32(f32(window_size.x) * image_scale),
    i32(f32(window_size.y) * image_scale),
}

window_props := Window{
    name = "Raytracing",
    size = window_size,
    size_f = { f32(window_size.x), f32(window_size.y) },
    fps = 60,
}

main :: proc() {
    game_init()
    for game_update() {
        continue
    }
    game_shutdown()
}

// @(export)
game_init :: proc() {
    state = new(State)
    state.window = window_props
    state.request_rerender = false // should be false on first render - thread are starting from clean/ready to render state

    rl.SetConfigFlags(state.window.config_flags)
    rl.InitWindow(window_size.x, window_size.y, state.window.name)

    state.cam = new_camera()
    // state.cam.position = {-2, 2, 1}
    // state.cam.look_at  = {0, 0, -1}
    // state.cam.up       = {0, 1, 0}
    state.cam.position = {0, 2, 3}
    state.cam.look_at  = {0, 0.5, -1}
    state.cam.focus_dist = 3.4

    generate_rand_unit_vectors_3d(state.unit_vec3_cache[:])
    generate_rand_unit_vectors_2d(state.unit_vec2_cache[:])

    init()
    camera_update(&state.cam)

    thread_count := os.processor_core_count()*2
    sync.barrier_init(&state.rerender_clean_end, thread_count+1)
    sync.barrier_init(&state.rerender_clean_start, thread_count+1)
    sync.barrier_init(&state.rerender_signal, thread_count+1)

    pixels_per_thread := i32(len(state.normalized_buffer) / thread_count)
    state.threads = make([dynamic]^thread.Thread, 0, thread_count)
    state.threads_data = make([dynamic]ThreadData, 0, thread_count)

    for i in 0..<thread_count {
        i := i32(i)
        t := thread.create(render_pass_threaded)

        append(&state.threads_data, ThreadData{
            begin = i * pixels_per_thread,
            end = i * pixels_per_thread + pixels_per_thread,
            samples_count_left = SAMPLES_PER_PIXEL,
            cam = state.cam,
        })
        t.data = &state.threads_data[i]

        thread.start(t)
        append(&state.threads, t)
    }
}

init :: proc() {
    state.window = window_props
    rl.SetTargetFPS(state.window.fps)

    state.cam.vFov = 90
    state.cam.defocus_angle = 0.0
    state.cam.focus_dist = 2.5
    // state.cam.defocus_angle = 0.0

    if rl.IsRenderTextureValid(state.screen_tex) { rl.UnloadRenderTexture(state.screen_tex) }
    if rl.IsRenderTextureValid(state.rt_tex)     { rl.UnloadRenderTexture(state.rt_tex) }
    delete_dynamic_array(state.normalized_buffer)
    delete_dynamic_array(state.texture_buffer)
    state.normalized_buffer = make([dynamic]Vec3, image_size.x * image_size.y)
    state.texture_buffer    = make([dynamic]rl.Color, image_size.x * image_size.y)
    state.screen_tex = rl.LoadRenderTexture(image_size.x, image_size.y)
    state.rt_tex     = rl.LoadRenderTexture(image_size.x, image_size.y)
    for i in 0..<len(state.normalized_buffer) {
        state.normalized_buffer[i] = Vec3Zero
    }


    brightness :: proc(col: Vec3, factor: f64) -> Vec3 {
        return {
            (1.0 - col.r)*factor + col.r,
            (1.0 - col.g)*factor + col.g,
            (1.0 - col.b)*factor + col.b,
        }
    }

    //{0.8, 0.8, 0.0}
    mat_ground := Material{ {0.8, 0.94, 0.86}, 0.3, 0.0, .Metal }
    mat_center := Material{ {0.1, 0.2, 0.5}, 0.0, 0.0, .Lambertian }
    mat_left   := Material{ brightness({0.8, 0.9, 1.0}, 0.9), 0.0, 1.5, .Dielectric }
    mat_bubble := Material{ brightness({0.8, 0.9, 1.0}, 0.9), 0.0, 1.0 / 1.5, .Dielectric }
    // mat_right  := Material{ {0.8, 0.6, 0.2}, 0.5, 0.0, .Metal }
    mat_right  := Material{ {0.8, 0.6, 0.2}, 0.2, 0.0, .Metal }
    mat_light  := Material{ {1.0, 0.6, 0.2}, 0.0, 0.0, .DiffuseLight }

    clear(&state.hit_list)
    append(&state.hit_list, new_sphere({0, -100.5, -1}, 100.5, mat_ground))

    christmas_tree_entities :: proc() {
        tree_mat := Material{ {0.25, 0.41, 0.04}, 0.9, 0.0, .Metal }
        green_bulb_mat := Material{ brightness({0.25, 0.41, 0.04}, 0.15), 0.0, 2.5, .Dielectric }
        red_bulb_mat := Material{ {0.8, 0.1, 0.04}, 0.3, 0.0, .Metal }
        blue_bulb_mat := Material{ {0.1, 0.3, 0.8}, 0.3, 0.0, .Metal }
        mat_right  := Material{ {0.8, 0.6, 0.2}, 0.2, 0.0, .Metal }

        count_max := f64(14)
        count := count_max
        height := f64(15)
        for h in 0..<height {

            t := h / height
            count -= t*2

            for i in 0..<count+1 {
                i := f64(i)
                x := math.cos(math.PI * (i / count)) * (1.0 - t)
                z := math.sin(math.PI * (i / count)) * (1.0 - t)
                y := (h)*0.2

                x += rand.float64_range(-0.05, 0.05)
                z += rand.float64_range(-0.05, 0.05)
                size := rand.float64_range(0.13, 0.17)
                append(&state.hit_list, new_sphere({ x, y, z }, size, tree_mat))
            }
        }

        count = 6
        height = f64(5)
        mat_idx := 0
        for h in 0..<height {

            t := (h) / height
            count -= t*2.2

            for i in 0..<count+1 {
                i := f64(i)
                x := math.cos(math.PI * (i / count)) * (1.0 - t) * 1.2
                z := math.sin(math.PI * (i / count)) * (1.0 - t) * 1.2
                y := h * 0.58

                x += rand.float64_range(-0.04, 0.04)
                z += rand.float64_range(-0.04, 0.04)
                y += rand.float64_range(-0.1, 0.1)
                size := rand.float64_range(0.15, 0.18)
                mats := []Material{ green_bulb_mat, red_bulb_mat, blue_bulb_mat, mat_right }
                mat := mats[mat_idx%len(mats)]
                if mat != green_bulb_mat {
                    mat.fuzz = rand.float64_range(0.0, 0.3)
                }
                append(&state.hit_list, new_sphere({ x, y+0.2, z }, size, mat))
                mat_idx += 1
            }
        }
        append(&state.hit_list, new_sphere({ 0, 2.9, 0 }, 0.23, mat_right))
    }

    append(&state.hit_list, new_sphere({ 0.0,  0.5, -1.2}, 0.5, mat_center))
    // append(&state.hit_list, new_sphere({-1.0,  0.0, -1.0}, 0.5, mat_left))
    // append(&state.hit_list, new_sphere({ 1.0,  0.0, -1.0}, 0.5, mat_right))
    // append(&state.hit_list, new_sphere({ 1.0,  0.0, -1.0}, 0.5, mat_light))
    // append(&state.hit_list, new_bbox({-0.6, -0.45, -0.5}, {-0.2, 0, -1}))
}

// @(export)
game_hot_reloaded :: proc(memFromOldApi: ^State) {
    state = memFromOldApi
    init()
}

// @(export)
game_update :: proc() -> bool {
    state.request_rerender = state.request_rerender || camera_controls() || rl.IsKeyPressed(.R)

    if rl.IsMouseButtonPressed(.LEFT) && !guiControlExclusiveMode {
        if false {
            focus_point := rl.GetMousePosition() * image_scale
            // focus_point := image_size / 2
            ray := get_straight_ray_from_camera(state.cam, f64(focus_point.x), f64(focus_point.y))
            hit_idx, ray_hit := ray_hit_any(ray)
            if hit_idx != -1 {
                state.cam.focus_dist = lg.length(state.cam.position - ray_hit.p) * 1.2
                state.request_rerender = true
            }
        }
    }

    camera_update(&state.cam)

    @(static) render_time: f32 = 0.0
    if state.request_rerender {
        render_time = 0.0
    }
    finished_threads_count := 0
    for d, idx in state.threads_data {
        if d.samples_count_left <= 0 {
            finished_threads_count += 1
        }
    }
    if finished_threads_count != len(state.threads_data) {
        render_time += rl.GetFrameTime()
    }

    if state.request_rerender {
        // Notify threads to stop and reset their state and buffer region in order to rerender
        for &tData in state.threads_data {
            tData.cam = state.cam
        }
        _ = sync.atomic_add(&state.rerender_gen, 1)
        sync.barrier_wait(&state.rerender_clean_start)
        sync.barrier_wait(&state.rerender_clean_end)
        rl.UpdateTexture(state.rt_tex.texture, raw_data(state.texture_buffer))
        sync.barrier_wait(&state.rerender_signal)
        state.request_rerender = false
    } else {
        rl.UpdateTexture(state.rt_tex.texture, raw_data(state.texture_buffer))
    }


    // Technically we can just draw state.rt_tex texture straigh to the screen,
    // But maybe later this can be used for something interesting
    rl.BeginTextureMode(state.screen_tex)
        w := f32(state.rt_tex.texture.width)
        h := f32(state.rt_tex.texture.height)
        rl.DrawTextureRec(state.rt_tex.texture, {0, 0, w, -h}, 0, rl.ColorFromNormalized([4]f32{1, 1, 1, 1}))
    rl.EndTextureMode()

    rl.BeginDrawing()
        rl.ClearBackground(rl.WHITE)
        rl.DrawTextureEx(state.screen_tex.texture, {0, 0}, 0, 1.0 / image_scale, rl.WHITE)

        // val_f32 := f32(state.cam.defocus_angle)
        // rerender = GuiSlider_Custom({window_props.size_f.x-150, 0, 150, 25}, "Text", "", &val_f32, 0.0, 30.0)
        // state.cam.defocus_angle = f64(val_f32)

        debug_text("Current render time: ", render_time)

        debug_text_draw_queued_and_reset()

        @(static) hotReloadTimer: f32 = 3 // statics and globals gets reset when reloading DLL
        debug_hot_reload_notification(&hotReloadTimer, "RELOADED")
        rl.DrawFPS(10, 10)

    rl.EndDrawing()

    free_all(context.temp_allocator)

    return !rl.WindowShouldClose()
}

render_pass_threaded :: proc(t: ^thread.Thread) {
    data := (^ThreadData)(t.data)
    local_rerender_gen := sync.atomic_load(&state.rerender_gen)

    for true {
        rerender_gen := sync.atomic_load(&state.rerender_gen)
        if local_rerender_gen != rerender_gen {
            sync.barrier_wait(&state.rerender_clean_start)
            local_rerender_gen = rerender_gen
            data = (^ThreadData)(t.data)
            for i in data.begin..<data.end {
                state.normalized_buffer[i] = Vec3Zero
            }

            data.samples_count_left = SAMPLES_PER_PIXEL
            // Do one pass and let main thread to render to screen to avoid tearing
            render_pass(data.begin, data.end, data.samples_count_left, data.cam)
            data.samples_count_left -= 1
            sync.barrier_wait(&state.rerender_clean_end)
            sync.barrier_wait(&state.rerender_signal)

        }

        if data.samples_count_left > 0 {
            render_pass(data.begin, data.end, data.samples_count_left, data.cam)
            data.samples_count_left -= 1
        } else {
            time.sleep(time.Millisecond * 5)
        }
    }
}

render_pass :: proc(begin, end, samples_count_left: i32, cam: Camera) {
    for i in begin..<end {
        i := i32(i)
        x := f64(i % image_size.x)
        y := f64(i / image_size.x)

        ray: Ray
        when SAMPLES_PER_PIXEL == 1 {
            ray = get_straight_ray_from_camera(cam, x, y)
            state.normalized_buffer[i] = ray_color(ray, 0)
        } else {
            ray = get_ray_from_camera(cam, x, y)
            state.normalized_buffer[i] += ray_color(ray, 0)
        }
    }

    frame_count := f64(SAMPLES_PER_PIXEL - samples_count_left + 1)
    for i in begin..<end {
        col := state.normalized_buffer[i]
        when SAMPLES_PER_PIXEL != 1 {
            col /= frame_count
        }
        r := f32(linear_to_gamma(col.x))
        g := f32(linear_to_gamma(col.y))
        b := f32(linear_to_gamma(col.z))
        state.texture_buffer[i] = rl.ColorFromNormalized([4]f32{r, g, b, 1.0})
    }
}

// @(export)
game_shutdown :: proc() {
    for t in state.threads {
        thread.terminate(t, 0)
        thread.destroy(t)
    }
    rl.UnloadTexture(state.screen_tex.texture)
    if rl.IsRenderTextureValid(state.screen_tex) { rl.UnloadRenderTexture(state.screen_tex) }
    if rl.IsRenderTextureValid(state.rt_tex)     { rl.UnloadRenderTexture(state.rt_tex) }
    delete_dynamic_array(state.normalized_buffer)
    delete_dynamic_array(state.texture_buffer)
    delete_dynamic_array(state.hit_list)
    delete_dynamic_array(state.threads)
    delete_dynamic_array(state.threads_data)

    free(state)
}

// @(export)
game_memory :: proc() -> rawptr {
    return state
}
