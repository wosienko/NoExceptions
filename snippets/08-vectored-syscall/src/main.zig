const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const win32 = veh_shared.win32;
const syscall_resolve = veh_shared.syscall_resolve;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

extern "kernel32" fn GetModuleHandleA(lp_module_name: ?[*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn AddVectoredExceptionHandler(
    first: veh.ULONG,
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn RemoveVectoredExceptionHandler(handle: veh.PVOID) callconv(.winapi) veh.ULONG;

const NtCloseFn = *const fn (handle: veh.PVOID) callconv(.winapi) veh.NTSTATUS;

var g_syscall_addr: usize = 0;

fn handleException(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    if (info.ExceptionRecord.ExceptionCode != veh.EXCEPTION_ACCESS_VIOLATION or g_syscall_addr == 0) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    const ctx = info.ContextRecord;
    ctx.R10 = ctx.Rcx;
    ctx.Rax = ctx.Rip;
    ctx.Rip = g_syscall_addr;
    return veh.EXCEPTION_CONTINUE_EXECUTION;
}

pub fn main() !void {
    std.debug.print("08-vectored-syscall\n", .{});
    std.debug.print("===================\n", .{});

    const ntdll = GetModuleHandleA("ntdll.dll") orelse return error.NtdllNotFound;
    const syscall_stub = syscall_resolve.findSyscallStub(ntdll) orelse return error.SyscallStubNotFound;
    g_syscall_addr = syscall_stub;

    const ssn = try syscall_resolve.resolveSsnByName(ntdll, "NtClose");
    std.debug.print("[i] syscall stub @ 0x{x}\n", .{syscall_stub});
    std.debug.print("[i] NtClose SSN = 0x{x}\n", .{ssn});

    const veh_handle = AddVectoredExceptionHandler(1, &handleException) orelse {
        return error.VehRegistrationFailed;
    };
    defer _ = RemoveVectoredExceptionHandler(veh_handle);

    const pNtClose: NtCloseFn = @ptrFromInt(@as(usize, ssn));
    const invalid_handle: veh.PVOID = @ptrFromInt(std.math.maxInt(usize));
    const status = pNtClose(invalid_handle);
    std.debug.print("[+] NtClose status: 0x{x}\n", .{@as(u32, @bitCast(status))});
    std.debug.print("[ok] vectored syscall redirection executed\n", .{});
}
