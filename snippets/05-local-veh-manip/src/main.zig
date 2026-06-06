const std = @import("std");
const builtin = @import("builtin");
const veh_shared = @import("veh_shared");
const veh = veh_shared.veh;
const win32 = veh_shared.win32;
const structs = veh_shared.structs;
const resolve = veh_shared.ntdll_resolve;

comptime {
    if (builtin.os.tag != .windows) @compileError("Windows only");
}

const ProcessControlFlowGuardPolicy: u32 = 7;

const PROCESS_MITIGATION_CONTROL_FLOW_GUARD_POLICY = extern struct {
    Flags: u32,
};

const RtlProtectHeapFn = *const fn (
    heap_handle: veh.PVOID,
    make_read_only: veh.BOOL,
) callconv(.winapi) veh.BOOL;

extern "kernel32" fn GetCurrentProcess() callconv(.winapi) veh.PVOID;
extern "kernel32" fn GetProcessMitigationPolicy(
    h_process: veh.PVOID,
    mitigation_policy: u32,
    buffer: *PROCESS_MITIGATION_CONTROL_FLOW_GUARD_POLICY,
    length: usize,
) callconv(.winapi) veh.BOOL;
extern "kernel32" fn GetProcessHeap() callconv(.winapi) veh.PVOID;
extern "kernel32" fn HeapAlloc(
    h_heap: veh.PVOID,
    dw_flags: veh.DWORD,
    dw_bytes: usize,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn GetProcAddress(
    h_module: ?*anyopaque,
    proc_name: [*:0]const u8,
) callconv(.winapi) ?*anyopaque;
extern "kernel32" fn AcquireSRWLockExclusive(lock: *structs.SRWLOCK) callconv(.winapi) void;
extern "kernel32" fn ReleaseSRWLockExclusive(lock: *structs.SRWLOCK) callconv(.winapi) void;
extern "kernel32" fn EncodePointer(ptr: veh.PVOID) callconv(.winapi) veh.PVOID;
extern "kernel32" fn AddVectoredExceptionHandler(
    first: veh.ULONG,
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn RemoveVectoredExceptionHandler(handle: veh.PVOID) callconv(.winapi) veh.ULONG;

var g_ref: u64 = 1;

fn asBOOL(v: bool) veh.BOOL {
    return if (v) 1 else 0;
}

fn listStartEntry(list: *structs.VECTORED_HANDLER_LIST) *structs.VECTORED_HANDLER_ENTRY {
    return @ptrFromInt(@intFromPtr(list) + @offsetOf(structs.VECTORED_HANDLER_LIST, "FirstVEH"));
}

fn listStartList(list: *structs.VECTORED_HANDLER_LIST) *structs.LIST_ENTRY {
    return @ptrFromInt(@intFromPtr(list) + @offsetOf(structs.VECTORED_HANDLER_LIST, "FirstVEH"));
}

fn isCfgEnabled() bool {
    var policy: PROCESS_MITIGATION_CONTROL_FLOW_GUARD_POLICY = .{ .Flags = 0 };
    if (GetProcessMitigationPolicy(
        GetCurrentProcess(),
        ProcessControlFlowGuardPolicy,
        &policy,
        @sizeOf(PROCESS_MITIGATION_CONTROL_FLOW_GUARD_POLICY),
    ) == 0) {
        return false;
    }
    return (policy.Flags & 0x1) != 0;
}

fn addVectoredExceptionHandlerReplacement(
    first: bool,
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) ?*structs.VECTORED_HANDLER_ENTRY {
    const ntdll = resolve.getNtdllBase() orelse return null;
    const list = resolve.getVectoredHandlerList(ntdll) orelse return null;
    const ldr_protect = resolve.getLdrProtectMrdata(ntdll) orelse return null;

    const cfg_enabled = isCfgEnabled();
    std.debug.print("[i] CFG enabled: {s}\n", .{if (cfg_enabled) "yes" else "no"});

    var heap = GetProcessHeap();
    if (heap == null) return null;

    var rtl_protect_heap: ?RtlProtectHeapFn = null;
    if (cfg_enabled) {
        const rtl_raw = GetProcAddress(ntdll, "RtlProtectHeap") orelse return null;
        rtl_protect_heap = @ptrFromInt(@intFromPtr(rtl_raw));

        const mrdata_heap_ptr = resolve.getLdrpMrdataHeap(ntdll) orelse return null;
        if (mrdata_heap_ptr.* == null) {
            const ensure_heap_exists = resolve.getLdrEnsureMrdataHeapExists(ntdll) orelse return null;
            ensure_heap_exists();
        }

        heap = mrdata_heap_ptr.* orelse return null;
    }

    var heap_unprotected = false;
    defer if (heap_unprotected and rtl_protect_heap != null) {
        _ = rtl_protect_heap.?(heap, asBOOL(true));
    };

    if (cfg_enabled) {
        _ = rtl_protect_heap.?(heap, asBOOL(false));
        heap_unprotected = true;
    }

    var lock_held = false;
    defer if (lock_held) ReleaseSRWLockExclusive(list.LockVEH);

    var mrdata_unprotected = false;
    defer if (mrdata_unprotected) resolve.callLdrProtectMrdata(ldr_protect, true);

    AcquireSRWLockExclusive(list.LockVEH);
    lock_held = true;

    resolve.callLdrProtectMrdata(ldr_protect, false);
    mrdata_unprotected = true;

    const veh_list_start_entry = listStartEntry(list);
    const veh_list_start_list = listStartList(list);
    const empty = list.FirstVEH == veh_list_start_entry;

    const raw_entry = HeapAlloc(heap, 0, @sizeOf(structs.VECTORED_HANDLER_ENTRY)) orelse return null;
    const new_entry: *structs.VECTORED_HANDLER_ENTRY = @ptrCast(@alignCast(raw_entry));

    new_entry.refcount = &g_ref;
    new_entry.removed = 0;
    new_entry._reserved = 0;
    new_entry.encoded_handler = EncodePointer(@ptrFromInt(@intFromPtr(handler)));

    if (empty or first) {
        if (empty) {
            resolve.flipProcessUsingVehBit();
            new_entry.list.Flink = veh_list_start_list;
            new_entry.list.Blink = veh_list_start_list;
            list.LastVEH = new_entry;
        } else {
            new_entry.list.Flink = &list.FirstVEH.list;
            new_entry.list.Blink = veh_list_start_list;
            list.FirstVEH.list.Blink = &new_entry.list;
        }
        list.FirstVEH = new_entry;
    } else {
        const tail = list.LastVEH;
        tail.list.Flink = &new_entry.list;
        new_entry.list.Flink = veh_list_start_list;
        new_entry.list.Blink = &tail.list;
        list.LastVEH = new_entry;
    }

    std.debug.print("[+] manual VEH entry @ 0x{x}\n", .{@intFromPtr(new_entry)});
    return new_entry;
}

fn pageAlignDown(ptr: *structs.VECTORED_HANDLER_ENTRY) veh.PVOID {
    return @ptrFromInt(@intFromPtr(ptr) & ~@as(usize, 0xfff));
}

fn overwriteFirstVectoredExceptionHandler(handler: win32.PVECTORED_EXCEPTION_HANDLER) bool {
    const ntdll = resolve.getNtdllBase() orelse return false;
    const list = resolve.getVectoredHandlerList(ntdll) orelse return false;

    var lock_held = false;
    defer if (lock_held) ReleaseSRWLockExclusive(list.LockVEH);

    var rtl_protect_heap: ?RtlProtectHeapFn = null;
    var cfg_target: veh.PVOID = null;
    var cfg_unprotected = false;
    defer if (cfg_unprotected and rtl_protect_heap != null) {
        _ = rtl_protect_heap.?(cfg_target, asBOOL(true));
    };

    AcquireSRWLockExclusive(list.LockVEH);
    lock_held = true;

    const start = listStartEntry(list);
    if (list.FirstVEH == start) {
        std.debug.print("[!] overwrite requested but VEH list is empty\n", .{});
        return false;
    }

    if (isCfgEnabled()) {
        const rtl_raw = GetProcAddress(ntdll, "RtlProtectHeap") orelse return false;
        rtl_protect_heap = @ptrFromInt(@intFromPtr(rtl_raw));
        cfg_target = pageAlignDown(list.FirstVEH);
        _ = rtl_protect_heap.?(cfg_target, asBOOL(false));
        cfg_unprotected = true;
    }

    list.FirstVEH.encoded_handler = EncodePointer(@ptrFromInt(@intFromPtr(handler)));
    std.debug.print("[+] overwrite: first VEH handler replaced\n", .{});
    return true;
}

fn seedHandler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    _ = info;
    std.debug.print("[SEED] pass-through\n", .{});
    return veh.EXCEPTION_CONTINUE_SEARCH;
}

fn manualHandler(info: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    if (info.ExceptionRecord.ExceptionCode != veh.EXCEPTION_INT_DIVIDE_BY_ZERO) {
        return veh.EXCEPTION_CONTINUE_SEARCH;
    }

    const old_rip = info.ContextRecord.Rip;
    info.ContextRecord.Rip += 2;
    std.debug.print("[MANUAL] div-by-zero Rip 0x{x} -> 0x{x}\n", .{ old_rip, info.ContextRecord.Rip });
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

pub fn main(init: std.process.Init) !void {
    const args = try init.minimal.args.toSlice(init.arena.allocator());

    var do_overwrite = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--overwrite")) {
            do_overwrite = true;
        } else {
            std.debug.print("[!] unknown arg: {s}\n", .{arg});
            return error.InvalidArgument;
        }
    }

    std.debug.print("05-local-veh-manip\n", .{});
    std.debug.print("==================\n", .{});

    var seed_handle: veh.PVOID = null;
    if (do_overwrite) {
        seed_handle = AddVectoredExceptionHandler(1, &seedHandler) orelse {
            std.debug.print("[!] failed to register seed VEH entry\n", .{});
            return error.SeedRegistrationFailed;
        };
        defer _ = RemoveVectoredExceptionHandler(seed_handle);
        std.debug.print("[i] --overwrite mode enabled\n", .{});
    }

    _ = addVectoredExceptionHandlerReplacement(!do_overwrite, &manualHandler) orelse {
        std.debug.print("[!] manual VEH registration failed\n", .{});
        return error.ManualRegistrationFailed;
    };

    if (do_overwrite and !overwriteFirstVectoredExceptionHandler(&manualHandler)) {
        std.debug.print("[!] overwrite path failed\n", .{});
        return error.OverwriteFailed;
    }

    std.debug.print("[*] triggering divide-by-zero...\n", .{});
    triggerDivByZero();
    std.debug.print("[ok] continued execution\n", .{});
}
