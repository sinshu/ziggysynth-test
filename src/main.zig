const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const mem = std.mem;
const fmt = std.fmt;

const ziggysynth = @import("ziggysynth.zig");
const SoundFont = ziggysynth.SoundFont;
const Synthesizer = ziggysynth.Synthesizer;
const SynthesizerSettings = ziggysynth.SynthesizerSettings;

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const CN = @import("./fft.zig").CN;
const fft = @import("./fft.zig").fft;

const screen_width = 1600;
const screen_height = 800;
const sample_rate = 44100;
const buffer_size = 2048;

const backColor = rl.Color{ .r = 0x37, .g = 0x47, .b = 0x4F, .a = 0xFF };
const barColor = rl.Color{ .r = 0x60, .g = 0x7D, .b = 0x8B, .a = 0xFF };
const textColor = rl.Color{ .r = 0xCF, .g = 0xD8, .b = 0xDC, .a = 0xFF };
const whiteKeyColor = rl.Color{ .r = 0xF4, .g = 0xF7, .b = 0xFA, .a = 0xFF };
const whiteKeyPressedColor = rl.Color{ .r = 0xB3, .g = 0xC6, .b = 0xD8, .a = 0xFF };
const blackKeyColor = rl.Color{ .r = 0x15, .g = 0x19, .b = 0x1F, .a = 0xFF };
const blackKeyPressedColor = rl.Color{ .r = 0x3C, .g = 0x4F, .b = 0x60, .a = 0xFF };
const outlineColor = rl.Color{ .r = 0x30, .g = 0x34, .b = 0x38, .a = 0xFF };

const base_note: u8 = 48;
const total_keys = 24;
const click_velocity: i32 = 110;

const PianoKey = struct {
    note: u8,
    is_black: bool,
    rect: rl.Rectangle,
    pressed: bool,
};

fn isBlack(note: u8) bool {
    return switch (note % 12) {
        1, 3, 6, 8, 10 => true,
        else => false,
    };
}

fn pointInRect(rect: rl.Rectangle, point: rl.Vector2) bool {
    return point.x >= rect.x and point.x <= rect.x + rect.width and point.y >= rect.y and point.y <= rect.y + rect.height;
}

fn noteNameZ(buf: []u8, note: u8) [:0]const u8 {
    const names = [_][]const u8{ "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" };
    const idx = @as(usize, @intCast(note % 12));
    const octave = @as(i32, @intCast(note / 12)) - 1;
    return fmt.bufPrintZ(buf, "{s}{d}", .{ names[idx], octave }) catch unreachable;
}

