# M2 test bench -- hand-built ELFs, no toolchain

`mkelf.py` writes four ELF64 files that the TruISA emulator can load. There is no
assembler and no linker involved: the code sections are raw 32-bit words, and the
container (program headers, section headers, a minimal `.symtab`) is laid out by the
script. See the module docstring for the exact loader requirements, which were read out of
`~/.opam/*/share/sail/lib/elf.c` rather than assumed.

## Run

```sh
python3 mkelf.py .                     # writes container.elf u1.elf u2.elf u3.elf
./build/c_emulator/sail_riscv_sim -T sig.txt -g 8 u1.elf
```

`container.elf` is the self-test of the container: it writes 1 to `tohost` and the
emulator must print `SUCCESS` and exit 0 without `--inst-limit`.

## Measured results (2026-10-30, model d08c4b3 + D-13/D-168 fixes)

| program | signature word | reading |
|---|---|---|
| `container` | `0x0000000000000000` | no store to the signature area; the point is `SUCCESS` + rc=0 |
| `u1` | `0x98C8000080000008` | Aligned, tag `0x4C` = mode 1 / N 12, address `0x8000_0008`, `pac = 0xC8` |
| `u2` | `0x7E00000000000000` | poisoned: tag bits 63..57 = `0111111`, silent (no trap) |
| `u3` | `0x0000000080000008` | Bare: tag `0000000`, address `0x8000_0008`, no trap |

⚠️ `0x98C8` is the *metadata half*, not a constant anyone should hard-code: tag `0x4C` is
predicted by ADR-0003's field layout, the `0xC8` in the `pac` slot is whatever
`makeCapAligned` produced on this build. Recorded, not justified -- do not tune it.

## Address constants

`lui` cannot produce `0x8000_0000` on RV64 (it sign-extends: `lui x1, 0x80000` gives
`0xFFFFFFFF80000000`), and `auipc` only lands on the right page when the instruction sits
at the start of that page. `li_addr()` therefore builds every absolute address as
`lui` + `slli 32` + `srli 32`, which is position independent and leaves bits 63..57 zero.
