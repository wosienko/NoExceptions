const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const resolve = veh_shared.ntdll_resolve;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

pub fn main() !void {
    const ntdll = resolve.getNtdllBase() orelse return error.NoNtdll;
    const handler_list = resolve.getVectoredHandlerList(ntdll) orelse return error.NoVectorHandlerList;
    const ldr_protect = resolve.getLdrProtectMrdata(ntdll) orelse return error.NoLdrProtectMrdata;
    const mrdata_heap_ptr = resolve.getLdrpMrdataHeap(ntdll) orelse return error.NoLdrpMrdataHeap;
    const ensure_heap_exists = resolve.getLdrEnsureMrdataHeapExists(ntdll) orelse return error.NoEnsureHeapExists;

    std.debug.print("04-lea-resolve\n", .{});
    std.debug.print("================\n", .{});
    std.debug.print("LdrpVectorHandlerList @ 0x{x}\n", .{@intFromPtr(handler_list)});
    std.debug.print("LdrProtectMrdata      @ 0x{x}\n", .{@intFromPtr(ldr_protect)});
    std.debug.print("LdrpMrdataHeap ptr    @ 0x{x}\n", .{@intFromPtr(mrdata_heap_ptr)});
    std.debug.print("LdrEnsure...Exists    @ 0x{x}\n", .{@intFromPtr(ensure_heap_exists)});

    if (mrdata_heap_ptr.*) |mrdata_heap| {
        std.debug.print("LdrpMrdataHeap value  @ 0x{x}\n", .{@intFromPtr(mrdata_heap)});
    } else {
        std.debug.print("LdrpMrdataHeap value  @ 0x0\n", .{});
    }
}
