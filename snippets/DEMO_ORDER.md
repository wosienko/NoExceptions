# Live demo order (~30 min)

Run from repo root. Each snippet: `zig build run`.

## Foundations (~10 min)

| # | Directory | Required on stage | Notes |
|---|-----------|-------------------|-------|
| 01 | `01-basic-veh` | **yes** | Hero demo — divide-by-zero VEH |
| 02 | `02-veh-chain` | optional | Handler dispatch order |
| 03 | `03-veh-spy` | **yes** | EDR spy pattern |

```powershell
cd snippets/01-basic-veh; zig build run
cd ../02-veh-chain; zig build run
cd ../03-veh-spy; zig build run
```

## Sample applications (~10 min)

| # | Directory | Required on stage | Notes |
|---|-----------|-------------------|-------|
| 04 | `04-vectored-syscall` | **yes** | VEH-PoC — AV redirects to syscall stub |
| 05 | `05-hwbp-syscall` | **yes** | HWBP — single-step patches CONTEXT |

```powershell
cd snippets/04-vectored-syscall; zig build run
cd ../05-hwbp-syscall; zig build run
```

## Expected output (capture on presentation machine)

### 01-basic-veh
```
[VEH] caught 0xc0000094
[VEH] Rip 0x... -> 0x... (+2)
[ok] continued execution
```

### 02-veh-chain
```
[handler-B] code=0xc0000094 -> EXECUTION
[handler-A] code=0xc0000094 -> SEARCH
[ok] continued execution
```

### 03-veh-spy
```
[SPY] div-by-zero @ Rip=0x... (observed, passing through)
[REAL] fixed Rip -> 0x...
[ok] continued execution
```

### 04-vectored-syscall
```
[i] syscall stub @ 0x...
[i] NtAllocateVirtualMemory SSN = 0x...
[+] NtAllocateVirtualMemory status: 0x0
[i] BaseAddress: 0x...
[i] RegionSize: 0x...
[ok] vectored syscall redirection executed
```

### 05-hwbp-syscall
```
[VEH] Decoy SSN: ...
[VEH] Real  SSN: ...
[ok] decoy SSN replaced with resolved SSN
```
