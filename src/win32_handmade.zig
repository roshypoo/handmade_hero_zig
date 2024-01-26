/// TODO(rosh): THIS IS NOT A FINAL PLATFORM LAYER
/// - Saved game location
/// - Getting a handle to our own executable file
/// - Asset loading
/// - Threading (launch a thread)
/// - Raw Input (support for multiple keyboard)
/// - Sleep/timeBeginPeriod
/// - ClipCursor() (for multimonitor support)
/// - Fullscreen support
/// - WM_SETCURSOR (control cursor visibility)
/// - QueryCancelAutoPlay
/// - WM_ACTIVATE_APP (for when we are not the active application)
/// - Blit speed improvements (BitBlit)
/// - Hardware acceleration (OpenGL or Direct3d or BOTH??)
/// - GetKeyboardLayout (International WASD support)
/// 
/// Just a partial list of stuff!!!

pub const UNICODE = true;

const WINAPI = @import("std").os.windows.WINAPI;
const std = @import("std");
const handmade = @import("handmade.zig");
const log = std.log.info;

// TODO(rosh): Implement sine ourselves.
const math = std.math;

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").system.iis;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").media.audio.direct_sound;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").system.performance;
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

const Win32SoundOutput = struct {
    samplesPerSecond: u32 = undefined,
    toneHz: u32 = undefined,
    toneVolume: u16 = undefined,
    runningSampleIndex: u32 = undefined,
    wavePeriod: u32 = undefined,
    bytesPerSample: u32 = undefined,
    secondaryBufferSize: u32 = undefined,
    latencySampleCount: u32 = undefined,
    tSine: f32 = undefined,

    fn create(samplesPerSecond: u32, toneHz: u32, toneVolume: u16, bytesPerSample: u32) Win32SoundOutput {
        return Win32SoundOutput{
            .samplesPerSecond = samplesPerSecond,
            .toneHz = toneHz,
            .toneVolume = toneVolume,
            .runningSampleIndex = 0,
            .wavePeriod = samplesPerSecond / toneHz,
            .bytesPerSample = bytesPerSample,
            .secondaryBufferSize = samplesPerSecond * bytesPerSample,
        };
    }
};
// TODO(rosh): These are global for now.
var running: bool = undefined;
var globalBackbuffer: Win32OffScreenBuffer = .{};
var globalSoundSecondaryBuffer: *win32.IDirectSoundBuffer = undefined;

var XinputGetState: *const fn (u32, ?*win32.XINPUT_STATE) callconv(WINAPI) isize = XinputGetState_;
fn XinputGetState_(_: u32, _: ?*win32.XINPUT_STATE) callconv((WINAPI)) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}
var XinputSetState: *const fn (u32, ?*win32.XINPUT_VIBRATION) callconv(WINAPI) isize = XinputSetState_;
fn XinputSetState_(_: u32, _: ?*win32.XINPUT_VIBRATION) callconv((WINAPI)) isize {
    return @intFromEnum(win32.ERROR_DEVICE_NOT_CONNECTED);
}

fn DirectSoundCreate_() win32.HRESULT {
    return @as(win32.HRESULT, -1);
}

