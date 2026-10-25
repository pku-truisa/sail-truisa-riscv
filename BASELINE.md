# Baseline

This fork tracks exactly one pinned upstream commit. This file is the
implementation-facing summary; the authoritative decision record is
**ADR-0025** in the TruISA architecture repository.

## 1. Coordinates

| Item | Value |
|---|---|
| Upstream | `CHERI-Alliance/sail-riscv` |
| Branch | `cheri-0.9.3` |
| Commit | `80a9e6514a87dd5031324ddfca31730ca739ceaf` |
| Commit subject | `Fix builds of tests on some platforms. (#1444)` |
| Re-verify | `git ls-remote --heads https://github.com/CHERI-Alliance/sail-riscv` |
| Structure | single repository, CHERI layer in `model/cheri/`, no submodules |

Reference points inside this repository:

| Ref | Purpose |
|---|---|
| `cheri-0.9.3` | **read-only** baseline; never commit here |
| `upstream-80a9e65` | tag on the same commit; immutable anchor |
| `truisa` | development branch |

## 2. Usability matrix

| Level | Criterion | Status |
|---|---|---|
| U1 buildable | CMake configure plus build, exit code 0 | **met** |
| U2 runnable | bundled `test/riscv-tests/rv64*.elf` all pass | **met** (229/229) |
| U3 CHERI executable | CHERI instructions decode and execute, fault path reachable | **met** (spot checks only) |
| U4 semantically correct | matches the 0.9.3 specification item by item | **NOT PROVEN** |

> **Coverage boundary of the 229/229 result.** Those tests all run on the
> base path with `CRE=0`, that is integer pointer mode. The CHERI checking
> path has **zero coverage**. That number must never be cited as CHERI
> acceptance evidence, only as proof that the commit is self-consistent for
> base RV64 instructions.

## 3. Build

Only the CMake entry point is usable.

```
cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DSAIL_BIN=<path-to-sail> -DDOWNLOAD_GMP=FALSE
cmake --build build --target sail_riscv_sim -j12
```

Artifact: `build/c_emulator/sail_riscv_sim`.

Known risk: `CMakeLists.txt` declares `SAIL_REQUIRED_VER 0.19.1`, while the
build was validated against Sail 0.20.3. It passes today only because the
version check is permissive. A stricter check upstream would break it.

## 4. Do not use the Makefile

The in-tree `Makefile` is stale and broken: it still references the removed
`model/riscv_xlen32.sail` and `model/riscv_xlen64.sail`, and it demands an
old Sail version. This is an upstream defect present on every merged branch.
Do not attempt to repair it locally, and do not use it as a health signal.

## 5. Tree map

| Item | Count |
|---|---|
| `model` tree, `.sail` files | 173 |
| `model/cheri/`, `.sail` files | 34 |
| actually compiled | 148, including 32 under `model/cheri/` |

Dead files, present in tree but not compiled:

- `model/riscv_sys_regs_seccfg.sail`
- `model/cheri/cheri_sys_regs_seccfg.sail`
- `model/cheri/test_main_ext.sail`

## 6. Known boundaries

1. **`tag=1` is unreachable from a plain ELF.** The only tagged sources are
   `PCC` and `ddc`, and there is no instruction that moves `ddc` into a `c`
   register. `SC` and `LC` require a tagged source, so the loop cannot be
   entered. Test scaffolding can only build tagged values indirectly.
2. **Trap entry stays in integer pointer mode.** The trap `PCC` is derived
   from the infinite capability, so a handler may perform integer loads and
   stores without switching mode first.
3. **`SCADDR` has no exception path.** It only clears the tag and never
   raises a CHERI fault. Do not assume this behaviour carries over to TruISA;
   the TruISA semantics require a separate decision.

## 7. Not part of the baseline

QEMU may be used as a behavioural cross-check only. It is **not** a source of
truth: its pointer-mode layer is known to be inconsistent, so whenever the two
disagree the Sail model wins.
