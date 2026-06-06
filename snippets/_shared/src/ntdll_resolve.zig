const veh = @import("veh_constants.zig");
const structs = @import("veh_structs.zig");

extern "kernel32" fn GetModuleHandleA(lp_module_name: ?[*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(h_module: ?*anyopaque, proc_name: [*:0]const u8) callconv(.winapi) ?*anyopaque;

pub const LdrProtectMrdataFn = *const fn (protect: veh.BOOL) callconv(.winapi) void;
pub const LdrEnsureMrdataHeapExistsFn = *const fn () callconv(.winapi) void;

pub fn getNtdllBase() ?*anyopaque {
    return GetModuleHandleA("NTDLL.DLL");
}

pub fn getVectoredHandlerList(ntdll: ?*anyopaque) ?*structs.VECTORED_HANDLER_LIST {
    const export_fn = GetProcAddress(ntdll, "RtlRemoveVectoredExceptionHandler") orelse return null;
    var ptr: usize = @intFromPtr(export_fn);

    while (readU8(ptr) != 0xcc) {
        if (readU8(ptr) == 0xe9) {
            ptr = applyRel32(ptr + 5, readI32(ptr + 1));

            while ((readU32(ptr) & 0x00ff_ffff) != 0x258d4c) {
                ptr += 1;
            }

            return @ptrFromInt(applyRel32(ptr + 7, readI32(ptr + 3)));
        }
        ptr += 1;
    }

    return null;
}

pub fn getLdrProtectMrdata(ntdll: ?*anyopaque) ?LdrProtectMrdataFn {
    const export_fn = GetProcAddress(ntdll, "RtlDeleteFunctionTable") orelse return null;
    var ptr: usize = @intFromPtr(export_fn);

    while (true) {
        if (readU8(ptr) == 0xe8) {
            return @ptrFromInt(applyRel32(ptr + 5, readI32(ptr + 1)));
        }
        ptr += 1;
    }
}

pub fn getLdrpMrdataHeap(ntdll: ?*anyopaque) ?*veh.PVOID {
    const export_fn = GetProcAddress(ntdll, "RtlAddFunctionTable") orelse return null;
    var ptr: usize = @intFromPtr(export_fn);

    while ((readU32(ptr) & 0x00ff_ffff) != 0x0d8b48) {
        ptr += 1;
    }

    return @ptrFromInt(applyRel32(ptr + 7, readI32(ptr + 3)));
}

pub fn getLdrEnsureMrdataHeapExists(ntdll: ?*anyopaque) ?LdrEnsureMrdataHeapExistsFn {
    const export_fn = GetProcAddress(ntdll, "RtlAddFunctionTable") orelse return null;
    var ptr: usize = @intFromPtr(export_fn);

    while (true) {
        if (readU8(ptr) == 0xe8) {
            return @ptrFromInt(applyRel32(ptr + 5, readI32(ptr + 1)));
        }
        ptr += 1;
    }
}

fn readU8(addr: usize) u8 {
    return @as(*const u8, @ptrFromInt(addr)).*;
}

fn readU32(addr: usize) u32 {
    return @as(*align(1) const u32, @ptrFromInt(addr)).*;
}

fn readI32(addr: usize) i32 {
    return @as(*align(1) const i32, @ptrFromInt(addr)).*;
}

fn applyRel32(base: usize, disp: i32) usize {
    const signed_base: i64 = @intCast(base);
    const signed_disp: i64 = disp;
    return @intCast(signed_base + signed_disp);
}
