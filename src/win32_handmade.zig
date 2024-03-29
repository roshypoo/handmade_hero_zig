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

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").system.library_loader;
    usingnamespace @import("win32").system.com;
    usingnamespace @import("win32").system.iis;
    usingnamespace @import("win32").storage.file_system;
    usingnamespace @import("win32").graphics.gdi;
    usingnamespace @import("win32").system.memory;
    usingnamespace @import("win32").ui.input.xbox_controller;
    usingnamespace @import("win32").ui.input.keyboard_and_mouse;
    usingnamespace @import("win32").media.audio.direct_sound;
    usingnamespace @import("win32").media.audio;
    usingnamespace @import("win32").system.performance;
    usingnamespace @import("win32").media;
    usingnamespace @import("win32").system.threading;
};
const IGNORE = @import("build_consts").IGNORE;
const HANDMADE_INTERNAL = (@import("builtin").mode == std.builtin.Mode.Debug);
const L = win32.L;
const HINSTANCE = win32.HINSTANCE;
const HANDLE = win32.HANDLE;
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
        const width = clientRect.right - clientRect.left;
        const height = clientRect.bottom - clientRect.top;
        return Win32WindowDimension{ .width = width, .height = height };
    }
};

const Win32SoundOutput = struct {
    samplesPerSecond: u32 = undefined,
    runningSampleIndex: u32 = undefined,
    bytesPerSample: u32 = undefined,
    secondaryBufferSize: u32 = undefined,
    latencySampleCount: u32 = undefined,
    tSine: f32 = undefined,

    fn create(samplesPerSecond: u32, bytesPerSample: u32) Win32SoundOutput {
        return Win32SoundOutput{
            .samplesPerSecond = samplesPerSecond,
            .runningSampleIndex = 0,
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
                    } else {
                        //TODO(rosh): Diagnostic
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
                        win32.OutputDebugStringA("secondary buffer created successfully");
                    }
                }
            }
        } else {
            //TODO(rosh): Diagnostic
        }
    } else {
        //TODO(rosh): Diagnostic
    }
}

const win32Platform = handmade.platform{ .DEBUGPlatformFreeFileMemory = DEBUGPlatformFreeFileMemory, .DEBUGPlatformReadEntireFile = DEBUGPlatformReadEntireFile, .DEBUGPlatformWriteEntireFile = DEBUGPlatformWriteEntireFile };

fn DEBUGPlatformWriteEntireFile(fileName: [*:0]const u8, fileSize: u32, memory: *anyopaque) bool {
    const handle: HANDLE = win32.CreateFileA(
        fileName,
        win32.FILE_GENERIC_WRITE,
        win32.FILE_SHARE_MODE{},
        null,
        win32.FILE_CREATION_DISPOSITION.CREATE_ALWAYS,
        win32.FILE_FLAGS_AND_ATTRIBUTES{},
        null,
    );
    var result: bool = false;
    if (handle != win32.INVALID_HANDLE_VALUE) {
        defer _ = win32.CloseHandle(handle);
        var bytesWritten: u32 = 0;
        if ((win32.WriteFile(
            handle,
            memory,
            fileSize,
            &bytesWritten,
            null,
        ) != 0)) {
            result = bytesWritten == fileSize;
        } else {
            //TODO(rosh): Logging
        }
    } else {
        const winError = win32.GetLastError();
        std.debug.print("File write op failed {}", .{winError});
    }
    return result;
}

