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

fn handlerA(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    const code = info.ExceptionRecord.ExceptionCode;
    std.debug.print("[handler-A] code=0x{x} -> SEARCH\n", .{code});
    return veh.EXCEPTION_CONTINUE_SEARCH;
}

fn handlerB(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    const code = info.ExceptionRecord.ExceptionCode;
    std.debug.print("[handler-B] code=0x{x} -> EXECUTION\n", .{code});
    if (code == veh.EXCEPTION_INT_DIVIDE_BY_ZERO) {
        info.ContextRecord.Rip += 2;
    }
    return veh.EXCEPTION_CONTINUE_EXECUTION;
}

fn handlerC(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    _ = info;
    std.debug.print("[handler-C]\n", .{});
    return veh.EXCEPTION_CONTINUE_SEARCH;
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
    std.debug.print("02-veh-chain\n", .{});
    std.debug.print("============\n", .{});

    const hB = AddVectoredExceptionHandler(1, &handlerB) orelse return error.RegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(hB);

    const hA = AddVectoredExceptionHandler(1, &handlerA) orelse return error.RegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(hA);

    const hC = AddVectoredExceptionHandler(0, &handlerC) orelse return error.RegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(hC);

    std.debug.print("[*] triggering divide-by-zero...\n", .{});
    triggerDivByZero();
    std.debug.print("[ok] continued execution\n", .{});
}
