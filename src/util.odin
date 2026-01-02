package raytracing

import "core:container/small_array"
import "core:fmt"
import "core:math"
import rl "vendor:raylib"

_ :: math

IS_DEBUG :: #config(IS_DEBUG, true)
DEBUG_BOUNDARY :: false

Array :: small_array.Small_Array

// =====================================
// =============== RAYLIB ==============
// =====================================

// These values are identical in raygui.h, but they are static to that file and not exposed
// they are recreated here so we can have same functionality
guiControlExclusiveMode := false
guiControlExclusiveRec := rl.Rectangle{ 0, 0, 0, 0 }

LineDimensions_Orient :: enum { NONE, HOR, VER }

LineDimensions :: struct {
    using _ : struct #raw_union {
        using _: struct { x0, x1: i32 },
        x: i32,
    },
    using _ : struct #raw_union {
        using _: struct { y0, y1: i32 },
        y: i32,
    },
    orient: LineDimensions_Orient,
}

draw_line :: proc(line: LineDimensions, color: rl.Color) {
    switch line.orient {
    case .HOR:  rl.DrawLine(line.x0, line.y, line.x1, line.y, color)
    case .VER:  rl.DrawLine(line.x, line.y0, line.x, line.y1, color)
    case .NONE: rl.DrawLine(line.x0, line.y0, line.x1, line.y1, color)
    }
}

// NOTE: rect is not centered. For centered text it is handled by `pivot` parameter
get_centered_text_rectangle :: proc "contextless" (font: rl.Font, text: cstring, pos: rl.Vector2, pad: i32, fontSize: f32, spacing: f32 = 999) -> rl.Rectangle {
    spacing := spacing
    if spacing == 999 {
        spacing = fontSize / 10
    }
    textSize := rl.MeasureTextEx(font, text, fontSize, spacing)
    return {
        pos.x,
        pos.y,
        textSize.x + f32(pad * 2),
        textSize.y + f32(pad * 2),
    }
}

draw_centered_text :: proc "contextless" (font: rl.Font, text: cstring, pos: rl.Vector2, rot, fontSize: f32, tint: rl.Color) {
    spacing := fontSize / 30
    textRect := get_centered_text_rectangle(font, text, pos, 0, fontSize, spacing)
    pivot := rect_size(textRect) / 2
    when DEBUG_BOUNDARY {
        rl.DrawRectanglePro({ pos.x, pos.y, textRect.width, textRect.height }, pivot, rot, rl.ColorAlpha(rl.RED, 0.3))
    }
    rl.DrawTextPro(font, text, pos, pivot, rot, fontSize, spacing, tint)
}

draw_left_text :: proc "contextless" (font: rl.Font, text: cstring, pos: rl.Vector2, rot, fontSize: f32, tint: rl.Color) {
    spacing := fontSize / 30
    textRect := get_centered_text_rectangle(font, text, pos, 0, fontSize, spacing)
    pivot := rect_size(textRect)
    pivot.x = 0.0
    pivot.y *= 0.5
    when DEBUG_BOUNDARY {
        rl.DrawRectanglePro({ pos.x, pos.y, textRect.width, textRect.height }, pivot, rot, rl.ColorAlpha(rl.RED, 0.3))
    }
    rl.DrawTextPro(font, text, pos, pivot, rot, fontSize, spacing, tint)
}

draw_right_text :: proc "contextless" (font: rl.Font, text: cstring, pos: rl.Vector2, rot, fontSize: f32, tint: rl.Color) {
    spacing := fontSize / 30
    textRect := get_centered_text_rectangle(font, text, pos, 0, fontSize, spacing)
    pivot := rect_size(textRect)
    pivot.y *= 0.5
    when DEBUG_BOUNDARY {
        rl.DrawRectanglePro({ pos.x, pos.y, textRect.width, textRect.height }, pivot, rot, rl.ColorAlpha(rl.RED, 0.3))
    }
    rl.DrawTextPro(font, text, pos, pivot, rot, fontSize, spacing, tint)
}


// ==================================
// =============== UI ===============
// ==================================

linear_to_gamma :: proc{ linear_to_gamma_f64, linear_to_gamma_f32 }
linear_to_gamma_f64 :: proc(val: f64) -> f64 {
    return val > 0 ? math.sqrt(val) : 0
}
linear_to_gamma_f32 :: proc(val: f32) -> f32 {
    return val > 0 ? math.sqrt(val) : 0
}

rect_new :: proc "contextless" (pos: rl.Vector2, size: rl.Vector2) -> rl.Rectangle {
    return {
        pos.x, pos.y,
        size.x, size.y,
    }
}

rect_size :: proc "contextless" (rect: rl.Rectangle) -> rl.Vector2 {
    return { rect.width, rect.height }
}

rect_pos :: proc "contextless" (rect: rl.Rectangle) -> rl.Vector2 {
    return { rect.x, rect.y }
}

