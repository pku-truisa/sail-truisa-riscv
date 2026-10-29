# Code Style

This document is an incomplete description of the predominant style used in the
RISC-V Sail model.
Where something is not specified, please look for existing code similar to what
is being added and copy the predominant style.

For C the formatting rules should be followed where applicable.
For other languages, follow the standard style for that language if it exists;
for example, Python should follow the standard PEP-8 style.

## Formatting

- Block-level indentation uses two spaces

- Tabs should not be used

- There should be no trailing spaces on any lines

- All files should end with a newline character

- Unix-style line endings should be used

- Files should be free from leading, trailing and double blank lines

- There should be one space either side of operators such as `=` and `+`

- There should be no spaces before and one space after `,`

- There should be one space after control flow keywords such as `if`, `foreach`
  and `match`

- There should be no spaces between a function name and its arguments, for both
  definitions (valspecs, function definitions and function clauses) and calls,
  nor should there be any spaces immediately within the parentheses

- There should be no spaces between a vector and the opening square bracket for
  indexing or slicing, nor should there be any spaces immediately within the
  square brackets

- For large blocks of code with repetitive structure where it improves
  readability, additional whitespace may be inserted to align corresponding
  elements horizontally with each other, within reason

- Avoid unnecessary parentheses and curly braces unless doing so seriously
  hurts readability

- When modifying existing code that does not conform to this style, prefer
  matching the existing style

- Files should have suitable copyright headers.

- Some mapping clauses, especially for instruction decoding (`encdec`)
  clauses, can be quite long. Unless these clauses appear in a group
  (see below), conditional mapping clauses should use the `when`
  construct if both sides of the mapping are conditioned on the same
  predicate expression; the two sides of the mapping and the `when`
  should be on separate lines.

```
mapping clause encdec = LOAD(imm, rs1, rd, is_unsigned, size, false, false)
  <-> imm @ encdec_reg(rs1) @ bool_bits(is_unsigned) @ size_enc(size) @ encdec_reg(rd) @ 0b0000011
  when (size_bytes(size) < xlen_bytes) | (not(is_unsigned) & size_bytes(size) <= xlen_bytes)
```

If these mapping clauses appear in a group (e.g., see `SHIFTIOP`),
they should preferably be each on a single line, with their
corresponding elements vertically aligned.

## Implementation

### Fork rule: TruISA never links a `cheri_*` file

TruISA is a **fork** of the CHERI model, not an extension layered on top of it.
A single shared source file is enough to make the fork unverifiable: at that
point neither model can be checked on its own.

1. **A build of `model/truisa/` must not include any `model/cheri/*.sail`.**
   Not even "just for the types". If something is needed, it gets its own copy.

2. **Need something a `cheri_*` file has? Copy it, rename it, then edit it.**
   `cheri_X.sail` -> `truisa_X.sail`, keeping the original block order so the
   two files can be diffed block by block. Mark every change with a
   `// TRUISA DELTA:` line naming the ADR that forces it.

3. **Keep CHERI's file split.** The split is load-bearing, not cosmetic:
   - `bits()` / `range()` / `Int` types  -> `*_cap_common.sail`
   - `enum` / `struct` (abstract)        -> `*_types.sail`
   - the one exception is `Capability`, which is a struct but stays in
     `*_cap_common.sail` because it *is* the pointer geometry.
   Do not merge two CHERI files into one TruISA file, and do not move a block
   to another file "because it fits better there".

4. **An upstream `riscv_*` / `prelude_*` file that already does the right thing
   is used as-is** -- it gets no `truisa_*` twin. (Example:
   `prelude_mem_metadata.sail` is already the no-metadata version TruISA needs.)

5. **A genuinely new file -- one with no CHERI counterpart -- needs a decision
   first**, recorded in an ADR or in a notice to the architecture group. Never
   as a side effect of a refactor.

