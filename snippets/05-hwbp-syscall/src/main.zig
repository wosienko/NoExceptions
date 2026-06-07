const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const win32 = veh_shared.win32;
const syscall_resolve = veh_shared.syscall_resolve;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

const THREAD_ALL_ACCESS: u32 = 0x001F03FF;
const MEM_COMMIT_RESERVE: u32 = 0x3000;
const PAGE_READWRITE: u32 = 0x04;

const CONTEXT_AMD64: u32 = 0x00100000;
const CONTEXT_DEBUG_REGISTERS: u32 = CONTEXT_AMD64 | 0x10;

const TamperedParams = struct {
    real_ssn: u32 = 0,
    arg1: u64 = 0,
    arg2: u64 = 0,
    arg3: u64 = 0,
    arg4: u64 = 0,
    armed: bool = false,
};

const NtDecoyCall = *const fn (
    process_handle: veh.PVOID,
    base_address: *veh.PVOID,
    zero_bits: usize,
    region_size: *usize,
    allocation_type: u32,
    protect: u32,
) callconv(.winapi) veh.NTSTATUS;

extern "kernel32" fn AddVectoredExceptionHandler(
    first: veh.ULONG,
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn RemoveVectoredExceptionHandler(handle: veh.PVOID) callconv(.winapi) veh.ULONG;
extern "kernel32" fn GetModuleHandleA(module_name: [*:0]const u8) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetProcAddress(
    module: ?*anyopaque,
    proc_name: [*:0]const u8,
) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn GetCurrentThreadId() callconv(.winapi) u32;
extern "kernel32" fn OpenThread(
    desired_access: u32,
    inherit_handle: veh.BOOL,
    thread_id: u32,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn CloseHandle(object: veh.PVOID) callconv(.winapi) veh.BOOL;
extern "kernel32" fn GetThreadContext(
    thread: veh.PVOID,
    context: *win32.CONTEXT_FULL,
) callconv(.winapi) veh.BOOL;
extern "kernel32" fn SetThreadContext(
    thread: veh.PVOID,
    context: *const win32.CONTEXT_FULL,
) callconv(.winapi) veh.BOOL;

var g_params: TamperedParams = .{};

fn setDr7Bits(current: u64, start_bit: u6, bit_count: u6, new_value: u64) u64 {
    const mask = (@as(u64, 1) << bit_count) - 1;
    return (current & ~(mask << start_bit)) | ((new_value & mask) << start_bit);
}

fn findSyscallInstruction(decoy_addr: usize) ?usize {
    var i: usize = 0;
    while (i + 1 < 0x40) : (i += 1) {
        const b0 = @as(*align(1) const u8, @ptrFromInt(decoy_addr + i)).*;
        const b1 = @as(*align(1) const u8, @ptrFromInt(decoy_addr + i + 1)).*;
        if (b0 == 0x0F and b1 == 0x05) {
            return decoy_addr + i;
        }
    }
    return null;
}

fn passParameters(arg1: u64, arg2: u64, arg3: u64, arg4: u64, real_ssn: u32) void {
    g_params.arg1 = arg1;
    g_params.arg2 = arg2;
    g_params.arg3 = arg3;
    g_params.arg4 = arg4;
    g_params.real_ssn = real_ssn;
    g_params.armed = true;
}

fn installHardwareBreakpoint(thread_id: u32, target_address: usize) bool {
    const thread = OpenThread(THREAD_ALL_ACCESS, 0, thread_id) orelse return false;
    defer _ = CloseHandle(thread);

    var context: win32.CONTEXT_FULL = std.mem.zeroes(win32.CONTEXT_FULL);
    context.ContextFlags = CONTEXT_DEBUG_REGISTERS;

    if (GetThreadContext(thread, &context) == 0) return false;

    context.Dr0 = target_address;
    context.Dr6 = 0;
    context.Dr7 = setDr7Bits(context.Dr7, 16, 2, 0); // RW0 = execute
    context.Dr7 = setDr7Bits(context.Dr7, 18, 2, 0); // LEN0 = 1 byte
    context.Dr7 = setDr7Bits(context.Dr7, 0, 1, 1); // L0 = enabled

    return SetThreadContext(thread, &context) != 0;
}

fn singleStepHandler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    if (info.ExceptionRecord.ExceptionCode != veh.STATUS_SINGLE_STEP) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    if (!g_params.armed) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    const exception_address_ptr = info.ExceptionRecord.ExceptionAddress orelse {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    };
    const exception_address = @intFromPtr(exception_address_ptr);
    if (exception_address != info.ContextRecord.Dr0) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    const decoy_ssn: u32 = @truncate(info.ContextRecord.Rax);
    std.debug.print("[VEH] Decoy SSN: {d}\n", .{decoy_ssn});
    std.debug.print("[VEH] Real  SSN: {d}\n", .{g_params.real_ssn});

    info.ContextRecord.Rax = g_params.real_ssn;
    info.ContextRecord.R10 = g_params.arg1;
    info.ContextRecord.Rdx = g_params.arg2;
    info.ContextRecord.R8 = g_params.arg3;
    info.ContextRecord.R9 = g_params.arg4;
    info.ContextRecord.Dr0 = 0;
    g_params.armed = false;

    return veh.EXCEPTION_CONTINUE_EXECUTION;
}

pub fn main() !void {
    std.debug.print("05-hwbp-syscall\n", .{});
    std.debug.print("===============\n", .{});

    const ntdll = GetModuleHandleA("ntdll.dll") orelse return error.NtdllNotLoaded;
    const real_ssn = try syscall_resolve.resolveSsnByName(ntdll, "NtAllocateVirtualMemory");

    const decoy_raw = GetProcAddress(ntdll, "NtQuerySecurityObject") orelse return error.DecoyNotFound;
    const decoy_addr = @intFromPtr(decoy_raw);
    const breakpoint_addr = findSyscallInstruction(decoy_addr) orelse return error.SyscallInstructionNotFound;

    std.debug.print("[i] decoy stub: 0x{x}\n", .{decoy_addr});
    std.debug.print("[i] hwbp @ syscall instruction: 0x{x}\n", .{breakpoint_addr});

    const veh_handle = AddVectoredExceptionHandler(1, &singleStepHandler) orelse {
        return error.VehRegistrationFailed;
    };
    defer _ = RemoveVectoredExceptionHandler(veh_handle);

    if (!installHardwareBreakpoint(GetCurrentThreadId(), breakpoint_addr)) {
        return error.HwbpInstallFailed;
    }

    var base_address: veh.PVOID = null;
    var region_size: usize = 0x100;
    const pseudo_current_process = std.math.maxInt(usize);

    passParameters(
        pseudo_current_process,
        @intFromPtr(&base_address),
        0,
        @intFromPtr(&region_size),
        real_ssn,
    );

    const decoy_fn: NtDecoyCall = @ptrFromInt(decoy_addr);
    const status = decoy_fn(
        @ptrFromInt(pseudo_current_process),
        &base_address,
        0,
        &region_size,
        MEM_COMMIT_RESERVE,
        PAGE_READWRITE,
    );

    std.debug.print("[i] Nt status: 0x{x}\n", .{@as(u32, @bitCast(status))});
    std.debug.print("[i] BaseAddress: 0x{x}\n", .{if (base_address) |ptr| @intFromPtr(ptr) else 0});
    std.debug.print("[i] RegionSize: 0x{x}\n", .{region_size});

    if (!veh.NT_SUCCESS(status)) {
        return error.NtAllocateVirtualMemoryFailed;
    }

    std.debug.print("[ok] decoy SSN replaced with resolved SSN\n", .{});
}
