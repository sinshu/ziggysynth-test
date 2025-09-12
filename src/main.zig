const std = @import("std");
const debug = std.debug;
const fs = std.fs;
const heap = std.heap;

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

const screen_width = 1600;
const screen_height = 800;
const sample_rate = 44100;
const buffer_size = 2048;

pub fn main() !void {
    var da = heap.DebugAllocator(.{}){};
    const allocator = da.allocator();
    defer debug.assert(da.deinit() == .ok);

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
    var mid = try fs.cwd().openFile("flourish.mid", .{});
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

                //fft_in[t].re = 0.5 * (left[t] + right[t]);
                //fft_in[t].im = 0.0;
            }
            rl.UpdateAudioStream(stream, &buffer, buffer_size);
        }

        rl.BeginDrawing();
        defer rl.EndDrawing();

        const textColor = rl.Color{ .r = 0xB2, .g = 0xDF, .b = 0xDB, .a = 0xFF };

        rl.ClearBackground(rl.SKYBLUE);
        rl.DrawText("MIDI music playback", 750, 150, 75, textColor);
        rl.DrawText("with raylib-zig", 900, 250, 75, textColor);
    }
}
