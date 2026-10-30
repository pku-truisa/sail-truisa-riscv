# M2 test bench -- hand-built ELFs, no toolchain

`mkelf.py` writes four ELF64 files that the TruISA emulator can load. There is no
assembler and no linker involved: the code sections are raw 32-bit words, and the
container (program headers, section headers, a minimal `.symtab`) is laid out by the
script. See the module docstring for the exact loader requirements, which were read out of
`~/.opam/*/share/sail/lib/elf.c` rather than assumed.

## Run

**One command for the whole regression** (D-173: this is what the baseline means by
"`M2` still holds"):

```sh
MODEL_SHA=$(git rev-parse --short HEAD) ./test/m2/run.sh
./test/m2/run.sh --csv docs/test/runs/<date>-<sha>-v<N>.csv    # archive a record
```

⚠️ Record naming is `<date>-<model@sha>-v<N>.csv`, where `N` is the **case-set version**
(`D-182` ruling 2). Adding/removing a case bumps `N`; changing an expectation does not.
The current version lives in one place only: `docs/test/plan/README.md`.

`run.sh` builds the ELFs, runs each case without `--inst-limit` (L1 trap 6: a
truncated run prints `rc=0` and hides a dead HTIF), compares the signature against
`expect.csv`, and writes `case,rc,trap,signature,expect,pass` to
`build/m2-run/m2.csv`. Exit codes: `0` all pass, `1` a case failed, `2` environment
problem (mostly: no emulator built).

## Cases

| case | what it proves | source of the expectation |
|---|---|---|
| `container` | L1 only: ELF loads, HTIF prints its address, `tohost` write ends the run by itself | `m2-baseline.md` §4 judgements 2–3 (no signature criterion, `-`) |
| `u1` | `CADD` +8 inside the slot; tag stays `0x4C`, `pac` unchanged | `m2-baseline.md` §3 |
| `u2` | `SCADDR` to the slot top then `CADD` past it ⇒ poisoned `0111111`, silent, no trap | `m2-baseline.md` §3 |
| `u3` | `CADD` on a Bare operand derives across the whole address space | `m2-baseline.md` §3 |
| `u4` | the `pac` invariant across `CADD`: two encodings, same `bits 63..48`, `bits 47..0` +8 | `D-176` §4 (judgement 5) |

⚠️ `u4` is the only case that needs **two** signature words (the criterion is a relation
between two points, so one word cannot carry it). `expect.csv` expresses that with a `/`
between fields and `run.sh` reads exactly `words` 8-byte words from the signature area.
The six CSV columns do not change.

⚠️ **`phase` column.** `u1` and `u4` carry `phase=A`: their expected *absolute* values
contain `pac`, which is produced by `signPtr` and includes `salt`. In phase A `salt` is
zeros so the values are stable; **in phase B they will change** and a pinned absolute would
turn the suite red while the model is fine. `D-182` ruling 3: the *relation* is the
criterion (long-lived), the absolute is a phase-A guard. `run.sh` prints a warning listing
every `phase=A` case on each run, so clearing that list is the "ready for phase B" check.
⚠️ `D-182` only named `u4`, but `u1` has the same property (`0x98C8…` contains `pac=0xC8`).

⚠️ `u4`'s first expectation was **wrong, and it was our mistake**: we pinned
`0x…0008 / 0x…0010`, i.e. we mistook U1's post-`CADD` address for the pre-`CADD` snapshot.
`D-176` §4 puts that snapshot after `scbnds` and before `cadd`, so the address is still the
slot base. `expect.csv` records the old value, why it was wrong, and the trace lines that
show it -- the criterion (`bits 63..48` equal, `bits 47..0` +8) never moved.

Manual single-case invocation, if that is what you want:

```sh
python3 mkelf.py .                     # writes container.elf u1.elf u2.elf u3.elf u4.elf
./build/c_emulator/sail_riscv_sim -T sig.txt -g 8 u1.elf
```

`container.elf` is the self-test of the container: it writes 1 to `tohost` and the
emulator must print `SUCCESS` and exit 0 without `--inst-limit`.

⚠️ `expect.csv` holds a **copy** of the expected signatures. The criteria themselves live
in the architecture repo (`docs/test/m2-baseline.md` §3/§4) and are maintained by the
architecture group only: a changed expectation is a changed criterion, and tuning
`expect.csv` until it goes green is exactly the failure mode that splitting this group
out was meant to prevent.

## Measured results (2026-10-30, model d08c4b3 + D-13/D-168 fixes)

| program | signature word | reading |
|---|---|---|
| `container` | `0x0000000000000000` | no store to the signature area; the point is `SUCCESS` + rc=0 |
| `u1` | `0x98C8000080000008` | Aligned, tag `0x4C` = mode 1 / N 12, address `0x8000_0008`, `pac = 0xC8` |
| `u2` | `0x7E00000000000000` | poisoned: tag bits 63..57 = `0111111`, silent (no trap) |
| `u3` | `0x0000000080000008` | Bare: tag `0000000`, address `0x8000_0008`, no trap |

↑ This table is a **historical measurement** taken by the development group, kept as-is
(it was not re-measured at commit `23ac92c`). For the current run, read
`docs/test/runs/<date>-<sha>.csv` in the architecture repo -- that CSV is produced by
`run.sh` and is the only place a pass/fail claim belongs.

Independently re-measured by the test group on 2026-10-30 from `origin/truisa@23ac92c`
(own worktree, own build): all four signature words **identical to the table above**
(`docs/test/runs/2026-10-30-23ac92c.csv`). The binary differs in size from the one
recorded in `docs/test/m2-baseline.md` (19,277,200 B vs 19,276,368 B) while the
signatures do not -- so binary size is not a reproducibility signal worth tracking.

⚠️ `0x98C8` is the *metadata half*, not a constant anyone should hard-code: tag `0x4C` is
predicted by ADR-0003's field layout, the `0xC8` in the `pac` slot is whatever
`makeCapAligned` produced on this build. Recorded, not justified -- do not tune it.

## Address constants

`lui` cannot produce `0x8000_0000` on RV64 (it sign-extends: `lui x1, 0x80000` gives
`0xFFFFFFFF80000000`), and `auipc` only lands on the right page when the instruction sits
at the start of that page. `li_addr()` therefore builds every absolute address as
`lui` + `slli 32` + `srli 32`, which is position independent and leaves bits 63..57 zero.
