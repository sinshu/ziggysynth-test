const std = @import("std");
const ziggysynth = @import("ziggysynth.zig");
const rl = @cImport({
    @cInclude("raylib.h");
});

const debug = std.debug;
const fs = std.fs;
const heap = std.heap;
const mem = std.mem;
const Allocator = mem.Allocator;

const SoundFont = ziggysynth.SoundFont;
const Synthesizer = ziggysynth.Synthesizer;
const SynthesizerSettings = ziggysynth.SynthesizerSettings;
const MidiFile = ziggysynth.MidiFile;
const MidiFileSequencer = ziggysynth.MidiFileSequencer;

const CN = @import("./fft.zig").CN;
const fft = @import("./fft.zig").fft;
const ifft = @import("./fft.zig").ifft;

const sample_rate = 44100;
const buffer_size = 2048;
const screen_width = 1600;
const screen_height = 800;

pub fn main() anyerror!void {
    var gpa = heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    defer debug.assert(gpa.deinit() == .ok);

    var fft_in = mem.zeroes([buffer_size]CN);
    var fft_out = mem.zeroes([buffer_size]CN);
    var smoothed = mem.zeroes([buffer_size]f32);

    rl.InitWindow(screen_width, screen_height, "MIDI Player");

    rl.InitAudioDevice();
    rl.SetAudioStreamBufferSizeDefault(buffer_size);

    var stream = rl.LoadAudioStream(sample_rate, 16, 2);
    var left: [buffer_size]f32 = undefined;
    var right: [buffer_size]f32 = undefined;
    var buffer: [2 * buffer_size]i16 = undefined;

    rl.PlayAudioStream(stream);

    // Load the SoundFont.
    var sf2 = try fs.cwd().openFile("TimGM6mb.sf2", .{});
    defer sf2.close();
    var sound_font = try SoundFont.init(allocator, sf2.reader());
    defer sound_font.deinit();

    // Create the synthesizer.
    var settings = SynthesizerSettings.init(44100);
    var synthesizer = try Synthesizer.init(allocator, &sound_font, &settings);
    defer synthesizer.deinit();

    // Load the MIDI file.
    var mid = try fs.cwd().openFile("flourish.mid", .{});
    defer mid.close();
    var midi_file = try MidiFile.init(allocator, mid.reader());
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
                var left_sample_i32: i32 = @intFromFloat(i32, 32768.0 * left[t]);
                if (left_sample_i32 < -32768) {
                    left_sample_i32 = -32768;
                }
                if (left_sample_i32 > 32767) {
                    left_sample_i32 = 32767;
                }
                var right_sample_i32: i32 = @intFromFloat(i32, 32768.0 * right[t]);
                if (right_sample_i32 < -32768) {
                    right_sample_i32 = -32768;
                }
                if (right_sample_i32 > 32767) {
                    right_sample_i32 = 32767;
                }
                var left_sample_i16 = @truncate(i16, left_sample_i32);
                var right_sample_i16 = @truncate(i16, right_sample_i32);
                buffer[2 * t] = left_sample_i16;
                buffer[2 * t + 1] = right_sample_i16;

                fft_in[t].re = 0.5 * (left[t] + right[t]);
                fft_in[t].im = 0.0;
            }
            rl.UpdateAudioStream(stream, &buffer, buffer_size);
        }

        fft(buffer_size, &fft_in, &fft_out);

        var backColor = rl.Color{ .r = 0x00, .g = 0x69, .b = 0x5C, .a = 0xFF };
        var barColor = rl.Color{ .r = 0x00, .g = 0x96, .b = 0x88, .a = 0xFF };
        var textColor = rl.Color{ .r = 0xB2, .g = 0xDF, .b = 0xDB, .a = 0xFF };

        rl.BeginDrawing();
        rl.ClearBackground(backColor);
        rl.DrawText("MIDI music playback", 750, 150, 75, textColor);
        rl.DrawText("with raylib-zig", 900, 250, 75, textColor);

        const lim = screen_width / 4;
        for (0..lim) |t| {
            const c = fft_out[t];
            const val = @floatCast(f32, 100 * @max(@log10(c.re * c.re + c.im * c.im) + 1.5, 0.0));
            if (val > smoothed[t]) {
                smoothed[t] = 0.5 * smoothed[t] + 0.5 * val;
            } else {
                smoothed[t] = 0.95 * smoothed[t] + 0.05 * val;
            }
            const top = @floatFromInt(f32, screen_height) - smoothed[t];
            rl.DrawRectangle(@intCast(c_int, 4 * t), @intFromFloat(i32, top), 2, @intFromFloat(i32, smoothed[t]) + 2, barColor);
        }

        rl.EndDrawing();
    }

    rl.CloseWindow();
}
