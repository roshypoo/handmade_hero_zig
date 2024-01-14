pub const UNICODE = true;

const WINAPI = @import("std").os.windows.WINAPI;
const std = @import("std");
const log = std.log.info;

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
};
const L = win32.L;
const HINSTANCE = win32.HINSTANCE;
const HWND = win32.HWND;
const HDC = win32.HDC;

const Win32OffScreenBuffer = struct {
    info: win32.BITMAPINFO = undefined,
    memory: ?*anyopaque = null,
    width: i32 = undefined,
    height: i32 = undefined,
    pitch: usize = undefined,
    bytesPerPixel: u8 = 4,
};

const Win32WindowDimension = struct {
    width: i32,
    height: i32,

    pub fn get(windowHandle: ?HWND) Win32WindowDimension {
        std.debug.assert(windowHandle != null);

        var clientRect: win32.RECT = win32.RECT{ .bottom = 0, .left = 0, .right = 0, .top = 0 };
        _ = win32.GetClientRect(windowHandle, &clientRect);
        var width = clientRect.right - clientRect.left;
        var height = clientRect.bottom - clientRect.top;
        return Win32WindowDimension{ .width = width, .height = height };
    }
};
// TODO(rosh): These are global for now.
var running: bool = undefined;
var globalBackbuffer: Win32OffScreenBuffer = .{};

var XinputGetState: *const fn (u32, ?*win32.XINPUT_STATE) callconv(WINAPI) isize = undefined;
var XinputSetState: *const fn (u32, ?*win32.XINPUT_VIBRATION) callconv(WINAPI) isize = undefined;
fn Win32LoadXinput() void {
    if (win32.LoadLibraryA("xinput1_4.dll")) |XinputLibrary| {
        if (win32.GetProcAddress(XinputLibrary, "XInputGetState")) |fun| {
            XinputGetState = @ptrCast(fun);
        }
        if (win32.GetProcAddress(XinputLibrary, "XInputSetState")) |fun| {
            XinputSetState = @ptrCast(fun);
        }
    }
}

pub export fn wWinMain(hInstance: HINSTANCE, _: ?HINSTANCE, _: [*:0]u16, _: u32) callconv(WINAPI) c_int {
    Win32LoadXinput();
    Win32ResizeDIBSection(&globalBackbuffer, 1200, 720);
    const WindowClass = win32.WNDCLASS{
        .style = win32.WNDCLASS_STYLES.initFlags(.{
            .HREDRAW = 1,
            .VREDRAW = 1,
        }),
        .lpfnWndProc = WindowProc,
        .cbClsExtra = 0,
        .cbWndExtra = 0,
        .hInstance = hInstance,
        .hIcon = null,
        .hCursor = null,
        .hbrBackground = null,
        .lpszMenuName = null,
        .lpszClassName = win32.L("HandmadeHeroWindowClass"),
    };

    if (win32.RegisterClass(&WindowClass) > 0) {
        const windowHandle = win32.CreateWindowEx(
            win32.WINDOW_EX_STYLE.initFlags(.{}),
            WindowClass.lpszClassName,
            win32.L("Handmade Hero"),
            win32.WINDOW_STYLE.initFlags(.{
                .OVERLAPPED = 1,
                .VISIBLE = 1,
                .SYSMENU = 1,
                .THICKFRAME = 1,
            }),
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            win32.CW_USEDEFAULT,
            null,
            null,
            hInstance,
            null,
        );

        if (windowHandle != null) {
            running = true;
            var xOffset: i32 = 0;
            var yOffset: i32 = 0;
            while (running) {
                var message: win32.MSG = undefined;
                while (win32.PeekMessage(
                    &message,
                    null,
                    0,
                    0,
                    win32.PEEK_MESSAGE_REMOVE_TYPE.initFlags(.{ .REMOVE = 1 }),
                ) > 0) {
                    if (message.message == win32.WM_QUIT) {
                        running = false;
                    }
                    _ = win32.TranslateMessage(&message);
                    _ = win32.DispatchMessage(&message);
                }

                var controllerIndex: u32 = 0;
                while (controllerIndex < win32.XUSER_MAX_COUNT) : (controllerIndex += 1) {
                    var controllerState: win32.XINPUT_STATE = undefined;
                    if (XinputGetState(controllerIndex, &controllerState) == @intFromEnum(win32.WIN32_ERROR.NO_ERROR)) {
                        // NOTE(rosh): The controller is plugged in.
                        // TODO(rosh): see if controllerState.dwPacketNumber increments too rapidly.
                        const pad: *win32.XINPUT_GAMEPAD = &controllerState.Gamepad;
                        const up: bool = (pad.*.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) != 0;
                        const down: bool = (pad.*.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) != 0;
                        const left: bool = (pad.*.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) != 0;
                        const right: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT != 0;
                        const start: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_START != 0;
                        const back: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_BACK != 0;
                        const leftShoulder: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_LEFT_SHOULDER != 0;
                        const rightShoulder: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_RIGHT_SHOULDER != 0;
                        const a: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_A != 0;
                        const b: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_B != 0;
                        const x: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_X != 0;
                        const y: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_Y != 0;

                        const stickX: i16 = pad.*.sThumbLX;
                        const stickY: i16 = pad.*.sThumbLY;
                        xOffset += @intCast(stickX >> 12);
                        yOffset += @intCast(stickY >> 12);
                        _ = [_]bool{ up, down, left, right, start, back, leftShoulder, rightShoulder, a, b, x, y };
                    }
                }
                RenderWeirdGradient(globalBackbuffer, xOffset, yOffset);

                var deviceContext = win32.GetDC(windowHandle);
                defer _ = win32.ReleaseDC(windowHandle, deviceContext);

                const windowDimension = Win32WindowDimension.get(windowHandle);
                if (deviceContext) |context| {
                    Win32CopyBufferToWindow(
                        &globalBackbuffer,
                        context,
                        windowDimension.width,
                        windowDimension.height,
                    );
                }
                xOffset += 1;
            }
        } else {
            ProcessWindowsError();
            // TODO(rosh): Logging
        }
    } else {
        ProcessWindowsError();
        // TODO(rosh): Logging
    }
    return 0;
}