fn Win32InitDirectSound(windowHandle: ?HWND, bufferSize: u32, samplesPerSecond: u32) void {
    var DirectSoundCreate: *const fn (
        pcGuidDevice: ?*const win32.Guid,
        ppDS: ?*?*win32.IDirectSound,
        pUnkOuter: ?*win32.IUnknown,
    ) callconv(WINAPI) i32 = undefined;

    if (win32.LoadLibraryA("dsound.dll")) |DSoundLibrary| {
        if (win32.GetProcAddress(DSoundLibrary, "DirectSoundCreate")) |fun| {
            DirectSoundCreate = @ptrCast(fun);
        }
        var ds: ?*win32.IDirectSound = undefined;

        if (win32.SUCCEEDED(DirectSoundCreate(null, &ds, null))) {
            if (ds) |directSound| {
                const GUID_NULL = win32.Guid.initString("00000000-0000-0000-0000-000000000000");
                var waveFormat: win32.WAVEFORMATEX = .{
                    .wFormatTag = win32.WAVE_FORMAT_PCM,
                    .nChannels = 2,
                    .nSamplesPerSec = samplesPerSecond,
                    .nAvgBytesPerSec = undefined,
                    .nBlockAlign = undefined,
                    .wBitsPerSample = 16,
                    .cbSize = 0,
                };
                waveFormat.nBlockAlign = (waveFormat.nChannels * waveFormat.wBitsPerSample) / 8;
                waveFormat.nAvgBytesPerSec = waveFormat.nSamplesPerSec * waveFormat.nBlockAlign;
                if (win32.SUCCEEDED(directSound.vtable.SetCooperativeLevel(directSound, windowHandle, win32.DSSCL_PRIORITY))) {
                    var bufferDescription: win32.DSBUFFERDESC = .{
                        .dwSize = @sizeOf(win32.DSBUFFERDESC),
                        .dwFlags = win32.DSBCAPS_PRIMARYBUFFER,
                        .dwBufferBytes = 0,
                        .dwReserved = 0,
                        .lpwfxFormat = null,
                        .guid3DAlgorithm = GUID_NULL,
                    };
                    var pb: ?*win32.IDirectSoundBuffer = undefined;

                    if (win32.SUCCEEDED(directSound.vtable.CreateSoundBuffer(
                        directSound,
                        &bufferDescription,
                        &pb,
                        null,
                    ))) {
                        if (pb) |primaryBuffer| {
                            if (win32.SUCCEEDED(
                                primaryBuffer.vtable.SetFormat(primaryBuffer, &waveFormat),
                            )) {
                                win32.OutputDebugStringA("Primary buffer format was set");
                                //NOTE(rosh): We have finally set the format!!
                            } else {
                                //TODO(rosh): Diagnostic
                            }
                        }
                    }
                } else {
                    //TODO(rosh): Diagnostic
                }
                var bufferDescription: win32.DSBUFFERDESC = .{
                    .dwSize = @sizeOf(win32.DSBUFFERDESC),
                    .dwFlags = 0,
                    .dwBufferBytes = bufferSize,
                    .dwReserved = 0,
                    .lpwfxFormat = &waveFormat,
                    .guid3DAlgorithm = GUID_NULL,
                };
                var secondaryBuffer: ?*win32.IDirectSoundBuffer = undefined;
                if (win32.SUCCEEDED(directSound.vtable.CreateSoundBuffer(directSound, &bufferDescription, &secondaryBuffer, null))) {
                    if (secondaryBuffer) |sb| {
                        globalSoundSecondaryBuffer = sb;
                    }
                    win32.OutputDebugStringA("secondary buffer created successfully");
                }
            }
        } else {
            //TODO(rosh): Diagnostic
        }
    } else {
        //TODO(rosh): Diagnostic
    }
}

fn Win32LoadXinput() void {
    if (win32.LoadLibraryA("xinput1_4.dll")) |XinputLibrary| {
        if (win32.GetProcAddress(XinputLibrary, "XInputGetState")) |fun| {
            XinputGetState = @ptrCast(fun);
        }
        if (win32.GetProcAddress(XinputLibrary, "XInputSetState")) |fun| {
            XinputSetState = @ptrCast(fun);
        }
    } else {
        //TODO(rosh): Diagnostic
    }
}

