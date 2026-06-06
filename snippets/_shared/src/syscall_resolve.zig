const std = @import("std");

const IMAGE_DOS_SIGNATURE: u16 = 0x5A4D;
const IMAGE_NT_SIGNATURE: u32 = 0x0000_4550;
const IMAGE_NT_OPTIONAL_HDR32_MAGIC: u16 = 0x010B;
const IMAGE_NT_OPTIONAL_HDR64_MAGIC: u16 = 0x020B;
const IMAGE_DIRECTORY_ENTRY_EXPORT: usize = 0;

const IMAGE_EXPORT_DIRECTORY = extern struct {
    Characteristics: u32,
    TimeDateStamp: u32,
    MajorVersion: u16,
    MinorVersion: u16,
    Name: u32,
    Base: u32,
    NumberOfFunctions: u32,
    NumberOfNames: u32,
    AddressOfFunctions: u32,
    AddressOfNames: u32,
    AddressOfNameOrdinals: u32,
};

const ZwExport = struct {
    name: []const u8,
    address: usize,
};

pub const ResolveError = error{
    InvalidPeImage,
    ExportDirectoryMissing,
    TargetNotFound,
    TooManyZwExports,
};

pub fn findSyscallStub(ntdll: ?*anyopaque) ?usize {
    const base = moduleBase(ntdll) orelse return null;
    const view = parseExportView(base) catch return null;

    for (0..view.export_dir.NumberOfNames) |i| {
        const name = readAsciiZ(base + view.name_rvas[i]) orelse continue;
        if (!std.mem.startsWith(u8, name, "Zw") and !std.mem.startsWith(u8, name, "Nt")) {
            continue;
        }

        const ordinal = @as(usize, view.name_ordinals[i]);
        if (ordinal >= view.func_rvas.len) continue;

        const fn_addr = base + view.func_rvas[ordinal];
        if (scanForSyscallRet(fn_addr, 0x40)) |stub| return stub;
    }

    return null;
}

pub fn resolveSsnByName(ntdll: ?*anyopaque, raw_name: []const u8) ResolveError!u32 {
    const base = moduleBase(ntdll) orelse return error.InvalidPeImage;
    const view = try parseExportView(base);

    var normalized_name_buf: [64]u8 = undefined;
    const target_name = normalizeZwName(raw_name, &normalized_name_buf) orelse {
        return error.TargetNotFound;
    };

    var exports: [2048]ZwExport = undefined;
    var zw_count: usize = 0;

    for (0..view.export_dir.NumberOfNames) |i| {
        const name = readAsciiZ(base + view.name_rvas[i]) orelse continue;
        if (!std.mem.startsWith(u8, name, "Zw")) continue;

        const ordinal = @as(usize, view.name_ordinals[i]);
        if (ordinal >= view.func_rvas.len) continue;

        if (zw_count >= exports.len) return error.TooManyZwExports;
        exports[zw_count] = .{
            .name = name,
            .address = base + view.func_rvas[ordinal],
        };
        zw_count += 1;
    }

    if (zw_count == 0) return error.TargetNotFound;

    var i: usize = 0;
    while (i < zw_count) : (i += 1) {
        var j: usize = i + 1;
        while (j < zw_count) : (j += 1) {
            if (exports[j].address < exports[i].address) {
                const tmp = exports[i];
                exports[i] = exports[j];
                exports[j] = tmp;
            }
        }
    }

    for (exports[0..zw_count], 0..) |entry, ssn| {
        if (std.mem.eql(u8, entry.name, target_name)) {
            return @intCast(ssn);
        }
    }

    return error.TargetNotFound;
}

const ExportView = struct {
    export_dir: *align(1) const IMAGE_EXPORT_DIRECTORY,
    name_rvas: []align(1) const u32,
    func_rvas: []align(1) const u32,
    name_ordinals: []align(1) const u16,
};

fn parseExportView(base: usize) ResolveError!ExportView {
    if (readU16(base) != IMAGE_DOS_SIGNATURE) return error.InvalidPeImage;

    const e_lfanew = readU32(base + 0x3C);
    const nt = base + e_lfanew;
    if (readU32(nt) != IMAGE_NT_SIGNATURE) return error.InvalidPeImage;

    const optional_header = nt + 0x18;
    const optional_magic = readU16(optional_header);
    const data_directory_offset: usize = switch (optional_magic) {
        IMAGE_NT_OPTIONAL_HDR64_MAGIC => 0x70,
        IMAGE_NT_OPTIONAL_HDR32_MAGIC => 0x60,
        else => return error.InvalidPeImage,
    };

    const export_entry = optional_header + data_directory_offset + (IMAGE_DIRECTORY_ENTRY_EXPORT * 8);
    const export_rva = readU32(export_entry);
    const export_size = readU32(export_entry + 4);
    if (export_rva == 0 or export_size == 0) return error.ExportDirectoryMissing;

    const export_dir: *align(1) const IMAGE_EXPORT_DIRECTORY = @ptrFromInt(base + export_rva);
    if (export_dir.NumberOfNames == 0 or export_dir.NumberOfFunctions == 0) {
        return error.ExportDirectoryMissing;
    }
    if (export_dir.AddressOfNames == 0 or export_dir.AddressOfFunctions == 0 or export_dir.AddressOfNameOrdinals == 0) {
        return error.ExportDirectoryMissing;
    }

    return .{
        .export_dir = export_dir,
        .name_rvas = @as([*]align(1) const u32, @ptrFromInt(base + export_dir.AddressOfNames))[0..export_dir.NumberOfNames],
        .func_rvas = @as([*]align(1) const u32, @ptrFromInt(base + export_dir.AddressOfFunctions))[0..export_dir.NumberOfFunctions],
        .name_ordinals = @as([*]align(1) const u16, @ptrFromInt(base + export_dir.AddressOfNameOrdinals))[0..export_dir.NumberOfNames],
    };
}

fn normalizeZwName(name: []const u8, buf: *[64]u8) ?[]const u8 {
    if (name.len < 3 or name.len > buf.len) return null;

    if (std.mem.startsWith(u8, name, "Zw")) {
        return name;
    }

    if (!std.mem.startsWith(u8, name, "Nt")) {
        return null;
    }

    @memcpy(buf[0..name.len], name);
    buf[0] = 'Z';
    buf[1] = 'w';
    return buf[0..name.len];
}

fn scanForSyscallRet(addr: usize, max_scan: usize) ?usize {
    var i: usize = 0;
    while (i + 2 < max_scan) : (i += 1) {
        if (readU8(addr + i) == 0x0F and readU8(addr + i + 1) == 0x05 and readU8(addr + i + 2) == 0xC3) {
            return addr + i;
        }
    }
    return null;
}

fn moduleBase(module: ?*anyopaque) ?usize {
    const ptr = module orelse return null;
    return @intFromPtr(ptr);
}

fn readAsciiZ(addr: usize) ?[]const u8 {
    const ptr: [*:0]const u8 = @ptrFromInt(addr);
    return std.mem.span(ptr);
}

fn readU8(addr: usize) u8 {
    return @as(*align(1) const u8, @ptrFromInt(addr)).*;
}

fn readU16(addr: usize) u16 {
    return @as(*align(1) const u16, @ptrFromInt(addr)).*;
}

fn readU32(addr: usize) u32 {
    return @as(*align(1) const u32, @ptrFromInt(addr)).*;
}
