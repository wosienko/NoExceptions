---
layout: default
---

# Minimal Zig VEH

<<< @/../snippets/01-basic-veh/src/main.zig {20-41}

`AddVectoredExceptionHandler(1, …)` → trigger div-by-zero → `Rip += 2` → continue.

---
layout: default
---

# Live demo — `01-basic-veh`

```powershell
cd snippets/01-basic-veh
zig build run
```

Expected: handler prints exception code, Rip adjustment, `[ok] continued execution`.

<!-- capture output before talk -->

---
layout: default
---

# VEH chain order

```mermaid {scale: 0.8}
flowchart LR
    HEAD["LIST_HEAD<br/>.mrdata"] --> A["Handler A<br/>First=1"]
    A --> B["Handler B<br/>First=1"]
    B --> C["Handler C<br/>First=0"]
    C --> HEAD
```

Registration order with `First=1` prepends — **last registered runs first**.

Optional reference — `02-veh-chain`:

<<< @/../snippets/02-veh-chain/src/main.zig {20-38}