fn Win32FillSoundBuffer(soundOutput: *Win32SoundOutput, bytesToLock: u32, bytesToWrite: u32) void {
    var region1: ?*anyopaque = undefined;
    var region1Size: u32 = undefined;
    var region2: ?*anyopaque = undefined;
    var region2Size: u32 = undefined;

    if (win32.SUCCEEDED(globalSoundSecondaryBuffer.*.vtable.Lock(
        globalSoundSecondaryBuffer,
        bytesToLock,
        bytesToWrite,
        &region1,
        &region1Size,
        &region2,
        &region2Size,
        0,
    ))) {
        //TODO(rosh): Assert that region1Size/region2Size is valid
        if (region1) |ptr| {
            var sampleOut: [*]i16 = @ptrCast(@alignCast(ptr));
            const region1SampleCount = region1Size / soundOutput.bytesPerSample;
            for (0..region1SampleCount) |_| {
                const sineValue = math.sin(soundOutput.tSine);
                const sampleValue: i16 = @intFromFloat(sineValue * @as(f32, @floatFromInt(soundOutput.toneVolume)));

                sampleOut[0] = sampleValue;
                sampleOut += @as(usize, 1);
                sampleOut[0] = sampleValue;
                sampleOut += @as(usize, 1);
                soundOutput.runningSampleIndex += 1;
                soundOutput.tSine += 2.0 * math.pi * 1.0 / @as(f32, @floatFromInt(soundOutput.wavePeriod));
            }
        }
        if (region2) |ptr| {
            const region2SampleCount = region2Size / soundOutput.bytesPerSample;
            var sampleOut: [*]i16 = @ptrCast(@alignCast(ptr));
            for (0..region2SampleCount) |_| {
                const sineValue = math.sin(soundOutput.tSine);
                const sampleValue: i16 = @intFromFloat(sineValue * @as(f32, @floatFromInt(soundOutput.toneVolume)));
                sampleOut[0] = sampleValue;
                sampleOut += @as(usize, 1);
                sampleOut[0] = sampleValue;
                sampleOut += @as(usize, 1);
                soundOutput.runningSampleIndex += 1;
                soundOutput.tSine += 2.0 * math.pi * 1.0 / @as(f32, @floatFromInt(soundOutput.wavePeriod));
            }
        }
    }
}

