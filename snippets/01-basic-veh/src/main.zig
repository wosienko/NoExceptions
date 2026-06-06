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

fn handler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    const code = info.ExceptionRecord.ExceptionCode;
    std.debug.print("[VEH] caught 0x{x}\n", .{code});
    if (code != veh.EXCEPTION_INT_DIVIDE_BY_ZERO)
        return veh.EXCEPTION_CONTINUE_SEARCH;

    const ctx = info.ContextRecord;
    const old_rip = ctx.Rip;
    ctx.Rip += 2; // skip 2-byte idiv on x64
    std.debug.print("[VEH] Rip 0x{x} -> 0x{x} (+2)\n", .{ old_rip, ctx.Rip });
    return veh.EXCEPTION_CONTINUE_EXECUTION;
}

fn triggerDivByZero() void {
    // Force a real 2-byte idiv so the CPU raises EXCEPTION_INT_DIVIDE_BY_ZERO
    asm volatile (
        \\ movl $1, %%eax
        \\ xor %%edx, %%edx
        \\ movl $0, %%ecx
        \\ idivl %%ecx
    );
}

pub fn main() !void {
    std.debug.print("01-basic-veh\n", .{});
    std.debug.print("============\n", .{});

    const h = AddVectoredExceptionHandler(1, &handler) orelse {
        std.debug.print("[!] AddVectoredExceptionHandler failed\n", .{});
        return error.RegistrationFailed;
    };
    defer _ = RemoveVectoredExceptionHandler(h);

    std.debug.print("[*] triggering divide-by-zero...\n", .{});
    triggerDivByZero();
    std.debug.print("[ok] continued execution\n", .{});
}
