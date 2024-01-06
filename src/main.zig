pub const UNICODE = true;

const WINAPI = @import("std").os.windows.WINAPI;
const std = @import("std");
const log = std.log.info;

const win32 = struct {
    usingnamespace @import("win32").zig;
    usingnamespace @import("win32").ui.windows_and_messaging;
    usingnamespace @import("win32").system.diagnostics.debug;
    usingnamespace @import("win32").foundation;
    usingnamespace @import("win32").graphics.gdi;
};
const cString = @cImport({
    @cInclude("string.h");
});
const L = win32.L;
const HINSTANCE = win32.HINSTANCE;
const HWND = win32.HWND;

pub export fn wWinMain(hInstance: HINSTANCE, _: ?HINSTANCE, _: [*:0]u16, _: u32) callconv(WINAPI) c_int {
    const WindowClass = win32.WNDCLASS{
        // TODO(rosh): Check if OWNDC/VREDAW/HREDRAW still matter
        .style = win32.WNDCLASS_STYLES.initFlags(.{}),
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
            @as(win32.WINDOW_EX_STYLE, @enumFromInt(0)),
            WindowClass.lpszClassName, 
            win32.L("Handmade Hero"), 
            win32.WINDOW_STYLE.initFlags(.{ .OVERLAPPED = 1, .VISIBLE = 1}), 
            win32.CW_USEDEFAULT, 
            win32.CW_USEDEFAULT, 
            win32.CW_USEDEFAULT, 
            win32.CW_USEDEFAULT, 
            null,
             null, 
             hInstance, 
             null
        );

        if (windowHandle != null) {
            var message: win32.MSG = undefined;
            while(true) {
                var messageResult = win32.GetMessage(&message, null, 0, 0);
                if (messageResult > 0) {
                  _ =  win32.TranslateMessage(&message);
                  _ = win32.DispatchMessage(&message);
                } else break;
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

fn WindowProc(windowHandle: HWND, message: u32, wParam: win32.WPARAM, lParam: win32.LPARAM) callconv(WINAPI) win32.LRESULT {
    var result: win32.LRESULT = 0;

    switch (message) {
        win32.WM_SIZE => {
            win32.OutputDebugStringA("WM_SIZE\n");
        },
        win32.WM_DESTROY => {
            win32.OutputDebugStringA("WM_DESTROY\n");
        },
        win32.WM_CLOSE => {
            win32.OutputDebugStringA("WM_CLOSE\n");
        },
        win32.WM_ACTIVATEAPP => {
            win32.OutputDebugStringA("WM_ACTIVATE_APP\n");
        },
        win32.WM_PAINT => {
            var paint: win32.PAINTSTRUCT = undefined;
            var deviceContext = win32.BeginPaint(windowHandle, &paint);
            var x = paint.rcPaint.left;
            var y = paint.rcPaint.top;
            var width = paint.rcPaint.right - paint.rcPaint.left;
            var height = paint.rcPaint.bottom - paint.rcPaint.top;
            _ = win32.PatBlt(deviceContext, x, y, width, height, win32.BLACKNESS);
            _ = win32.EndPaint(windowHandle, &paint);
        },
        else => {
            result = win32.DefWindowProc(windowHandle, message, wParam, lParam);
        },
    }

    return result;
}

fn ProcessWindowsError() void {
    var errorMessage = win32.GetLastError();
    std.debug.print("{}", .{ errorMessage});
}