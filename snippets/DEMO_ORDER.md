# Live demo order (~30 min)

Run from repo root. Each snippet: `zig build run`.

## Foundations (~8 min)

| # | Directory | Required on stage | Notes |
|---|-----------|-------------------|-------|
| 01 | `01-basic-veh` | **yes** | Hero demo — divide-by-zero VEH |
| 02 | `02-veh-chain` | optional | Handler dispatch order |
| 03 | `03-veh-spy` | **yes** | EDR spy pattern |

```powershell
cd snippets/01-basic-veh; zig build run
cd ../03-veh-spy; zig build run
```

## Bypass approaches (~10 min)

| # | Directory | Required on stage | Notes |
|---|-----------|-------------------|-------|
| 04 | `04-lea-resolve` | **yes** | Quick — prints resolved ntdll globals |
| 05 | `05-local-veh-manip` | **yes** | Full LEA-track manual splice |
| 06 | `06-veh-probe` | optional | LIST_HEAD discovery only |
| 07 | `07-direct-splice` | **yes** | VEHicle RE-track direct splice |

```powershell
cd snippets/04-lea-resolve; zig build run
cd ../05-local-veh-manip; zig build run
cd ../07-direct-splice; zig build run
```

## Offensive (~5 min)

| # | Directory | Required on stage | Notes |
|---|-----------|-------------------|-------|
| 08 | `08-vectored-syscall` | **yes** | VEH-PoC — AV redirects to syscall stub |
| 09 | `09-hwbp-syscall` | **yes** | HWBP — single-step patches CONTEXT |

```powershell
cd snippets/08-vectored-syscall; zig build run
cd ../09-hwbp-syscall; zig build run
```

## Expected output (capture on presentation machine)

### 01-basic-veh
```
[VEH] caught 0xc0000094
[VEH] Rip 0x... -> 0x... (+2)
[ok] continued execution
```

### 03-veh-spy
```
[SPY] div-by-zero @ Rip=0x... (observed, passing through)
[REAL] fixed Rip -> 0x...
[ok] continued execution
```

### 04-lea-resolve
```
LdrpVectorHandlerList @ 0x...
LdrProtectMrdata      @ 0x...
```

### 05-local-veh-manip
```
[+] manual VEH entry @ 0x...
[MANUAL] div-by-zero Rip 0x... -> 0x...
[ok] continued execution
```

### 07-direct-splice
```
Spliced directly - no AddVectoredExceptionHandler for our handler.
[VEH] Rip 0x... -> 0x... (+2)
[ok] continued execution
```

### 08-vectored-syscall
```
[i] syscall stub @ 0x...
[i] NtAllocateVirtualMemory SSN = 0x...
[+] NtAllocateVirtualMemory status: 0x0
[i] BaseAddress: 0x...
[i] RegionSize: 0x...
[ok] vectored syscall redirection executed
```

### 09-hwbp-syscall
```
[VEH] Decoy SSN: ...
[VEH] Real  SSN: ...
[ok] decoy SSN replaced with resolved SSN
```