rect_move :: proc "contextless" (rect: ^rl.Rectangle, offset: rl.Vector2) {
    rect.x += offset.x
    rect.y += offset.y
}

rect_margin_defer :: proc(rect: ^rl.Rectangle, margin: f32) {
    rect.x -= margin
    rect.y -= margin
    rect.width += margin + margin
    rect.height += margin + margin
}

@(deferred_in_out = rect_margin_defer)
rect_margin_t :: proc(rect: ^rl.Rectangle, margin: f32) {
    rect.x += margin
    rect.y += margin
    rect.width -= margin + margin
    rect.height -= margin + margin
}

rect_margin :: proc(rect: ^rl.Rectangle, margin: f32) {
    rect.x += margin
    rect.y += margin
    rect.width -= margin + margin
    rect.height -= margin + margin
}

rect_get_outline :: proc(rect: rl.Rectangle, rotation: f32) -> (outline: [5]rl.Vector2) {
    corners := rect_get_corners(rect, rotation)
    outline[0] = corners[0]
    outline[1] = corners[1]
    outline[2] = corners[3] // NOTE: swapping bottom corners
    outline[3] = corners[2]
    outline[4] = corners[0]
    return
}

rect_get_corners :: proc(rect: rl.Rectangle, rotation: f32) -> (corners: [4]rl.Vector2) {
    // Only calculate rotation if needed
    if rotation == 0.0 {
        x := rect.x - rect.width / 2
        y := rect.y - rect.height / 2
        corners[0] = { x, y }
        corners[1] = { x + rect.width, y }
        corners[2] = { x, y + rect.height }
        corners[3] = { x + rect.width, y + rect.height }
    } else {
        sinRotation := math.sin(rotation * rl.DEG2RAD)
        cosRotation := math.cos(rotation * rl.DEG2RAD)
        x := rect.x
        y := rect.y
        origin := rect_size(rect) / 2
        dx := -origin.x
        dy := -origin.y

        corners[0].x = x + dx*cosRotation - dy*sinRotation
        corners[0].y = y + dx*sinRotation + dy*cosRotation

        corners[1].x = x + (dx + rect.width)*cosRotation - dy*sinRotation
        corners[1].y = y + (dx + rect.width)*sinRotation + dy*cosRotation

        corners[2].x = x + dx*cosRotation - (dy + rect.height)*sinRotation
        corners[2].y = y + dx*sinRotation + (dy + rect.height)*cosRotation

        corners[3].x = x + (dx + rect.width)*cosRotation - (dy + rect.height)*sinRotation
        corners[3].y = y + (dx + rect.width)*sinRotation + (dy + rect.height)*cosRotation
    }
    return
}

is_mouse_in_rect :: proc(rect: rl.Rectangle) -> bool {
    mousePos := rl.GetMousePosition()
    return rl.CheckCollisionPointRec(mousePos, rect)
}

// Sets guiControlExclusiveMode, guiControlExclusiveRec, so we can tell if element is being manipulated
// even if mouse cursor is outside bounds of slider
GuiSlider_Custom :: proc(bounds: rl.Rectangle, textLeft: cstring, textRight: cstring, value: ^f32, minValue, maxValue: f32) -> bool {
    oldValue := value^
    rl.GuiSlider(bounds, textLeft, textRight, value, minValue, maxValue)
    isChanged := value^ != oldValue

    if rl.GuiState(rl.GuiGetState()) != .STATE_DISABLED && !rl.GuiIsLocked() {
        mousePoint := rl.GetMousePosition()

        if guiControlExclusiveMode { // Allows to keep dragging outside of bounds
            if !rl.IsMouseButtonDown(.LEFT) {
                guiControlExclusiveMode = false
                guiControlExclusiveRec = rl.Rectangle{ 0, 0, 0, 0 }
            }
        } else if rl.CheckCollisionPointRec(mousePoint, bounds) {
            if rl.IsMouseButtonDown(.LEFT) {
                guiControlExclusiveMode = true
                guiControlExclusiveRec = bounds // Store bounds as an identifier when dragging starts
            }
        }
    }
    return isChanged
}

// =====================================
// =============== MATH ===============
// =====================================

// Freya's smooth lerp
// a - from
// b - to
// decay - approx. from 1 (slow) to 25 (fast)
// dt - deltaTime
exp_decay :: proc "contextless" (a, b: $T, decay, dt: f32) -> (result: T) {
    result = b
    if a != b {
        result = b+(a-b)*math.exp(-decay*dt)
    }
    return
}

// TODO: Do I need this, if `math` package already ahs it?
inv_lerp :: proc "contextless" (a, b, val: $T) -> T {
    return (val - a) / (b - a)
}

// TODO: Do I need this, if `math` package already ahs it?
remap :: proc "contextless" (iMin, iMax, oMin, oMax, val: $T) -> T {
    t := inv_lerp(iMin, iMax, val)
    return math.lerp(oMin, oMax, t)
}