pub fn main() !void {
    var da = heap.DebugAllocator(.{}){};
    const allocator = da.allocator();
    defer debug.assert(da.deinit() == .ok);

    var fft_in = mem.zeroes([buffer_size]CN);
    var fft_out = mem.zeroes([buffer_size]CN);
    var smoothed = mem.zeroes([buffer_size]f32);

    rl.InitWindow(screen_width, screen_height, "Interactive Synth");
    defer rl.CloseWindow();

    rl.InitAudioDevice();
    defer rl.CloseAudioDevice();
    rl.SetAudioStreamBufferSizeDefault(buffer_size);
    const stream = rl.LoadAudioStream(sample_rate, 16, 2);
    defer rl.UnloadAudioStream(stream);
    rl.PlayAudioStream(stream);

    var left: [buffer_size]f32 = undefined;
    var right: [buffer_size]f32 = undefined;
    var buffer: [2 * buffer_size]i16 = undefined;

    var sf2 = try fs.cwd().openFile("TimGM6mb.sf2", .{});
    defer sf2.close();
    var sf2_buffer: [1024]u8 = undefined;
    var sf2_reader = sf2.reader(&sf2_buffer);
    var sound_font = try SoundFont.init(allocator, &sf2_reader.interface);
    defer sound_font.deinit();

    var settings = SynthesizerSettings.init(sample_rate);
    var synthesizer = try Synthesizer.init(allocator, &sound_font, &settings);
    defer synthesizer.deinit();
    defer synthesizer.noteOffAll(true);

    var keys: [total_keys]PianoKey = undefined;

    var white_count: usize = 0;
    for (0..total_keys) |idx| {
        const note = base_note + @as(u8, @intCast(idx));
        if (!isBlack(note)) {
            white_count += 1;
        }
    }

    const keyboard_margin: f32 = 120.0;
    const keyboard_width = @as(f32, @floatFromInt(screen_width)) - keyboard_margin * 2.0;
    const keyboard_start_x = keyboard_margin;
    const keyboard_top: f32 = 420.0;
    const white_key_height: f32 = 300.0;
    const white_key_width = keyboard_width / @as(f32, @floatFromInt(white_count));
    const black_key_width = white_key_width * 0.6;
    const black_key_height = white_key_height * 0.6;

    var white_index: f32 = 0.0;
    for (&keys, 0..) |*key, idx| {
        const note = base_note + @as(u8, @intCast(idx));
        const is_black = isBlack(note);
        key.* = .{
            .note = note,
            .is_black = is_black,
            .rect = undefined,
            .pressed = false,
        };

        if (!is_black) {
            const x = keyboard_start_x + white_index * white_key_width;
            key.rect = rl.Rectangle{
                .x = x,
                .y = keyboard_top,
                .width = white_key_width,
                .height = white_key_height,
            };
            white_index += 1.0;
        } else {
            const base_center = keyboard_start_x + (white_index - 0.5) * white_key_width;
            const adjusted_center = base_center + white_key_width * 0.5;
            key.rect = rl.Rectangle{
                .x = adjusted_center - black_key_width / 2.0,
                .y = keyboard_top,
                .width = black_key_width,
                .height = black_key_height,
            };
        }
    }

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        if (rl.IsAudioStreamProcessed(stream)) {
            synthesizer.render(left[0..], right[0..]);
            for (0..buffer_size) |t| {
                var left_sample_i32: i32 = @intFromFloat(32768.0 * left[t]);
                if (left_sample_i32 < -32768) {
                    left_sample_i32 = -32768;
                }
                if (left_sample_i32 > 32767) {
                    left_sample_i32 = 32767;
                }
                var right_sample_i32: i32 = @intFromFloat(32768.0 * right[t]);
                if (right_sample_i32 < -32768) {
                    right_sample_i32 = -32768;
                }
                if (right_sample_i32 > 32767) {
                    right_sample_i32 = 32767;
                }
                const left_sample_i16: i16 = @truncate(left_sample_i32);
                const right_sample_i16: i16 = @truncate(right_sample_i32);
                buffer[2 * t] = left_sample_i16;
                buffer[2 * t + 1] = right_sample_i16;

                fft_in[t].re = 0.5 * (left[t] + right[t]);
                fft_in[t].im = 0.0;
            }
            rl.UpdateAudioStream(stream, &buffer, buffer_size);
            fft(buffer_size, &fft_in, &fft_out);
        }

        const mouse_position = rl.GetMousePosition();
        const is_mouse_down = rl.IsMouseButtonDown(rl.MOUSE_BUTTON_LEFT);
        var hovered_index: ?usize = null;
        if (is_mouse_down) {
            var i: usize = 0;
            while (i < keys.len) : (i += 1) {
                if (keys[i].is_black and pointInRect(keys[i].rect, mouse_position)) {
                    hovered_index = i;
                    break;
                }
            }
            if (hovered_index == null) {
                i = 0;
                while (i < keys.len) : (i += 1) {
                    if (!keys[i].is_black and pointInRect(keys[i].rect, mouse_position)) {
                        hovered_index = i;
                        break;
                    }
                }
            }
        }

        if (!is_mouse_down) {
            for (&keys) |*key| {
                if (key.pressed) {
                    synthesizer.noteOff(0, @as(i32, @intCast(key.note)));
                    key.pressed = false;
                }
            }
        } else {
            const hovered_idx = hovered_index;
            for (&keys, 0..) |*key, idx| {
                const keep_pressed = if (hovered_idx) |value| value == idx else false;
                if (key.pressed and !keep_pressed) {
                    synthesizer.noteOff(0, @as(i32, @intCast(key.note)));
                    key.pressed = false;
                }
            }
            if (hovered_idx) |idx| {
                var key = &keys[idx];
                if (!key.pressed) {
                    synthesizer.noteOn(0, @as(i32, @intCast(key.note)), click_velocity);
                    key.pressed = true;
                }
            }
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(backColor);
        rl.DrawText("Interactive piano", 70, 70, 70, textColor);
        rl.DrawText("Click keys to play notes", 70, 150, 40, textColor);

        const lim = screen_width / 4;
        for (0..lim) |t| {
            const c = fft_out[t];
            const val = @as(f32, @floatCast(100 * @max(@log10(c.re * c.re + c.im * c.im) + 1.5, 0.0)));
            if (val > smoothed[t]) {
                smoothed[t] = 0.5 * smoothed[t] + 0.5 * val;
            } else {
                smoothed[t] = 0.95 * smoothed[t] + 0.05 * val;
            }
            const top = @as(f32, @floatFromInt(screen_height)) - smoothed[t];
            rl.DrawRectangle(@as(c_int, @intCast(4 * t)), @as(i32, @intFromFloat(top)), 2, @as(i32, @intFromFloat(smoothed[t])) + 2, barColor);
        }

        // Draw white keys first so black keys layer on top.
        for (&keys) |key| {
            if (!key.is_black) {
                const color = if (key.pressed) whiteKeyPressedColor else whiteKeyColor;
                rl.DrawRectangleRec(key.rect, color);
                rl.DrawRectangleLinesEx(key.rect, 2.0, outlineColor);

                var label_buf: [8:0]u8 = undefined;
                const label = noteNameZ(&label_buf, key.note);
                const text_x = @as(c_int, @intFromFloat(key.rect.x + key.rect.width * 0.35));
                const text_y = @as(c_int, @intFromFloat(key.rect.y + key.rect.height - 40.0));
                rl.DrawText(label.ptr, text_x, text_y, 24, outlineColor);
            }
        }

        // Draw black keys afterwards.
        for (&keys) |key| {
            if (key.is_black) {
                const color = if (key.pressed) blackKeyPressedColor else blackKeyColor;
                rl.DrawRectangleRec(key.rect, color);
            }
        }

        var active_label: ?[:0]const u8 = null;
        var active_buf: [8:0]u8 = undefined;
        for (keys) |key| {
            if (key.pressed) {
                active_label = noteNameZ(&active_buf, key.note);
                break;
            }
        }
        if (active_label) |label| {
            rl.DrawText(label.ptr, 70, 210, 40, textColor);
        }
    }
}
