pub const UNICODE = true;

const WINAPI = @import("std").os.windows.WINAPI;
const std = @import("std");
const log = std.log.info;

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").foundation;
};
const cString = @cImport({
    @cInclude("string.h");
});
const L = win32.L;
const HINSTANCE = win32.HINSTANCE;
// const CW_USEDEFAULT = win32.CW_USEDEFAULT;
// const MSG = win32.MSG;
// const HWND = win32.HWND;

pub export fn wWinMain(_: HINSTANCE, _: ?HINSTANCE, _: [*:0]u16, _: u32) callconv(WINAPI) c_int {
    _ = win32.MessageBoxA(null, "This is Handmade Hero", "Handmade Hero", win32.MB_OK);
    return 0;
}
