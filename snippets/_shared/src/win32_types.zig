const veh = @import("veh_constants.zig");

pub const EXCEPTION_MAXIMUM_PARAMETERS = 15;

pub const EXCEPTION_RECORD = extern struct {
    ExceptionCode: veh.DWORD,
    ExceptionFlags: veh.DWORD,
    ExceptionRecord: ?*EXCEPTION_RECORD,
    ExceptionAddress: veh.PVOID,
    NumberParameters: veh.DWORD,
    ExceptionInformation: [EXCEPTION_MAXIMUM_PARAMETERS]usize,
};

/// x64 CONTEXT — only fields demos touch. Full struct must match Windows layout
/// through Rip (offset 0xF8). Pad before Rip to preserve offsets.
pub const CONTEXT = extern struct {
    _pad_before_rip: [0xF8]u8,
    Rip: u64,
    _after_rip: [0x3B0 - 0x100]u8, // through Dr0 at 0x3B0
    // Dr0–Dr7 live in debug register region; declare Dr0 at correct offset:
};

pub const CONTEXT_FULL = extern struct {
    P1Home: u64,
    P2Home: u64,
    P3Home: u64,
    P4Home: u64,
    P5Home: u64,
    P6Home: u64,
    ContextFlags: u32,
    MxCsr: u32,
    SegCs: u16,
    SegDs: u16,
    SegEs: u16,
    SegFs: u16,
    SegGs: u16,
    SegSs: u16,
    EFlags: u32,
    Dr0: u64,
    Dr1: u64,
    Dr2: u64,
    Dr3: u64,
    Dr6: u64,
    Dr7: u64,
    Rax: u64,
    Rcx: u64,
    Rdx: u64,
    Rbx: u64,
    Rsp: u64,
    Rbp: u64,
    Rsi: u64,
    Rdi: u64,
    R8: u64,
    R9: u64,
    R10: u64,
    R11: u64,
    R12: u64,
    R13: u64,
    R14: u64,
    R15: u64,
    Rip: u64,
    // remainder not needed for demos
    _rest: [512]u8,
};

pub const EXCEPTION_POINTERS = extern struct {
    ExceptionRecord: *EXCEPTION_RECORD,
    ContextRecord: *CONTEXT_FULL,
};

pub const PVECTORED_EXCEPTION_HANDLER =
    *const fn (*EXCEPTION_POINTERS) callconv(.winapi) veh.LONG;
