pub const LIST_ENTRY = extern struct {
    Flink: *LIST_ENTRY,
    Blink: *LIST_ENTRY,
};

pub const SRWLOCK = extern struct {
    Ptr: ?*anyopaque,
};

/// 0x28-byte node — matches RtlpAddVectoredHandler allocation.
pub const VECTORED_HANDLER_ENTRY = extern struct {
    list: LIST_ENTRY,
    refcount: *u64,
    removed: u32,
    _reserved: u32,
    encoded_handler: ?*anyopaque,
};

/// Local-VEH-Manipulation layout (VEH + VCH sub-lists).
pub const VECTORED_HANDLER_LIST = extern struct {
    LockVEH: *SRWLOCK,
    FirstVEH: *VECTORED_HANDLER_ENTRY,
    LastVEH: *VECTORED_HANDLER_ENTRY,
    LockVCH: *SRWLOCK,
    FirstVCH: *VECTORED_HANDLER_ENTRY,
    LastVCH: *VECTORED_HANDLER_ENTRY,
};

pub const MEMORY_BASIC_INFORMATION = extern struct {
    BaseAddress: ?*anyopaque,
    AllocationBase: ?*anyopaque,
    AllocationProtect: u32,
    PartitionId: u16,
    _reserved: u16,
    RegionSize: usize,
    State: u32,
    Protect: u32,
    Type: u32,
};
