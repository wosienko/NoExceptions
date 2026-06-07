pub const DWORD = u32;
pub const ULONG = u32;
pub const LONG = i32;
pub const BOOL = c_int;
pub const PVOID = ?*anyopaque;
pub const NTSTATUS = i32;

pub const EXCEPTION_INT_DIVIDE_BY_ZERO: DWORD = 0xC0000094;
pub const EXCEPTION_ACCESS_VIOLATION: DWORD = 0xC0000005;
pub const STATUS_SINGLE_STEP: DWORD = 0x80000004;

pub const EXCEPTION_CONTINUE_SEARCH: LONG = 0;
pub const EXCEPTION_CONTINUE_EXECUTION: LONG = -1;
pub const EXCEPTION_EXECUTE_HANDLER: LONG = 1;

pub const NT_SUCCESS = struct {
    pub fn ok(status: NTSTATUS) bool {
        return status >= 0;
    }
}.ok;
