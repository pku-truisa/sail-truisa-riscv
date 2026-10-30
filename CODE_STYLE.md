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

7. **Source order is load-bearing for ordinary functions -- across files AND within
   one.** Sail resolves names by text position, so where a definition sits relative
   to its use is part of its meaning. Two scopes:

   | Scope | Rule |
   |---|---|
   | **Across files** | the file holding the definition must come **before** the file that uses it |
   | **Within one file** | the definition must come **before** the statement that uses it |

   Three relationships decide which side the TruISA file goes on:

   | Relationship | Order | Example |
   |---|---|---|
   | **Override** -- redefines something the base defines | TruISA **after** base | truisa_sys_regs.sail after riscv_sys_regs.sail |
   | **Supply** -- the base *calls* something nothing defines | TruISA **before** base | truisa_sys_regs_access.sail before its consumer |
   | **Scattered clause** -- is_CSR_defined, csr_name_map | anywhere between csr_begin and csr_end | truisa_csr_ext.sail |

   ⚠️ Measured twice, not inferred. Across files: with the supply file placed after
   its consumer the build stops at `Function read_stvec_utvec not found` even though
   the definition is in the chain. Within one file: moving the same definition below
   `get_stvec` reproduces the identical error, only now pointing inside that file.
   Both mean "a swap keeps its position" is true only for same-position replacement,
   and that a same-file reordering is **not** a harmless defensive move.

8. **Before taking a base file into the chain, ask two questions -- not one.** Both
   can fail independently, and they lead to different repairs:

   | # | Question | If yes |
   |---|---|---|
   | ① | Does it **reference** a symbol that is undefined everywhere outside `model/cheri/`? | TruISA supplies it, or the chain is rearranged -- the base file stays **out** |
   | ② | Does it **define** a name the chain **already defines**? | Take **only the missing names**; ⛔ never add the file whole |

   | Failure seen | File | Repair |
   |---|---|---|
   | ① | `riscv_sys_regs_access.sail` -- its xTVT block needs `legalize_tvt` / `register mtvt`, neither of which exists | supplied by `truisa_sys_regs_access.sail`, base file dropped from the chain |
   | ② | `riscv_types_ext.sail` -- 5 of its 10 names (`ext_exc_type` + four conversions) are already defined by TruISA's own enum | only the 3 missing stub types were taken |
   | neither | `riscv_sys_exceptions.sail` | used as-is |

   One-line tests: for ①, `grep` the candidate for symbols with no definition
   anywhere outside `model/cheri/`; for ②, `grep` its top-level definition names
   against the rest of the chain. Either hit means "not as-is".

   ⚠️ Question ② was added after the ①-only version was applied and failed:
   `riscv_types_ext.sail` had no unresolved reference at all, so ① said "use it
   as-is", and the build then stopped on `Cannot define type synonym ext_exc_type
   ... already exists`. The two failures look alike from far away -- both are
   "this base file does not fit" -- which is exactly why both questions have to be
   asked rather than inferred from one.

   ⚠️ Question ① exists because the opposite mistake was made three times in one
   session: an empty `truisa_*` placeholder sat in the chain while the base file
   that actually defines what the chain needs was left out. The symptom is always
   a dangling name much later in the build, never next to the placeholder.

9. **Never claim a value is "discarded" without naming its receiver.** A call that
   *looks* like a bare statement may be the last expression of its block, and a
   block's last expression **is** its value -- covering `match` arms. So before
   writing "the return value is dropped", find one of the three receivers:
   right-hand side of a `let`, an argument position, or the final expression of
   the enclosing block.

   | Claim | Check |
   |---|---|
   | "the caller never sets the PC" | `grep -n "set_next_pc(<fn>" model/riscv_insts_base.sail` -- a hit means **someone takes the value** |
   | "this function returns `unit`" | read the `val`/`function` signature, ⛔ not the shape of the `match` |
   | "the value is dropped" | quote the receiver's line number in the message; **no line number, no claim** |

   ⚠️ This rule exists because the opposite was asserted about
   `prepare_xret_target`: `prepare_xret_target(Machine)` sits alone on its line at
   `riscv_sys_control.sail:289`, but it is the arm's tail expression and therefore
   `exception_handler`'s return value, which `riscv_insts_base.sail:547` feeds to
   `set_next_pc`. An "urgent bug" was filed on the strength of "it looks like a
   statement". The proposed fix (call `set_next_pc` inside the function) would
   have run it twice per xRET, and `sail_branch_announce` is **not** idempotent.

   ⭐ Corollary: when a claim depends on a call site, **put the line number in the
   message**. A conclusion without it costs the other side a full round trip to
   re-derive the same grep.

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
