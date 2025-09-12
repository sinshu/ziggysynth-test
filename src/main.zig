const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const mem = std.mem;

const ziggysynth = @import("ziggysynth.zig");
const SoundFont = ziggysynth.SoundFont;
const Synthesizer = ziggysynth.Synthesizer;
const SynthesizerSettings = ziggysynth.SynthesizerSettings;
const MidiFile = ziggysynth.MidiFile;
const MidiFileSequencer = ziggysynth.MidiFileSequencer;

const rl = @cImport({
    @cInclude("raylib.h");
    @cInclude("raymath.h");
});

const CN = @import("./fft.zig").CN;
const fft = @import("./fft.zig").fft;
const ifft = @import("./fft.zig").ifft;

const screen_width = 1600;
const screen_height = 800;
const sample_rate = 44100;
const buffer_size = 2048;

const backColor = rl.Color{ .r = 0x37, .g = 0x47, .b = 0x4F, .a = 0xFF };
const barColor = rl.Color{ .r = 0x60, .g = 0x7D, .b = 0x8B, .a = 0xFF };
const textColor = rl.Color{ .r = 0xCF, .g = 0xD8, .b = 0xDC, .a = 0xFF };

pub fn main() !void {
    var da = heap.DebugAllocator(.{}){};
    const allocator = da.allocator();
    defer debug.assert(da.deinit() == .ok);

    var fft_in = mem.zeroes([buffer_size]CN);
    var fft_out = mem.zeroes([buffer_size]CN);
    var smoothed = mem.zeroes([buffer_size]f32);

    rl.InitWindow(screen_width, screen_height, "MIDI Player");
    defer rl.CloseWindow();

    rl.InitAudioDevice();
    rl.SetAudioStreamBufferSizeDefault(buffer_size);
    const stream = rl.LoadAudioStream(sample_rate, 16, 2);
    rl.PlayAudioStream(stream);
    var left: [buffer_size]f32 = undefined;
    var right: [buffer_size]f32 = undefined;
    var buffer: [2 * buffer_size]i16 = undefined;

    // Load the SoundFont.
    var sf2 = try fs.cwd().openFile("TimGM6mb.sf2", .{});
    defer sf2.close();
    var sf2_buffer: [1024]u8 = undefined;
    var sf2_reader = sf2.reader(&sf2_buffer);
    var sound_font = try SoundFont.init(allocator, &sf2_reader.interface);
    defer sound_font.deinit();

    // Create the synthesizer.
    var settings = SynthesizerSettings.init(44100);
    var synthesizer = try Synthesizer.init(allocator, &sound_font, &settings);
    defer synthesizer.deinit();

    // Load the MIDI file.
    var mid = try fs.cwd().openFile("d_map01.mid", .{});
    defer mid.close();
    var mid_buffer: [1024]u8 = undefined;
    var mid_reader = mid.reader(&mid_buffer);
    var midi_file = try MidiFile.init(allocator, &mid_reader.interface);
    defer midi_file.deinit();

    // Create the sequencer.
    var sequencer = MidiFileSequencer.init(&synthesizer);

    // Play the MIDI file.
    sequencer.play(&midi_file, true);

    rl.SetTargetFPS(60);

    while (!rl.WindowShouldClose()) {
        if (rl.IsAudioStreamProcessed(stream)) {
            sequencer.render(&left, &right);
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

        rl.BeginDrawing();
        defer rl.EndDrawing();

        rl.ClearBackground(backColor);
        rl.DrawText("MIDI music playback", 750, 150, 75, textColor);
        rl.DrawText("with Zig 0.15.1", 1020, 250, 75, textColor);

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
    }
}
