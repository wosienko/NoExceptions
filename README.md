# No Exceptions — Vectored Exception Handling

A practitioner-focused presentation on Windows **Vectored Exception Handling (VEH)** — what it is, how to register handlers, and a couple of sample applications (EDR-style spy, vectored syscall, hardware-breakpoint syscall tampering). The repo includes a Slidev deck and five runnable Zig demos.

**Audience:** security practitioners (EDR / offensive tooling)
**Duration:** ~30 minutes (slides + live terminal demos)

## What's in this repo

| Path                     | Description                                                      |
| ------------------------ | ---------------------------------------------------------------- |
| [`slides/`](slides/)     | Slidev presentation — modular pages under `pages/`               |
| [`snippets/`](snippets/) | Five Zig 0.16 demo projects, each buildable with `zig build run` |

Foundational demos use **divide-by-zero** (`EXCEPTION_INT_DIVIDE_BY_ZERO`, advance `Rip`, `EXCEPTION_CONTINUE_EXECUTION`) for clarity.

## Prerequisites

- **Windows x64** — snippets and demos target Windows only
- **[Zig 0.16](https://ziglang.org/)** — for all projects under `snippets/`
- **Node.js + pnpm** — for the Slidev deck in `slides/`

## Running the slides

```powershell
cd slides
pnpm install
pnpm run dev
```

Open [http://localhost:3030](http://localhost:3030). To build a static export:

```powershell
pnpm run build
```

Slide content is split across `slides/pages/` (`01-intro.md` through `05-offensive.md`), imported from [`slides/slides.md`](slides/slides.md).

## Running the demos

From any snippet directory:

```powershell
cd snippets/01-basic-veh
zig build run
```

All snippets share Win32/VEH helpers from [`snippets/_shared/`](snippets/_shared/).

### Snippet overview

| #   | Directory             | Topic                                                |
| --- | --------------------- | ---------------------------------------------------- |
| 01  | `01-basic-veh`        | Basic VEH handler — divide-by-zero, advance `Rip`    |
| 02  | `02-veh-chain`        | Handler dispatch order                               |
| 03  | `03-veh-spy`          | EDR-style spy handler (observe, pass through)        |
| 04  | `04-vectored-syscall` | VEH-PoC-style AV → syscall stub redirection          |
| 05  | `05-hwbp-syscall`     | Hardware breakpoint single-step CONTEXT patch        |

For live-demo order and expected output, see [`snippets/DEMO_ORDER.md`](snippets/DEMO_ORDER.md).

## Presentation flow (high level)

1. **Intro** — Windows EH stack, KTRAPs, `CONTEXT`
2. **VEH basics** — registration, dispatch, handler return values
3. **Zig demos** — foundations (`01`–`02`)
4. **EDR problem** — why VEH matters for in-process monitoring (`03`)
5. **Sample applications** — vectored and HWBP syscall tricks (`04`–`05`)

## Disclaimer

This material is for **authorized security research and education** only. Techniques described here may be detected or blocked by modern EDR/AV products. Use only in environments where you have explicit permission.

---

**Note:** AI was used to generate the presentation (slides) and some code snippets in this repository.
