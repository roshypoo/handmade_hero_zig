pub const game_offscreen_buffer = struct {
   
    memory: ?*anyopaque = null,
    width: i32 = undefined,
    height: i32 = undefined,
    pitch: usize = undefined,
    bytesPerPixel: u8 = 4,
};

pub fn GameUpdateAndRender(buffer: *game_offscreen_buffer, blueOffset: i32, greenOffset: i32) void {
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