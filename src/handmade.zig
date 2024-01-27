///TODO(rosh): Services that platform layer provides to the game
///NOTE(rosh): Services that game provides to the platform layer.
/// (this may expand in the future - sound on seperate thread, etc.)
///
/// FOUR THINGS - timing, controller/keyboard input, bitmap buffer to use, sound buffer to use
///
/// TODO(rosh): In the future, rendering __specifically__ will become a three-tiered abstraction!!!!
///
const std = @import("std");
const math = std.math;
pub const game_offscreen_buffer = struct {
    memory: ?*anyopaque = null,
    width: i32 = undefined,
    height: i32 = undefined,
    pitch: usize = undefined,
    bytesPerPixel: u8 = 4,
};

pub const game_sound_output_buffer = struct {
    samples: [*]i16 = undefined,
    samplesPerSecond: u32 = undefined,
    samplesCount: u32 = undefined,
};

var tSine: f32 = undefined;
fn GameOutputSound(soundBuffer: *game_sound_output_buffer, toneHz: u32) void {
    const toneVolume: u32 = 3000;
    var sampleOut = soundBuffer.samples;
    const wavePeriod: u32 = soundBuffer.samplesPerSecond / toneHz;
    // var sampleOut: [*]i16 = @ptrCast(@alignCast(ptr));
    for (0..soundBuffer.samplesCount) |_| {
        const sineValue = math.sin(tSine);
        const sampleValue: i16 = @intFromFloat(sineValue * @as(f32, @floatFromInt(toneVolume)));

        sampleOut[0] = sampleValue;
        sampleOut += @as(usize, 1);
        sampleOut[0] = sampleValue;
        sampleOut += @as(usize, 1);

        tSine += 2.0 * math.pi * 1.0 / @as(f32, @floatFromInt(wavePeriod));
    }
}
fn RenderWeirdGradient(buffer: *game_offscreen_buffer, blueOffset: i32, greenOffset: i32) void {
    var row: [*]u8 = @ptrCast(buffer.*.memory);
    var y: u32 = 0;
    while (y < buffer.*.height) : (y += 1) {
        var x: u32 = 0;
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        while (x < buffer.*.width) : (x += 1) {
            //
            // Pixel in memory: 00 00 00 00

            const blue = x + @as(u32, @intCast(blueOffset));
            const green = y + @as(u32, @intCast(greenOffset));
            var color = (green << 8) | blue;
            pixel[0] = color;
            pixel += 1;
        }
        row += buffer.*.pitch;
    }
}
pub fn GameUpdateAndRender(buffer: *game_offscreen_buffer, blueOffset: i32, greenOffset: i32, soundbuffer: *game_sound_output_buffer, toneHz: u32) void {
    //TODO(rosh): Allow sample offsets here for more robust platform options
    GameOutputSound(soundbuffer, toneHz);
    RenderWeirdGradient(buffer, blueOffset, greenOffset);
}
