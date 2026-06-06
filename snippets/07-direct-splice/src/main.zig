const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const win32 = veh_shared.win32;
const veh_probe = veh_shared.veh_probe;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

fn handler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    const code = info.ExceptionRecord.ExceptionCode;
    if (code != veh.EXCEPTION_INT_DIVIDE_BY_ZERO) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    const old_rip = info.ContextRecord.Rip;
    info.ContextRecord.Rip += 2; // skip 2-byte idiv on x64
    std.debug.print("[VEH] Rip 0x{x} -> 0x{x} (+2)\n", .{ old_rip, info.ContextRecord.Rip });
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
    std.debug.print("07-direct-splice\n", .{});
    std.debug.print("================\n", .{});

    const direct_handle = try veh_probe.installVectoredHandlerDirectly(&handler);
    defer veh_probe.removeVectoredHandlerDirectly(direct_handle);

    std.debug.print("Spliced directly - no AddVectoredExceptionHandler for our handler.\n", .{});
    std.debug.print("[*] triggering divide-by-zero...\n", .{});
    triggerDivByZero();
    std.debug.print("[ok] continued execution\n", .{});
}
