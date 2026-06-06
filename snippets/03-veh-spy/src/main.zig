const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const win32 = veh_shared.win32;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

extern "kernel32" fn AddVectoredExceptionHandler(
    First: veh.ULONG,
    Handler: win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;

extern "kernel32" fn RemoveVectoredExceptionHandler(
    Handle: veh.PVOID,
) callconv(.winapi) veh.ULONG;

fn spyHandler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    if (info.ExceptionRecord.ExceptionCode != veh.EXCEPTION_INT_DIVIDE_BY_ZERO)
        return veh.EXCEPTION_CONTINUE_SEARCH;
    std.debug.print("[SPY] div-by-zero @ Rip=0x{x} (observed, passing through)\n", .{
        info.ContextRecord.Rip,
    });
    return veh.EXCEPTION_CONTINUE_SEARCH;
}

fn realHandler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    if (info.ExceptionRecord.ExceptionCode != veh.EXCEPTION_INT_DIVIDE_BY_ZERO)
        return veh.EXCEPTION_CONTINUE_SEARCH;
    info.ContextRecord.Rip += 2;
    std.debug.print("[REAL] fixed Rip -> 0x{x}\n", .{info.ContextRecord.Rip});
    return veh.EXCEPTION_CONTINUE_EXECUTION;
}

fn triggerDivByZero() void {
    asm volatile (
        \\ movl $1, %%eax
        \\ xor %%edx, %%edx
        \\ movl $0, %%ecx
        \\ idivl %%ecx
    );
}

pub fn main() !void {
    std.debug.print("03-veh-spy\n", .{});
    std.debug.print("==========\n", .{});

    const hReal = AddVectoredExceptionHandler(1, &realHandler) orelse return error.RegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(hReal);

    const hSpy = AddVectoredExceptionHandler(1, &spyHandler) orelse return error.RegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(hSpy);

    std.debug.print("[*] triggering divide-by-zero...\n", .{});
    triggerDivByZero();
    std.debug.print("[ok] continued execution\n", .{});
}
