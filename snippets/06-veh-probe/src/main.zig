const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const structs = veh_shared.structs;
const veh_probe = veh_shared.veh_probe;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

extern "kernel32" fn AddVectoredExceptionHandler(
    first: veh.ULONG,
    handler: veh_shared.win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn RemoveVectoredExceptionHandler(handle: veh.PVOID) callconv(.winapi) veh.ULONG;

pub fn main() !void {
    std.debug.print("06-veh-probe\n", .{});
    std.debug.print("============\n", .{});

    const probe = AddVectoredExceptionHandler(1, &veh_probe.vehProbeHandler) orelse
        return error.ProbeRegistrationFailed;
    defer _ = RemoveVectoredExceptionHandler(probe);

    const entry: *structs.VECTORED_HANDLER_ENTRY = @ptrCast(@alignCast(probe));
    const head = veh_probe.findVehListHead(&entry.list) orelse return error.VehListHeadNotFound;
    const lock: *structs.SRWLOCK = @ptrFromInt(@intFromPtr(head) - @sizeOf(structs.SRWLOCK));

    std.debug.print("[walk] LIST_HEAD @ 0x{x}\n", .{@intFromPtr(head)});
    std.debug.print("[lock] SRWLOCK   @ 0x{x}\n", .{@intFromPtr(lock)});
}
