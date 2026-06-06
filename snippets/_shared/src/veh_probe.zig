const veh = @import("veh_constants.zig");
const win32 = @import("win32_types.zig");
const structs = @import("veh_structs.zig");

pub const DirectVehHandle = struct {
    node: *structs.VECTORED_HANDLER_ENTRY,
    lock: *structs.SRWLOCK,
};

extern "kernel32" fn AddVectoredExceptionHandler(
    first: veh.ULONG,
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn RemoveVectoredExceptionHandler(handle: veh.PVOID) callconv(.winapi) veh.ULONG;
extern "kernel32" fn VirtualQuery(
    lp_address: *const anyopaque,
    lp_buffer: *structs.MEMORY_BASIC_INFORMATION,
    dw_length: usize,
) callconv(.winapi) usize;
extern "kernel32" fn VirtualProtect(
    lp_address: veh.PVOID,
    dw_size: usize,
    fl_new_protect: veh.DWORD,
    lpfl_old_protect: *veh.DWORD,
) callconv(.winapi) veh.BOOL;
extern "kernel32" fn GetProcessHeap() callconv(.winapi) veh.PVOID;
extern "kernel32" fn HeapAlloc(
    h_heap: veh.PVOID,
    dw_flags: veh.DWORD,
    dw_bytes: usize,
) callconv(.winapi) veh.PVOID;
extern "kernel32" fn HeapFree(
    h_heap: veh.PVOID,
    dw_flags: veh.DWORD,
    lp_mem: veh.PVOID,
) callconv(.winapi) veh.BOOL;
extern "kernel32" fn AcquireSRWLockExclusive(lock: *structs.SRWLOCK) callconv(.winapi) void;
extern "kernel32" fn ReleaseSRWLockExclusive(lock: *structs.SRWLOCK) callconv(.winapi) void;
extern "kernel32" fn EncodePointer(ptr: veh.PVOID) callconv(.winapi) veh.PVOID;

fn unprotectRange(addr: veh.PVOID, size: usize) !veh.DWORD {
    var old: veh.DWORD = 0;
    if (VirtualProtect(addr, size, veh.PAGE_READWRITE, &old) == 0) {
        return error.VirtualProtectFailed;
    }
    return old;
}

fn restoreProtection(addr: veh.PVOID, size: usize, old: veh.DWORD) void {
    var dummy: veh.DWORD = 0;
    _ = VirtualProtect(addr, size, old, &dummy);
}

pub fn vehProbeHandler(_: *win32.EXCEPTION_POINTERS) callconv(.winapi) veh.LONG {
    return veh.EXCEPTION_CONTINUE_SEARCH;
}

pub fn isInsideImage(addr: *const anyopaque) bool {
    var info: structs.MEMORY_BASIC_INFORMATION = undefined;
    if (VirtualQuery(addr, &info, @sizeOf(structs.MEMORY_BASIC_INFORMATION)) == 0) return false;
    return info.Type == veh.MEM_IMAGE;
}

pub fn findVehListHead(probe: *structs.LIST_ENTRY) ?*structs.LIST_ENTRY {
    var current = probe.Flink;
    var hops: usize = 0;
    while (current != probe and hops < 1024) : (hops += 1) {
        if (isInsideImage(@ptrCast(current))) return current;
        current = current.Flink;
    }
    return null;
}

pub fn installVectoredHandlerDirectly(
    handler: win32.PVECTORED_EXCEPTION_HANDLER,
) !DirectVehHandle {
    const probe = AddVectoredExceptionHandler(1, &vehProbeHandler) orelse
        return error.ProbeRegistrationFailed;
    const probe_entry: *structs.VECTORED_HANDLER_ENTRY = @ptrCast(@alignCast(probe));
    const list_head = findVehListHead(&probe_entry.list) orelse {
        _ = RemoveVectoredExceptionHandler(probe);
        return error.VehListHeadNotFound;
    };
    _ = RemoveVectoredExceptionHandler(probe);

    const lock: *structs.SRWLOCK =
        @ptrFromInt(@intFromPtr(list_head) - @sizeOf(structs.SRWLOCK));
    const protected_size = @sizeOf(structs.SRWLOCK) + @sizeOf(structs.LIST_ENTRY);
    const old_protect = try unprotectRange(@ptrCast(lock), protected_size);
    errdefer restoreProtection(@ptrCast(lock), protected_size, old_protect);

    const heap = GetProcessHeap() orelse return error.GetProcessHeapFailed;
    const node_raw = HeapAlloc(heap, 0, @sizeOf(structs.VECTORED_HANDLER_ENTRY)) orelse
        return error.NodeAllocationFailed;
    errdefer _ = HeapFree(heap, 0, node_raw);

    const refcount_raw = HeapAlloc(heap, 0, @sizeOf(u64)) orelse
        return error.RefcountAllocationFailed;
    errdefer _ = HeapFree(heap, 0, refcount_raw);

    const node: *structs.VECTORED_HANDLER_ENTRY = @ptrCast(@alignCast(node_raw));
    const refcount: *u64 = @ptrCast(@alignCast(refcount_raw));
    refcount.* = 1;

    node.refcount = refcount;
    node.removed = 0;
    node._reserved = 0;
    node.encoded_handler = EncodePointer(@ptrFromInt(@intFromPtr(handler)));

    AcquireSRWLockExclusive(lock);
    const old_first = list_head.Flink;
    node.list.Flink = old_first;
    node.list.Blink = list_head;
    old_first.Blink = &node.list;
    list_head.Flink = &node.list;
    ReleaseSRWLockExclusive(lock);

    restoreProtection(@ptrCast(lock), protected_size, old_protect);
    return .{ .node = node, .lock = lock };
}

pub fn removeVectoredHandlerDirectly(h: DirectVehHandle) void {
    const node = h.node;
    const lock = h.lock;

    const protected_size = @sizeOf(structs.SRWLOCK) + @sizeOf(structs.LIST_ENTRY);
    const old_protect = unprotectRange(@ptrCast(lock), protected_size) catch return;
    defer restoreProtection(@ptrCast(lock), protected_size, old_protect);

    AcquireSRWLockExclusive(lock);
    const flink = node.list.Flink;
    const blink = node.list.Blink;
    flink.Blink = blink;
    blink.Flink = flink;
    ReleaseSRWLockExclusive(lock);

    const heap = GetProcessHeap() orelse return;
    _ = HeapFree(heap, 0, @ptrCast(node.refcount));
    _ = HeapFree(heap, 0, @ptrCast(node));
}
