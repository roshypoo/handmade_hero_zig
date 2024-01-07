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
const L = win32.L;
const HINSTANCE = win32.HINSTANCE;
const HWND = win32.HWND;
const HDC = win32.HDC;

// TODO(rosh): This is a global for now.
var running: bool = undefined;
var bitmapInfo: win32.BITMAPINFO = undefined;
var bitmapMemory: ?*anyopaque = undefined;
var bitmapHandle: ?win32.HBITMAP = undefined;
var bitmapDeviceContext: ?HDC = null;

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
        const windowHandle = win32.CreateWindowEx(@as(win32.WINDOW_EX_STYLE, @enumFromInt(0)), WindowClass.lpszClassName, win32.L("Handmade Hero"), win32.WINDOW_STYLE.initFlags(.{ .OVERLAPPED = 1, .VISIBLE = 1, .SYSMENU = 1, .THICKFRAME = 1 }), win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, win32.CW_USEDEFAULT, null, null, hInstance, null);

        if (windowHandle != null) {
            var message: win32.MSG = undefined;
            running = true;
            while (running) {
                var messageResult = win32.GetMessage(&message, null, 0, 0);
                if (messageResult > 0) {
                    _ = win32.TranslateMessage(&message);
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
            var clientRect: win32.RECT = win32.RECT{ .bottom = 0, .left = 0, .right = 0, .top = 0 };
            _ = win32.GetClientRect(windowHandle, &clientRect);
            const width = clientRect.right - clientRect.left;
            const height = clientRect.bottom - clientRect.top;
            resizeDIBSection(width, height);
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
            var deviceContext = win32.BeginPaint(windowHandle, &paint);
            var x = paint.rcPaint.left;
            var y = paint.rcPaint.top;
            var width = paint.rcPaint.right - paint.rcPaint.left;
            var height = paint.rcPaint.bottom - paint.rcPaint.top;
            if (deviceContext) |context| {
                UpdateWindow(context, x, y, width, height);
            }
            _ = win32.EndPaint(windowHandle, &paint);
        },
        else => {
            result = win32.DefWindowProc(windowHandle, message, wParam, lParam);
        },
    }

    return result;
}

fn UpdateWindow(deviceContext: HDC, x: i32, y: i32, width: i32, height: i32) void {
    _ = win32.StretchDIBits(deviceContext, x, y, width, height, x, y, width, height, bitmapMemory, &bitmapInfo, win32.DIB_USAGE.RGB_COLORS, win32.ROP_CODE.SRCCOPY);
}

fn resizeDIBSection(width: i32, height: i32) void {

    //TODO(rosh): Bulletproof this.
    // Maybe don't free first, free after, then free first if that fails.

    if (bitmapHandle) |bmHandle| {
        _ = win32.DeleteObject(bmHandle);
    }
    if (bitmapDeviceContext == null) {
        //TODO(rosh): Should we recreate this under special circumstances.
        bitmapDeviceContext = win32.CreateCompatibleDC(bitmapDeviceContext);
    }

    bitmapInfo = win32.BITMAPINFO{ .bmiHeader = win32.BITMAPINFOHEADER{
        .biSize = @sizeOf(win32.BITMAPINFOHEADER),
        .biWidth = width,
        .biHeight = height,
        .biPlanes = 1,
        .biBitCount = 32,
        .biCompression = win32.BI_RGB,
        .biSizeImage = 0,
        .biXPelsPerMeter = 0,
        .biYPelsPerMeter = 0,
        .biClrUsed = 0,
        .biClrImportant = 0,
    }, .bmiColors = [1]win32.RGBQUAD{win32.RGBQUAD{ .rgbBlue = 0, .rgbGreen = 0, .rgbRed = 0, .rgbReserved = 0 }} };

    bitmapHandle = win32.CreateDIBSection(bitmapDeviceContext, &bitmapInfo, win32.DIB_USAGE.RGB_COLORS, &bitmapMemory, null, 0);
}

fn ProcessWindowsError() void {
    var errorMessage = win32.GetLastError();
    std.debug.print("{}", .{errorMessage});
}