// =====================================
// =============== OTHER ===============
// =====================================

rlVec2 :: proc "contextless" (x, y: i32) -> rl.Vector2 {
    return { f32(x), f32(y) }
}

inbetween :: proc "contextless" (val, a, b: $T) -> bool {
    return a <= val && val <= b
}

closesTo :: proc "contextless" (val, a, b: $T) -> f32 {
    diffA := abs(val - a)
    diffB := abs(val - b)
    if diffA < diffB { return a }
    return b
}

bytes_to_int64 :: proc(buf: []u8) -> (res: i64) {
    assert(len(buf) == 8)
    res |= i64(buf[0])
    res |= i64(buf[1]) << 8
    res |= i64(buf[2]) << 16
    res |= i64(buf[3]) << 24
    res |= i64(buf[4]) << 32
    res |= i64(buf[5]) << 40
    res |= i64(buf[6]) << 48
    res |= i64(buf[7]) << 56
    return
}

// =====================================
// =============== DEBUG ===============
// =====================================

DEBUG_TEXT_X                :: 10
DEBUG_TEXT_Y_OFFSET_INIT    :: 35
DEBUG_TEXT_FONT_SIZE        :: 20
DEBUG_TEXT_FONT_COLOR       :: rl.BLACK

debugTextYOffset: i32 = DEBUG_TEXT_Y_OFFSET_INIT
deferedDebugTextBuffer: [256]cstring
deferedDebugTextBufferLen: int

debugTextAfterPos: rl.Vector2

@(disabled = IS_DEBUG==false)
debug_text_draw_queued_and_reset :: proc() {
    for i in 0..<deferedDebugTextBufferLen {
        rl.DrawText(deferedDebugTextBuffer[i], DEBUG_TEXT_X, debugTextYOffset, DEBUG_TEXT_FONT_SIZE, DEBUG_TEXT_FONT_COLOR)
        debugTextYOffset += DEBUG_TEXT_FONT_SIZE
    }

    debugTextYOffset = DEBUG_TEXT_Y_OFFSET_INIT
    deferedDebugTextBufferLen = 0
}

@(disabled = IS_DEBUG==false)
debug_margin :: proc() {
    debugTextYOffset += 10
}

@(disabled = IS_DEBUG==false)
debug_text :: proc(args: ..any) {
    text := fmt.ctprint(..args)
    debugTextAfterPos.x = f32(rl.MeasureText(text, DEBUG_TEXT_FONT_SIZE))
    debugTextAfterPos.y = f32(debugTextYOffset)

    rl.DrawText(text, DEBUG_TEXT_X, debugTextYOffset, DEBUG_TEXT_FONT_SIZE, DEBUG_TEXT_FONT_COLOR)
    debugTextYOffset += DEBUG_TEXT_FONT_SIZE
    return
}

@(disabled = IS_DEBUG==false)
debug_textf :: proc(format: string, args: ..any) {
    text := fmt.ctprintf(format, ..args)
    debugTextAfterPos.x = f32(rl.MeasureText(text, DEBUG_TEXT_FONT_SIZE))
    debugTextAfterPos.y = f32(debugTextYOffset)

    rl.DrawText(text, DEBUG_TEXT_X, debugTextYOffset, DEBUG_TEXT_FONT_SIZE, DEBUG_TEXT_FONT_COLOR)
    debugTextYOffset += DEBUG_TEXT_FONT_SIZE
    return
}

@(disabled = IS_DEBUG==false)
debug_hot_reload_notification :: proc(hotReloadTimer: ^f32, str: cstring) {
    hotReloadTimer := hotReloadTimer
    if hotReloadTimer^ > 0 {
        pos := state.window.size_f / 2
        draw_centered_text(rl.GetFontDefault(), str, pos, 0, 60, rl.ColorAlpha(rl.RED, hotReloadTimer^))
        hotReloadTimer^ = hotReloadTimer^ - rl.GetFrameTime()
        hotReloadTimer^ = clamp(hotReloadTimer^, 0, 3)
    }
}

@(disabled = IS_DEBUG==false)
defered_debug_text :: proc(args: ..any) {
    if deferedDebugTextBufferLen >= len(deferedDebugTextBuffer) {
        return
    }
    deferedDebugTextBuffer[deferedDebugTextBufferLen] = fmt.ctprint(..args)
    deferedDebugTextBufferLen += 1
}

@(disabled = IS_DEBUG==false)
defered_debug_text_f :: proc(format: string, args: ..any) {
    if deferedDebugTextBufferLen >= len(deferedDebugTextBuffer) {
        return
    }
    deferedDebugTextBuffer[deferedDebugTextBufferLen] = fmt.ctprintf(format, ..args)
    deferedDebugTextBufferLen += 1
}