fn DEBUGPlatformReadEntireFile(fileName: [*:0]const u8) handmade.debug_read_file_result {
    var result = handmade.debug_read_file_result{};
    const handle: HANDLE = win32.CreateFileA(
        fileName,
        win32.FILE_GENERIC_READ,
        win32.FILE_SHARE_MODE{ .READ = 1 },
        null,
        win32.FILE_CREATION_DISPOSITION.OPEN_EXISTING,
        win32.FILE_FLAGS_AND_ATTRIBUTES{},
        null,
    );
    if (handle != win32.INVALID_HANDLE_VALUE) {
        defer _ = win32.CloseHandle(handle);

        var fileSize: win32.LARGE_INTEGER = undefined;
        if (win32.GetFileSizeEx(handle, &fileSize) != 0) {
            if (win32.VirtualAlloc(
                null,
                @intCast(fileSize.QuadPart),
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            )) |data| {
                const fileSize32: u32 = @truncate(@as(u64, @bitCast(fileSize.QuadPart)));
                var bytesToRead: u32 = 0;
                result.contents = data;
                if ((win32.ReadFile(
                    handle,
                    result.contents,
                    fileSize32,
                    &bytesToRead,
                    null,
                ) != 0) and fileSize32 == bytesToRead) {
                    result.contentSize = fileSize32;
                    //NOTE(rosh): File read successfully
                } else {
                    //TODO(rosh): Logging
                    DEBUGPlatformFreeFileMemory(result.contents);
                    result.contentSize = 0;
                    result.contents = null;
                }
            } else {
                //TODO(rosh): Logging
            }
        } else {
            //TODO(rosh): Logging
        }
    } else {
        const winError = win32.GetLastError();
        std.debug.print("File doesn't exist {}", .{winError});
        //TODO(rosh): Logging
    }
    return result;
}

fn DEBUGPlatformFreeFileMemory(memory: ?*anyopaque) void {
    if (memory != null) {
        _ = win32.VirtualFree(memory, 0, win32.VIRTUAL_FREE_TYPE.RELEASE);
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

fn Win32ClearBuffer(soundOutput: *Win32SoundOutput) void {
    var region1: ?*anyopaque = undefined;
    var region1Size: u32 = undefined;
    var region2: ?*anyopaque = undefined;
    var region2Size: u32 = undefined;
    if (win32.SUCCEEDED(globalSoundSecondaryBuffer.*.vtable.Lock(
        globalSoundSecondaryBuffer,
        0,
        soundOutput.secondaryBufferSize,
        &region1,
        &region1Size,
        &region2,
        &region2Size,
        0,
    ))) {
        if (region1) |ptr| {
            var destSample: [*]i16 = @ptrCast(@alignCast(ptr));
            var byteIndex: u32 = undefined;
            while (byteIndex < region1Size) : (byteIndex += 1) {
                destSample[0] = 0;
                destSample += @as(usize, 1);
            }
        }
        if (region2) |ptr| {
            var destSample: [*]i16 = @ptrCast(@alignCast(ptr));
            var byteIndex: u32 = undefined;
            while (byteIndex < region2Size) : (byteIndex += 1) {
                destSample[0] = 0;
                destSample += @as(usize, 1);
            }
        }
        _ = globalSoundSecondaryBuffer.vtable.Unlock(
            globalSoundSecondaryBuffer,
            region1,
            region1Size,
            region2,
            region2Size,
        );
    }
}

fn Win32FillSoundBuffer(
    soundOutput: *Win32SoundOutput,
    bytesToLock: u32,
    bytesToWrite: u32,
    sourceBuffer: *handmade.game_sound_output_buffer,
) void {
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
            var destSample: [*]i16 = @ptrCast(@alignCast(ptr));
            var sourceSample = sourceBuffer.samples;
            const region1SampleCount = region1Size / soundOutput.bytesPerSample;
            for (0..region1SampleCount) |_| {
                destSample[0] = sourceSample[0];
                destSample += @as(usize, 1);
                sourceSample += @as(usize, 1);
                destSample[0] = sourceSample[0];
                destSample += @as(usize, 1);
                sourceSample += @as(usize, 1);
                soundOutput.runningSampleIndex += 1;
            }
        }
        if (region2) |ptr| {
            var destSample: [*]i16 = @ptrCast(@alignCast(ptr));
            var sourceSample = sourceBuffer.samples;
            const region2SampleCount = region2Size / soundOutput.bytesPerSample;
            for (0..region2SampleCount) |_| {
                destSample[0] = sourceSample[0];
                destSample += @as(usize, 1);
                sourceSample += @as(usize, 1);
                destSample[0] = sourceSample[0];
                destSample += @as(usize, 1);
                sourceSample += @as(usize, 1);
                soundOutput.runningSampleIndex += 1;
            }
        }
        _ = globalSoundSecondaryBuffer.vtable.Unlock(
            globalSoundSecondaryBuffer,
            region1,
            region1Size,
            region2,
            region2Size,
        );
    }
}
fn Win32ProcessXInputStickValue(value: i16, deadZoneThreshold: i16) f32 {
    var result: f32 = 0;
    if (value < -deadZoneThreshold) {
        result = @as(f32, @floatFromInt(value + deadZoneThreshold)) / (32768.0 - @as(f32, @floatFromInt(deadZoneThreshold)));
    } else if (value > deadZoneThreshold) {
        result = @as(f32, @floatFromInt(value - deadZoneThreshold)) / (32767.0 - @as(f32, @floatFromInt(deadZoneThreshold)));
    }
    return result;
}
fn Win32ProcessDigitalXinputButton(xInputButtonState: u32, newState: *handmade.game_button_state, buttonBit: u32, oldState: *handmade.game_button_state) void {
    newState.halfTransitionCount = if (oldState.endedDown != newState.endedDown) 1 else 0;
    newState.endedDown = if ((xInputButtonState & buttonBit) == buttonBit) 1 else 0;
}

