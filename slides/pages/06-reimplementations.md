---
layout: default
---

# Bypass track A — LEA resolve

Byte-scan `ntdll` exports for `LEA`/`CALL` patterns — no registration API calls.

- Anchor: `RtlRemoveVectoredExceptionHandler`
- Pattern `0x258d4c` (`lea r13, [rip+disp]`) → `LdrpVectorHandlerList`
- Also resolve `LdrProtectMrdata`, `LdrpMrdataHeap`, `LdrEnsureMrdataHeapExists`

---
layout: default
---

# LEA resolve — `04-lea-resolve`

<<< @/../snippets/04-lea-resolve/src/main.zig {10-29}

```powershell
cd snippets/04-lea-resolve
zig build run
```

<!-- capture output before talk -->

---
layout: default
---

# LEA track — manual splice (`05-local-veh-manip`)

CFG-aware path: mrdata heap alloc → `EncodePointer` → SRW lock → list splice → `FlipBit(PROCESS_USING_VEH)`.

---
layout: default
zoom: 0.85
---

# Manual splice — lock + list insert

<<< @/../snippets/05-local-veh-manip/src/main.zig {121-160}

```powershell
cd snippets/05-local-veh-manip
zig build run
```

<!-- capture output before talk -->

---
layout: default
---

# Bypass track B — RE probe (VEHicle)

Understand `RtlpAddVectoredHandler` from RE; discover `LIST_HEAD` at runtime:

1. Register probe handler via API (once)
2. Walk `Flink` from probe node
3. `VirtualQuery` — find node in `MEM_IMAGE` region → that's the list head
4. Direct splice bypasses hooked registration APIs

```powershell
cd snippets/06-veh-probe
zig build run
```

<!-- capture output before talk -->

---
layout: default
---

# RE track — direct splice (`07-direct-splice`)

Probe discovery → build 0x28 node → `VirtualProtect` + SRW splice → div-by-zero proof.

```powershell
cd snippets/07-direct-splice
zig build run
```

<!-- capture output before talk -->

---
layout: default
---

# LEA vs RE probe

| | LEA (Local) | RE probe (VEHicle) |
|---|---|---|
| Finds globals | Signature scan in ntdll | Probe walk, no hardcoded offsets |
| API calls for install | None | Probe uses API once, splice bypasses hooks |
| CFG fidelity | Full (mrdata heap) | Pragmatic (`VirtualProtect`, process heap) |
| Breaks on | ntdll pattern change | Hook that fakes probe node layout (rare) |
