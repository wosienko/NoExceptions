---
layout: default
---

# Export surface

`kernel32!AddVectoredExceptionHandler` → `ntdll!RtlAddVectoredExceptionHandler`

```asm
; ntdll!RtlAddVectoredExceptionHandler
xor     r8d, r8d          ; a3 = 0 → VEH (not VCH)
jmp     RtlpAddVectoredHandler
```

Three instructions — all work happens in `RtlpAddVectoredHandler`.

---
layout: default
zoom: 0.95
---

# `RtlpAddVectoredHandler` flow

1. `LdrEnsureMrdataHeapExists()` — prepare CFG heap if needed
2. Allocate **0x28** byte node on `LdrpMrdataHeap` (CFG) or process heap
3. Allocate refcount (`*v11 = 1`), `EncodePointer(handler)` at `+0x20`
4. `LdrProtectMrdata(0)` — unprotect `.mrdata` list head
5. `RtlAcquireSRWLockExclusive(LockVEH)`
6. Splice into circular list — `First=1` prepends, `First=0` appends
7. Set `PROCESS_USING_VEH` PEB bit if list was empty
8. `LdrProtectMrdata(1)` — re-protect, release lock

---
layout: default
---

# `VECTORED_HANDLER_ENTRY` (0x28)

| Offset | Field |
|--------|-------|
| `+0x00` | `LIST_ENTRY` (`Flink`, `Blink`) |
| `+0x10` | `refcount` (pointer to u64) |
| `+0x18` | `removed` (u32) |
| `+0x1C` | `_reserved` (u32) |
| `+0x20` | `encoded_handler` (`EncodePointer`) |

Nodes live on private heap; **LIST_HEAD** lives in `.mrdata` (`MEM_IMAGE`).

---
layout: default
---

# `LdrpVectorHandlerList`

```c
typedef struct _VECTORED_HANDLER_LIST {
    PVOID                   LockVEH;      // SRWLOCK
    VECTORED_HANDLER_ENTRY* FirstVEH;
    VECTORED_HANDLER_ENTRY* LastVEH;
    PVOID                   LockVCH;
    VECTORED_HANDLER_ENTRY* FirstVCH;
    VECTORED_HANDLER_ENTRY* LastVCH;
} VECTORED_HANDLER_LIST;
```

VEH and VCH share layout — separate sub-lists, separate locks. `FirstVEH` / `LastVEH` are **pointers into the circular list**, not raw `LIST_ENTRY` heads.

---
layout: default
---

# CFG / `.mrdata` protection

- `LdrProtectMrdata(BOOL)` toggles write access to `.mrdata` (handler list heads)
- `LdrpMrdataHeap` — dedicated heap for CFG-compatible handler nodes
- Direct list splice requires: unlock SRW → unprotect mrdata → patch links → protect → lock

<div class="text-sm opacity-70 mt-8">

**Footnote — lazy page commit:** VEH can also handle `EXCEPTION_ACCESS_VIOLATION` on guard pages for JIT/GC lazy commit. Not demonstrated here; div-by-zero is the teaching fault throughout Part 1.

</div>