fn Win32ProcessKeyboardMessage(newState: *handmade.game_button_state, isDown: u32) void {
    std.debug.assert(newState.endedDown != isDown);
    newState.halfTransitionCount += 1;
    newState.endedDown = isDown;
}

var globalPerfCountFrequency: i64 = undefined;
inline fn Win32GetWallClock() win32.LARGE_INTEGER {
    var result: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceCounter(&result);
    return result;
}
inline fn Win32GetSecondsElapsed(start: win32.LARGE_INTEGER, end: win32.LARGE_INTEGER) f32 {
    return @as(f32, @floatFromInt(end.QuadPart - start.QuadPart)) / @as(f32, @floatFromInt(globalPerfCountFrequency));
}
pub export fn wWinMain(hInstance: HINSTANCE, _: ?HINSTANCE, _: [*:0]u16, _: u32) callconv(WINAPI) c_int {
    var perfCountFrequencyResult: win32.LARGE_INTEGER = undefined;
    _ = win32.QueryPerformanceFrequency(&perfCountFrequencyResult);
    globalPerfCountFrequency = perfCountFrequencyResult.QuadPart;

    const desiredSchedulerMS: u32 = 1;
    const sleepIsGranular = win32.timeBeginPeriod(desiredSchedulerMS) == win32.TIMERR_NOERROR;
    Win32LoadXinput();
    Win32ResizeDIBSection(&globalBackbuffer, 1200, 720);
    const WindowClass = win32.WNDCLASS{
        .style = win32.WNDCLASS_STYLES{
            .HREDRAW = 1,
            .VREDRAW = 1,
            .OWNDC = 1,
        },
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
    const monitorRefreshHz = 60;
    const gameUpdateHz = monitorRefreshHz / 2;
    const targetSecondsPerFrame = 1.0 / @as(f32, @floatFromInt(gameUpdateHz));
    if (win32.RegisterClass(&WindowClass) > 0) {
        const windowHandle = win32.CreateWindowEx(
            win32.WINDOW_EX_STYLE{},
            WindowClass.lpszClassName,
            win32.L("Handmade Hero"),
            win32.WINDOW_STYLE{
                .VISIBLE = 1,
                .SYSMENU = 1,
                .THICKFRAME = 1,
            },
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

            // NOTE(rosh): Sound test
            var soundOutput = Win32SoundOutput{};
            soundOutput.samplesPerSecond = 48000;
            soundOutput.runningSampleIndex = 0;
            soundOutput.bytesPerSample = @sizeOf(u16) * 2;
            soundOutput.secondaryBufferSize = soundOutput.samplesPerSecond * soundOutput.bytesPerSample;
            soundOutput.latencySampleCount = soundOutput.samplesPerSecond / 15;

            Win32InitDirectSound(
                windowHandle,
                soundOutput.secondaryBufferSize,
                soundOutput.samplesPerSecond,
            );
            Win32ClearBuffer(
                &soundOutput,
            );
            _ = globalSoundSecondaryBuffer.vtable.Play(globalSoundSecondaryBuffer, 0, 0, win32.DSBPLAY_LOOPING);

            //TODO(rosh): Pool with bitmap virtual alloc.
            const gameMemoryStorageSize = handmade.Megabytes(64);
            const transientMemoryStorageSize = handmade.Gigabytes(4);

            //TODO(rosh): Fix this.the programming crashes when trying to pass baseAddress to virtualalloc.
            // const baseAddress: ?[*]u8 =  if (HANDMADE_INTERNAL) @ptrFromInt(handmade.Terabytes(2)) else null;
            const totalSize = gameMemoryStorageSize + transientMemoryStorageSize;

            if (@as(?[*]i16, @ptrCast(@alignCast(win32.VirtualAlloc(
                null,
                soundOutput.secondaryBufferSize,
                win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                win32.PAGE_READWRITE,
            ))))) |samples| {
                if (@as(?[*]u8, @ptrCast(@alignCast(win32.VirtualAlloc(
                    null,
                    totalSize,
                    win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
                    win32.PAGE_READWRITE,
                ))))) |memory| {
                    var gameMemory = handmade.game_memory{ .permanentStorageSize = gameMemoryStorageSize, .permanentStorage = memory, .transientStorageSize = transientMemoryStorageSize, .transientStorage = memory + gameMemoryStorageSize };

                    var input = [1]handmade.game_input{
                        handmade.game_input{
                            .controllers = [1]handmade.game_controller_input{
                                handmade.game_controller_input{
                                    .buttons = .{
                                        .actionUp = handmade.game_button_state{},
                                        .actionDown = handmade.game_button_state{},
                                        .actionLeft = handmade.game_button_state{},
                                        .actionRight = handmade.game_button_state{},
                                        .moveUp = handmade.game_button_state{},
                                        .moveDown = handmade.game_button_state{},
                                        .moveLeft = handmade.game_button_state{},
                                        .moveRight = handmade.game_button_state{},
                                        .leftShoulder = handmade.game_button_state{},
                                        .rightShoulder = handmade.game_button_state{},
                                        .start = handmade.game_button_state{},
                                        .back = handmade.game_button_state{},
                                    },
                                },
                            } ** 5,
                        },
                    } ** 2;
                    var oldInput = &input[0];
                    var newInput = &input[1];

                    var lastCounter: win32.LARGE_INTEGER = Win32GetWallClock();
                    const lastCycleCount: u64 = rdtsc();

                    running = true;
                    while (running) {
                        const oldKeyboardController: *handmade.game_controller_input = &oldInput.controllers[0];
                        const newKeyboardController: *handmade.game_controller_input = &newInput.controllers[0];

                        newKeyboardController.* = handmade.game_controller_input{ .buttons = .{
                            .actionUp = handmade.game_button_state{},
                            .actionDown = handmade.game_button_state{},
                            .actionLeft = handmade.game_button_state{},
                            .actionRight = handmade.game_button_state{},
                            .moveUp = handmade.game_button_state{},
                            .moveDown = handmade.game_button_state{},
                            .moveLeft = handmade.game_button_state{},
                            .moveRight = handmade.game_button_state{},
                            .leftShoulder = handmade.game_button_state{},
                            .rightShoulder = handmade.game_button_state{},
                            .start = handmade.game_button_state{},
                            .back = handmade.game_button_state{},
                        } };
                        newKeyboardController.isConnected = true;
                        var buttonIndex: u8 = 0;
                        while (buttonIndex < 12) : (buttonIndex += 1) {
                            newKeyboardController.Get(buttonIndex).endedDown = oldKeyboardController.Get(buttonIndex).endedDown;
                        }
                        Win32ProcessPendingMessages(newKeyboardController);

                        var controllerIndex: u32 = 0;
                        var maxControllerCount = 1 + win32.XUSER_MAX_COUNT;
                        if (maxControllerCount > input.len) {
                            maxControllerCount = input.len;
                        }
                        while (controllerIndex < win32.XUSER_MAX_COUNT) : (controllerIndex += 1) {
                            const ourControllerIndex = controllerIndex + 1;
                            const oldController = &oldInput.controllers[ourControllerIndex];
                            const newController = &newInput.controllers[ourControllerIndex];
                            var controllerState: win32.XINPUT_STATE = undefined;
                            if (XinputGetState(controllerIndex, &controllerState) == @intFromEnum(win32.WIN32_ERROR.NO_ERROR)) {
                                // NOTE(rosh): The controller is plugged in.
                                // TODO(rosh): see if controllerState.dwPacketNumber increments too rapidly.
                                const pad: *win32.XINPUT_GAMEPAD = &controllerState.Gamepad;

                                newController.isConnected = true;
                                //TODO(rosh): This is a square deadzone, check Xinput to
                                //verify that deadzone is "round" and show how to do
                                // round deadzone processing.
                                newController.stickAverageX = Win32ProcessXInputStickValue(
                                    pad.sThumbLX,
                                    win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
                                );
                                newController.stickAverageY = Win32ProcessXInputStickValue(
                                    pad.sThumbLY,
                                    win32.XINPUT_GAMEPAD_LEFT_THUMB_DEADZONE,
                                );

                                if ((newController.stickAverageX != 0) or (newController.stickAverageY != 0)) {
                                    newController.isAnalog = true;
                                }
                                if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_UP) != 0) {
                                    newController.stickAverageY = 1.0;
                                    newController.isAnalog = false;
                                }
                                if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_DOWN) != 0) {
                                    newController.stickAverageY = -1.0;
                                    newController.isAnalog = false;
                                }
                                if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_LEFT) != 0) {
                                    newController.stickAverageX = -1.0;
                                    newController.isAnalog = false;
                                }
                                if ((pad.wButtons & win32.XINPUT_GAMEPAD_DPAD_RIGHT) != 0) {
                                    newController.stickAverageX = 1.0;
                                    newController.isAnalog = false;
                                }
                                const threshold: f32 = 0.5;
                                Win32ProcessDigitalXinputButton(
                                    if (newController.stickAverageX < -threshold) 1 else 0,
                                    @ptrCast(&newController.buttons.moveLeft),
                                    1,
                                    @ptrCast(&oldController.buttons.moveLeft),
                                );

                                Win32ProcessDigitalXinputButton(
                                    if (newController.stickAverageX > threshold) 1 else 0,
                                    @ptrCast(&newController.buttons.moveRight),
                                    1,
                                    @ptrCast(&oldController.buttons.moveRight),
                                );
                                Win32ProcessDigitalXinputButton(
                                    if (newController.stickAverageY > threshold) 1 else 0,
                                    @ptrCast(&newController.buttons.moveUp),
                                    1,
                                    @ptrCast(&oldController.buttons.moveUp),
                                );
                                Win32ProcessDigitalXinputButton(
                                    if (newController.stickAverageY < -threshold) 1 else 0,
                                    @ptrCast(&newController.buttons.moveDown),
                                    1,
                                    @ptrCast(&oldController.buttons.moveDown),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.actionUp),
                                    win32.XINPUT_GAMEPAD_Y,
                                    @ptrCast(&oldController.buttons.actionUp),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.actionDown),
                                    win32.XINPUT_GAMEPAD_A,
                                    @ptrCast(&oldController.buttons.actionDown),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.actionRight),
                                    win32.XINPUT_GAMEPAD_B,
                                    @ptrCast(&oldController.buttons.actionRight),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.actionLeft),
                                    win32.XINPUT_GAMEPAD_X,
                                    @ptrCast(&oldController.buttons.actionLeft),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.leftShoulder),
                                    win32.XINPUT_GAMEPAD_LEFT_SHOULDER,
                                    @ptrCast(&oldController.buttons.leftShoulder),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.rightShoulder),
                                    win32.XINPUT_GAMEPAD_RIGHT_SHOULDER,
                                    @ptrCast(&oldController.buttons.rightShoulder),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.start),
                                    win32.XINPUT_GAMEPAD_START,
                                    @ptrCast(&oldController.buttons.start),
                                );
                                Win32ProcessDigitalXinputButton(
                                    pad.wButtons,
                                    @ptrCast(&newController.buttons.back),
                                    win32.XINPUT_GAMEPAD_BACK,
                                    @ptrCast(&oldController.buttons.back),
                                );
                            } else {
                                newController.isConnected = false;
                            }
                        }

                        // TODO(rosh): DirectSound output test
                        var byteToLock: u32 = 0;
                        var playCursor: u32 = 0;
                        var writeCursor: u32 = 0;
                        var bytesToWrite: u32 = 0;
                        var targetCursor: u32 = 0;

                        var isSouldValid: bool = false;
                        //TODO(rosh): Tighten up sound logic so that we know where we should be writing to
                        // and can anticipate the time spent in game update
                        if (win32.SUCCEEDED(globalSoundSecondaryBuffer.vtable.GetCurrentPosition(globalSoundSecondaryBuffer, &playCursor, &writeCursor))) {
                            isSouldValid = true;
                            byteToLock = (soundOutput.runningSampleIndex * soundOutput.bytesPerSample) % soundOutput.secondaryBufferSize;

                            targetCursor = (playCursor + (soundOutput.latencySampleCount * soundOutput.bytesPerSample)) % soundOutput.secondaryBufferSize;
                            if (byteToLock > targetCursor) {
                                bytesToWrite = soundOutput.secondaryBufferSize - byteToLock;
                                bytesToWrite += targetCursor;
                            } else {
                                bytesToWrite = targetCursor - byteToLock;
                            }
                        }
                        //TODO(rosh):Sound is wrong now, because we haven't updated
                        // it to go with the new frameloop.
                        var soundBuffer = handmade.game_sound_output_buffer{
                            .samplesPerSecond = soundOutput.samplesPerSecond,
                            .samplesCount = bytesToWrite / soundOutput.bytesPerSample,
                            .samples = samples,
                        };

                        var gameOffscreenBuffer = handmade.game_offscreen_buffer{
                            .memory = globalBackbuffer.memory,
                            .height = globalBackbuffer.height,
                            .width = globalBackbuffer.width,
                            .pitch = globalBackbuffer.pitch,
                        };
                        handmade.GameUpdateAndRender(&win32Platform, &gameMemory, &gameOffscreenBuffer, &soundBuffer, newInput);

                        if (isSouldValid) {
                            Win32FillSoundBuffer(
                                &soundOutput,
                                byteToLock,
                                bytesToWrite,
                                &soundBuffer,
                            );
                        }
                        const workCounter = Win32GetWallClock();
                        const workSecondsElapsed = Win32GetSecondsElapsed(lastCounter, workCounter);

                        //TODO(rosh):NOT TESTED YET!!! PROBABLY BUGGY!!!!
                        var secondsElapsedForFrame = workSecondsElapsed;
                        if (secondsElapsedForFrame < targetSecondsPerFrame) {
                            if (sleepIsGranular) {
                                const sleepMs: u32 = @intFromFloat((1000.0 * (targetSecondsPerFrame - secondsElapsedForFrame)));
                                if (sleepMs > 0) {
                                    win32.Sleep(sleepMs);
                                }
                            }
                            while (secondsElapsedForFrame < targetSecondsPerFrame) {
                                secondsElapsedForFrame = Win32GetSecondsElapsed(lastCounter, Win32GetWallClock());
                            }
                        } else {
                            //TODO(rosh): MISSED FRAME RATE!!!
                            //TODO(rosh): Logging
                        }
                        const deviceContext = win32.GetDC(windowHandle);
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

                        const temp = newInput;
                        newInput = oldInput;
                        oldInput = temp;

                        const endCounter = Win32GetWallClock();

                        const msPerFrame = 1000.0 * Win32GetSecondsElapsed(lastCounter, endCounter);
                        lastCounter = endCounter;
                        const endCycleCount = rdtsc();
                        const cyclesElapsed: u64 = endCycleCount - lastCycleCount;

                        const fps: f64 = 0.0;
                        const mcpf: f32 = @floatCast(@as(f64, @floatFromInt(cyclesElapsed)) / (1000 * 1000));

                        std.debug.print("{d}ms/f, {d}fps, {d}mc/f\n", .{ msPerFrame, fps, mcpf });
                    }
                } else {}
            } else {}
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