6. **When in doubt, read the CHERI file before claiming what it contains.**
   File names do not predict contents: `cheri_prelude.sail` holds tag
   callbacks, while the capability widths live in `cheri_cap_common.sail`. A
   "file responsibility table" that is inferred from names has already produced
   one wrong refactor.

7. **CMake source order is load-bearing for ordinary functions.** Sail resolves
   cross-file names in file order, so where a TruISA file sits relative to the
   base file it talks to is part of its meaning. Three cases, and they do not
   agree with each other:

   | Relationship | Order | Example |
   |---|---|---|
   | **Override** -- the TruISA file redefines something the base already defines | TruISA file **after** the base (last wins) | `truisa_sys_regs.sail` after `riscv_sys_regs.sail` |
   | **Supply** -- the base *calls* something nothing defines | TruISA file **before** the base | `truisa_sys_regs_access.sail` before `riscv_sys_regs_access.sail` (it supplies `read_stvec_utvec`) |
   | **Scattered clause** -- `is_CSR_defined`, `csr_name_map` | anywhere, but between `riscv_csr_begin.sail` and `riscv_csr_end.sail` | `truisa_csr_ext.sail` next to `riscv_csr_end.sail` |

   ⚠️ Measured, not inferred: with the supply file placed *after* its consumer the
   build stops at `Function read_stvec_utvec not found` even though the
   definition is in the chain. The general rule "a swap keeps its position" is
   therefore only true for same-position replacement.

### Identifier naming (TruISA addition)

- **No bare single letters**, unless the letter is a symbol the specification
  itself defines. Those stay exactly as the spec writes them:
  `N` / `C` (block exponent), `L` (length), `VA`, and the field name `N/C`.
- Everything else is spelled out: `bound` (not `b`), `base` (not `b`),
  `cap` (not `c`), `ptr` (not `p`), `addrInt` (not `a`).
- ⚠️ Short abbreviations that are not words are forbidden too: `bnd`, `sz`,
  `cnt`, `len_str` is fine but `lstr` is not. Write `bound`, `size`, `count`.
- ⚠️ One name must not carry two meanings in one file. Example of what this
  rule prevents: `c : Capability` and `c : Int` (the block exponent) coexisting
  in the same module.
- Rationale: this model IS the executable form of the specification. A reader
  who has to decode `b` cannot check the code against the prose line by line,
  which is the only real acceptance test this model has.

- Since this is the official model intended to be included as part of the
  RISC-V specifications, readability is paramount, including to those not
  already familiar with the details of that field of Computer Science (e.g.
  floating-point or cryptography)

- All instructions should be built as part of both the RV32 and RV64 models so
  as to provide a path to supporting mutable MXL/SXL/UXL; if necessary,
  constructs like `assert(xlen == 32)` at the start of the body can be
  used to suppress any type errors that arise as a result

- Avoid the use of hard-coded constants like 32 even if the instruction is
  RV32-specific, instead favouring `xlen` or a computed constant to
  more clearly express the underlying intent

- Local variables should be made immutable whenever possible, but short
  imperative loops with a small amount of local mutable state are preferred
  over less-readable functional-style recursive equivalents

- Choose carefully between integer and bitvector types, and avoid multiple
  round-trips between the two; for example, if counting something, use a `nat`
  and convert it to an appropriately-sized bitvector at the point it is stored
  in a register, but keep register source values as bitvectors until they are
  needed to be interpreted as integers (see the implementation of `MUL` as an
  example)

- Use Sail's `newtype` constructs to differentiate between types with
  the same underlying representation (e.g. they are bitvectors of the
  same length) for added type safety

- Prefer `bool` over `bits(1)` when a value logically represents true or false
  rather than being a single bit with a numeric meaning, and vice-versa

- Do not use strings for anything that is not text

- No new compile-time warnings from the Sail compiler should be introduced
  (this does not include C warnings for the code generated by the Sail
  compiler)

- Do not use the `ext*` types and hooks for standard extensions unless
  providing a stub implementation; these are reserved for use by out-of-tree
  extensions that provide their own non-stub implementations
