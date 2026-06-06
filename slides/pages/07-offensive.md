---
layout: default
---

# Vectored syscalls (VEH-PoC)

Call `Nt*` with **syscall number as function pointer** → guaranteed `EXCEPTION_ACCESS_VIOLATION`.

```mermaid {scale: 0.8}
flowchart LR
    A["call ptr=SSN"] --> B[AV at Rip]
    B --> C["VEH: R10=RCX, Rax=SSN"]
    C --> D["Rip = syscall stub"]
    D --> E[Real syscall executes]
```

Handler rewires `CONTEXT` — no inline hook on `ntdll` export.

---
layout: default
---

# Vectored syscall — `08-vectored-syscall`

<<< @/../snippets/08-vectored-syscall/src/main.zig {23-56}

```powershell
cd snippets/08-vectored-syscall
zig build run
```

Benign `NtClose` only — SSN resolved dynamically, no shellcode.

<!-- capture output before talk -->

---
layout: default
---

# Tampered syscalls (HWBP)

`STATUS_SINGLE_STEP` at `Dr0` on a **decoy** `Nt*` stub's `syscall` instruction.

```mermaid {scale: 0.8}
flowchart LR
    A[Call decoy Nt API] --> B[HWBP fires]
    B --> C["VEH: swap SSN + args"]
    C --> D[Clear Dr0, resume]
    D --> E[Real syscall runs]
```

Decoy SSN in `Rax` — VEH patches real SSN and Win64 args before kernel entry.

---
layout: default
---

# HWBP syscall — `09-hwbp-syscall`

<<< @/../snippets/09-hwbp-syscall/src/main.zig {109-195}

```powershell
cd snippets/09-hwbp-syscall
zig build run
```

Benign `NtAllocateVirtualMemory` — small RW allocation, no payload execution.

<!-- capture output before talk -->

---
layout: default
---

# AV-triggered vs HWBP-triggered

| | Vectored syscall (AV) | HWBP tamper (single-step) |
|---|---|---|
| Trigger | `EXCEPTION_ACCESS_VIOLATION` | `STATUS_SINGLE_STEP` at `Dr0` |
| Setup | VEH only | VEH + debug registers (`Dr0`/`Dr7`) |
| Target insn | Any invalid `Rip` (SSN as ptr) | `syscall` in decoy stub |
| Stealth | Obvious AV on every call | Looks like normal export call until HWBP |
| Detection | AV storm, unmapped Rip | Debug register monitoring |

Both tamper `CONTEXT` inside VEH — different trigger, same resume primitive.