pub export fn wWinMain(hInstance: HINSTANCE, _: ?HINSTANCE, _: [*:0]u16, _: u32) callconv(WINAPI) c_int {
    
    var perfCountFrequencyResult: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&perfCountFrequencyResult);
    const perfCountFrequency = perfCountFrequencyResult.QuadPart;


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
            // NOTE(rosh): Graphics test
            var xOffset: i32 = 0;
            var yOffset: i32 = 0;

            // NOTE(rosh): Sound test
            var soundOutput = Win32SoundOutput{};
            soundOutput.samplesPerSecond = 48000;
            soundOutput.toneHz = 256;
            soundOutput.toneVolume = 1000;
            soundOutput.runningSampleIndex = 0;
            soundOutput.wavePeriod = soundOutput.samplesPerSecond / soundOutput.toneHz;
            soundOutput.bytesPerSample = @sizeOf(u16) * 2;
            soundOutput.secondaryBufferSize = soundOutput.samplesPerSecond * soundOutput.bytesPerSample;
            soundOutput.latencySampleCount = soundOutput.samplesPerSecond / 15;


            Win32InitDirectSound(
                windowHandle,
                soundOutput.secondaryBufferSize,
                soundOutput.samplesPerSecond,
            );
            Win32FillSoundBuffer(
                &soundOutput,
                0,
                soundOutput.latencySampleCount * soundOutput.bytesPerSample,
            );
            _ = globalSoundSecondaryBuffer.vtable.Play(globalSoundSecondaryBuffer, 0, 0, win32.DSBPLAY_LOOPING);

             var lastCounter: win32.LARGE_INTEGER = undefined;
            _ = win32.QueryPerformanceCounter(&lastCounter);
            var lastCycleCount: u64 = rdtsc();
            
            running = true;
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
                        const up: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) != 0;
                        const down: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) != 0;
                        const left: bool = (pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) != 0;
                        const right: bool = pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT != 0;
                        const start: bool = pad.wButtons & win32.XINPUT_GAMEPAD_START != 0;
                        const back: bool = pad.wButtons & win32.XINPUT_GAMEPAD_BACK != 0;
                        const leftShoulder: bool = pad.*.wButtons & win32.XINPUT_GAMEPAD_LEFT_SHOULDER != 0;
                        const rightShoulder: bool = pad.wButtons & win32.XINPUT_GAMEPAD_RIGHT_SHOULDER != 0;
                        const a: bool = pad.wButtons & win32.XINPUT_GAMEPAD_A != 0;
                        const b: bool = pad.wButtons & win32.XINPUT_GAMEPAD_B != 0;
                        const x: bool = pad.wButtons & win32.XINPUT_GAMEPAD_X != 0;
                        const y: bool = pad.wButtons & win32.XINPUT_GAMEPAD_Y != 0;

                        const stickX = pad.sThumbLX;
                        const stickY = pad.sThumbLY;
                        //TODO(rosh): Need to handle joystick deadzone.
                        xOffset += @divTrunc(stickX, 4096);
                        yOffset += @divTrunc(stickY, 4096);

                        // soundOutput.toneHz = 512 * 256 * @as(u32, @intCast(@divTrunc(stickY, 32000)));
                        // soundOutput.wavePeriod = soundOutput.samplesPerSecond / soundOutput.toneHz;
                        _ = [_]bool{ up, down, left, right, start, back, leftShoulder, rightShoulder, a, b, x, y };
                    }
                }

                var gameOffscreenBuffer = handmade.game_offscreen_buffer{
                    .memory = globalBackbuffer.memory,
                    .bytesPerPixel = globalBackbuffer.bytesPerPixel,
                    .height = globalBackbuffer.height,
                    .width = globalBackbuffer.width,
                    .pitch = globalBackbuffer.pitch
                };
               
                handmade.GameUpdateAndRender(&gameOffscreenBuffer,xOffset, yOffset);

                // TODO(rosh): DirectSound output test
                var playCursor: u32 = undefined;
                var writeCursor: u32 = undefined;
                if (win32.SUCCEEDED(globalSoundSecondaryBuffer.vtable.GetCurrentPosition(globalSoundSecondaryBuffer, &playCursor, &writeCursor))) {
                    const byteToLock: u32 = (soundOutput.runningSampleIndex * soundOutput.bytesPerSample) % soundOutput.secondaryBufferSize;

                    var targetCursor = (playCursor + (soundOutput.latencySampleCount * soundOutput.bytesPerSample)) % soundOutput.secondaryBufferSize;
                    var bytesToWrite: u32 = undefined;
                    if (byteToLock > targetCursor) {
                        bytesToWrite = soundOutput.secondaryBufferSize - byteToLock;
                        bytesToWrite += targetCursor;
                    } else {
                        bytesToWrite = targetCursor - byteToLock;
                    }

                    Win32FillSoundBuffer(&soundOutput, byteToLock, bytesToWrite);
                }

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

                const endCycleCount = rdtsc();

                var endCounter: win32.LARGE_INTEGER = undefined;
                _ = win32.QueryPerformanceCounter(&endCounter);
                
                // TODO(rosh): Display the value here
                const cyclesElapsed: u64 = endCycleCount - lastCycleCount;
                const counterElapsed: f64 = @floatFromInt(endCounter.QuadPart - lastCounter.QuadPart);
                const msPerFrame: f32 = @floatCast((1000 * counterElapsed) / @as(f64, @floatFromInt(perfCountFrequency)));
                const fps: f32 = @floatCast(@as(f64, @floatFromInt(perfCountFrequency)) / counterElapsed);
                const mcpf: f32 = @floatCast(@as(f64, @floatFromInt(cyclesElapsed)) / (1000 * 1000));

                std.debug.print("{d}ms/f, {d}fps, {d}mc/f\n", .{msPerFrame, fps, mcpf});
                lastCounter = endCounter;
                lastCycleCount = endCycleCount;
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
                    @intFromEnum(win32.VK_F4) => {
                        const isAltKeyDown = lParam & (1 << 29) != 0;
                        if (isAltKeyDown) {
                            running = false;
                        }
                    },
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
            result = win32.DefWindowProcA(windowHandle, message, wParam, lParam);
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

fn ProcessWindowsError() void {
    var errorMessage = win32.GetLastError();
    std.debug.print("{}", .{errorMessage});
}


fn rdtsc() u64 {
   var low: u64 = undefined;
    var high: u64 = undefined;

    asm volatile(
        "rdtsc"
        : [low] "={eax}" (low),
        [high] "={edx}" (high)        
    );

    return (high << 32) | low;
}