fn WindowProc(
    windowHandle: HWND,
    message: u32,
    wParam: win32.WPARAM,
    lParam: win32.LPARAM,
) callconv(WINAPI) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {
            win32.OutputDebugStringA("WM_SIZE\n");
        },
        win32.WM_DESTROY => {
            // TODO(rosh): Handle this message to the user?
            running = false;
        },
        win32.WM_CLOSE => {
            // TODO(rosh): Handle this as an error - recreate window?
            running = false;
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATE_APP\n");
        },
        win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYUP, win32.WM_KEYDOWN => {
            const vKCode: u32 = @intCast(wParam);
            const wasDown: bool = (lParam & (1 << 30) != 0);
            const isDown: bool = (lParam & (1 << 31) == 0);
            if (wasDown != isDown) {
                switch (vKCode) {
                    'W' => {},
                    'A' => {},
                    'S' => {},
                    'D' => {},
                    'Q' => {},
                    'E' => {},
                    @intFromEnum(win32.VK_UP) => {},
                    @intFromEnum(win32.VK_LEFT) => {},
                    @intFromEnum(win32.VK_DOWN) => {},
                    @intFromEnum(win32.VK_RIGHT) => {},
                    @intFromEnum(win32.VK_ESCAPE) => {
                        win32.OutputDebugStringA("Escape Key: ");
                        if (isDown) {
                            win32.OutputDebugStringA("isDown\n");
                        }
                        if (wasDown) {
                            win32.OutputDebugStringA("wasDown\n");
                        }
                    },
                    @intFromEnum(win32.VK_SPACE) => {},
                    else => {},
                }
            }
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            var deviceContext = win32.BeginPaint(windowHandle, &paint);

            var windowDimension = Win32WindowDimension.get(windowHandle);
            if (deviceContext) |context| {
                Win32CopyBufferToWindow(
                    &globalBackbuffer,
                    context,
                    windowDimension.width,
                    windowDimension.height,
                );
            }
            _ = win32.EndPaint(windowHandle, &paint);
        },
        else => {
            result = win32.DefWindowProc(windowHandle, message, wParam, lParam);
        },
    }

    return result;
}

fn Win32CopyBufferToWindow(
    buffer: *Win32OffScreenBuffer,
    deviceContext: HDC,
    windowWidth: i32,
    windowHeight: i32,
) void {
    // TODO(rosh): Fix aspect ratio
    _ = win32.StretchDIBits(
        deviceContext,
        0,
        0,
        windowWidth,
        windowHeight,
        0,
        0,
        buffer.*.width,
        buffer.*.height,
        buffer.*.memory,
        &buffer.*.info,
        win32.DIB_USAGE.RGB_COLORS,
        win32.ROP_CODE.SRCCOPY,
    );
}

fn Win32ResizeDIBSection(buffer: *Win32OffScreenBuffer, width: i32, height: i32) void {

    //TODO(rosh): Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.

    if (buffer.*.memory != null) {
        _ = win32.VirtualFree(
            buffer.*.memory,
            0,
            win32.VIRTUAL_FREE_TYPE.RELEASE,
        );
    }

    buffer.*.width = width;
    buffer.*.height = height;

    buffer.*.info = win32.BITMAPINFO{ .bmiHeader = win32.BITMAPINFOHEADER{
        .biSize = @sizeOf(win32.BITMAPINFOHEADER),
        .biWidth = buffer.*.width,
        .biHeight = -buffer.*.height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    }, .bmiColors = [1]win32.RGBQUAD{win32.RGBQUAD{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }} };

    var bitmapMemorySize: usize = @as(usize, @intCast((buffer.*.width * buffer.*.height) * buffer.*.bytesPerPixel));

    buffer.*.memory = win32.VirtualAlloc(
        null,
        bitmapMemorySize,
        win32.VIRTUAL_ALLOCATION_TYPE.COMMIT,
        win32.PAGE_PROTECTION_FLAGS.PAGE_READWRITE,
    );
    buffer.*.pitch = @intCast((buffer.*.bytesPerPixel * width));
}

fn RenderWeirdGradient(buffer: Win32OffScreenBuffer, blueOffset: i32, greenOffset: i32) void {
    var row: [*]u8 = @ptrCast(buffer.memory);
    var y: u32 = 0;
    while (y < buffer.height) : (y += 1) {
        var x: u32 = 0;
        var pixel: [*]u32 = @ptrCast(@alignCast(row));
        while (x < buffer.width) : (x += 1) {
            //
            // Pixel in memory: 00 00 00 00

            const blue = x + @as(u32, @intCast(blueOffset));
            const green = y + @as(u32, @intCast(greenOffset));
            var color = (green << 8) | blue;
            pixel[0] = color;
            pixel += 1;
        }
        row += buffer.pitch;
    }
}

fn ProcessWindowsError() void {
    var errorMessage = win32.GetLastError();
    std.debug.print("{}", .{errorMessage});
}
