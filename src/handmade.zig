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
const HANDMADE_INTERNAL = (@import("builtin").mode == std.builtin.Mode.Debug);

/// IMPORTANT(rosh):
/// They are NOT for doing anything in the shipping game - they are
/// blocking and the write doesn't protect against lost data!
pub const platform = struct {
    DEBUGPlatformReadEntireFile: fn ([*:0]const u8) debug_read_file_result = undefined,
    DEBUGPlatformFreeFileMemory: fn (*anyopaque) void = undefined,
    DEBUGPlatformWriteEntireFile: fn ([*:0]const u8, u32, *anyopaque) bool = undefined,
};

pub const debug_read_file_result = struct { contents: ?*anyopaque = undefined, contentSize: u32 = 0 };

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

pub const game_button_state = packed struct {
    halfTransitionCount: u32 = 0,
    endedDown: u32 = 0,
};
pub const game_controller_input = struct {
    isAnalog: bool = false,
    isConnected: bool = false,
    stickAverageX: f32 = 0,
    stickAverageY: f32 = 0,

    buttons: packed struct {
        moveUp: game_button_state,
        moveDown: game_button_state,
        moveLeft: game_button_state,
        moveRight: game_button_state,
        actionUp: game_button_state,
        actionDown: game_button_state,
        actionLeft: game_button_state,
        actionRight: game_button_state,
        leftShoulder: game_button_state,
        rightShoulder: game_button_state,
        back: game_button_state,
        start: game_button_state,
    },

    pub fn Get(self: *game_controller_input, index: u8) *game_button_state {
        return switch (index) {
            0 => &self.buttons.moveUp,
            1 => &self.buttons.moveDown,
            2 => &self.buttons.moveLeft,
            3 => &self.buttons.moveRight,
            4 => &self.buttons.actionUp,
            5 => &self.buttons.actionDown,
            6 => &self.buttons.actionLeft,
            7 => &self.buttons.actionRight,
            8 => &self.buttons.leftShoulder,
            9 => &self.buttons.rightShoulder,
            10 => &self.buttons.back,
            11 => &self.buttons.start,
            else => unreachable,
        };
    }
};
pub const game_input = struct {
    controllers: [5]game_controller_input,
};

pub const game_memory = struct {
    isInitialized: bool = false,
    permanentStorageSize: u64,
    permanentStorage: [*]u8, //NOTE(rosh): REQUIRED to be cleared to zero.
    transientStorageSize: u64,
    transientStorage: [*]u8, //NOTE(rosh): REQUIRED to be cleared to zero.
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

        tSine += (2.0 * math.pi * 1.0) / @as(f32, @floatFromInt(wavePeriod));
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
            const color = (green << 8) | blue;
            pixel[0] = color;
            pixel += 1;
        }
        row += buffer.*.pitch;
    }
}

const game_state = struct {
    blueOffset: i32 = undefined,
    greenOffset: i32 = undefined,
    toneHz: u32 = undefined,
};

pub fn GameUpdateAndRender(callbacks: *const platform, memory: *game_memory, buffer: *game_offscreen_buffer, soundbuffer: *game_sound_output_buffer, input: *game_input) void {
    std.debug.assert(@sizeOf(game_state) <= memory.permanentStorageSize);

    var gameState: *game_state = @ptrCast(@alignCast(memory));
    if (!memory.isInitialized) {
        const fileName = "src/handmade.zig";
        const file = callbacks.DEBUGPlatformReadEntireFile(fileName);
        if (file.contents) |content| {
            if (callbacks.DEBUGPlatformWriteEntireFile(
                "data/test.out",
                file.contentSize,
                content,
            )) {
                std.debug.print("File written successfully to {any}", .{"data/test.out"});
                callbacks.DEBUGPlatformFreeFileMemory(content);
            } else {
                std.debug.print("File write operation failed to {s}", .{"data/test.out"});
            }
        }

        gameState.toneHz = 256;
        memory.isInitialized = true;
    }

    for (input.controllers) |controller| {
        if (controller.isAnalog) {
            //NOTE(rosh): Use analog movement tuning
            gameState.blueOffset += @intFromFloat(4.0 * controller.stickAverageX);
            // gameState.toneHz += 256 + @as(u32, @intFromFloat(120.0 * controller.stickAverageY));
        } else {
            if (controller.buttons.moveLeft.endedDown != 0) {
                gameState.blueOffset -= 1;
            } else if (controller.buttons.moveRight.endedDown != 0) {
                gameState.blueOffset += 1;
            }
            //NOTE(rosh): Use digital movement tuning
        }

        if (controller.buttons.actionDown.endedDown != 0) {
            gameState.greenOffset += 1;
        }
    }

    //TODO(rosh): Allow sample offsets here for more robust platform options
    GameOutputSound(soundbuffer, gameState.toneHz);
    RenderWeirdGradient(buffer, gameState.blueOffset, gameState.greenOffset);
}

pub inline fn Terabytes(value: u64) u64 {
    return 1024 * Gigabytes(value);
}
pub inline fn Gigabytes(value: u64) u64 {
    return 1024 * Megabytes(value);
}
pub inline fn Megabytes(value: u64) u64 {
    return 1024 * Kilobytes(value);
}
pub inline fn Kilobytes(value: u64) u64 {
    return 1024 * value;
}