fn Win32ProcessPendingMessages(keyboard_controller: *handmade.game_controller_input) void {
    var message: win32.MSG = undefined;
    while (win32.PeekMessage(
        &message,
        null,
        0,
        0,
        win32.PEEK_MESSAGE_REMOVE_TYPE{ .REMOVE = 1 },
    ) > 0) {
        switch (message.message) {
            win32.WM_QUIT => {
                running = false;
            },
            win32.WM_SYSKEYDOWN, win32.WM_SYSKEYUP, win32.WM_KEYUP, win32.WM_KEYDOWN => {
                const vKCode: u32 = @intCast(message.wParam);
                const wasDown: bool = (message.lParam & (1 << 30) != 0);
                const isDown: bool = (message.lParam & (1 << 31) == 0);
                if (wasDown != isDown) {
                    switch (vKCode) {
                        'W' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.moveUp,
                                @intFromBool(isDown),
                            );
                        },
                        'A' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.moveLeft,
                                @intFromBool(isDown),
                            );
                        },
                        'S' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.moveDown,
                                @intFromBool(isDown),
                            );
                        },
                        'D' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.moveRight,
                                @intFromBool(isDown),
                            );
                        },
                        'Q' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.leftShoulder,
                                @intFromBool(isDown),
                            );
                        },
                        'E' => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.rightShoulder,
                                @intFromBool(isDown),
                            );
                        },
                        @intFromEnum(win32.VK_UP) => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.actionUp,
                                @intFromBool(isDown),
                            );
                        },
                        @intFromEnum(win32.VK_LEFT) => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.actionLeft,
                                @intFromBool(isDown),
                            );
                        },
                        @intFromEnum(win32.VK_DOWN) => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.actionDown,
                                @intFromBool(isDown),
                            );
                        },
                        @intFromEnum(win32.VK_RIGHT) => {
                            Win32ProcessKeyboardMessage(
                                &keyboard_controller.buttons.actionRight,
                                @intFromBool(isDown),
                            );
                        },
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
                            const isAltKeyDown = message.lParam & (1 << 29) != 0;
                            if (isAltKeyDown) {
                                running = false;
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {
                _ = win32.TranslateMessage(&message);
                _ = win32.DispatchMessage(&message);
            },
        }
    }
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

        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            const deviceContext = win32.BeginPaint(windowHandle, &paint);

            const windowDimension = Win32WindowDimension.get(windowHandle);
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

    if (buffer.memory != null) {
        _ = win32.VirtualFree(
            buffer.*.memory,
            0,
            win32.VIRTUAL_FREE_TYPE.RELEASE,
        );
    }

    buffer.width = width;
    buffer.height = height;

    buffer.info = win32.BITMAPINFO{ .bmiHeader = win32.BITMAPINFOHEADER{
        .biSize = @sizeOf(win32.BITMAPINFOHEADER),
        .biWidth = buffer.width,
        .biHeight = -buffer.height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    }, .bmiColors = [1]win32.RGBQUAD{win32.RGBQUAD{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }} };

    const bitmapMemorySize: usize = @as(usize, @intCast((buffer.width * buffer.height) * buffer.bytesPerPixel));

    buffer.memory = win32.VirtualAlloc(
        null,
        bitmapMemorySize,
        win32.VIRTUAL_ALLOCATION_TYPE{ .RESERVE = 1, .COMMIT = 1 },
        win32.PAGE_READWRITE,
    );
    buffer.pitch = @intCast((buffer.bytesPerPixel * width));
}

fn ProcessWindowsError() void {
    const errorMessage = win32.GetLastError();
    std.debug.print("{}", .{errorMessage});
}

fn rdtsc() u64 {
    var low: u64 = undefined;
    var high: u64 = undefined;

    asm volatile ("rdtsc"
        : [low] "={eax}" (low),
          [high] "={edx}" (high),
    );

    return (high << 32) | low;
}
