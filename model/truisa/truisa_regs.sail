/*=======================================================================================*
 *  TruISA: counterpart of model/cheri/cheri_regs.sail
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart.
 *
 *  What the blueprint file does: rC / wC / rC_bits / wC_bits plus `overload C`, i.e.
 *  the C() view of the register file. `regtype` itself moved to truisa_reg_type.sail
 *  (CMakeLists.txt:178); this file starts from the accessors.
 *
 *  Status: DONE (ADR-0029 CR section 8.2). rX_full / wX_full already take and return
 *  `regtype` in the shared riscv_regs.sail:140 / :177, so they became correct the
 *  moment regtype changed -- ⛔ do not copy them here.
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* accessors for the capability representation */

/* reads a given capability register (x0 reads as zero_reg, via rX_full). */
function rC(r : regno) -> regtype = rX_full(r)

/* writes a register with a capability value.
 *
 * // TRUISA DELTA vs cheri_regs.sail:15-18: the blueprint also fires
 * // xreg_write_callback(Regidx, v.address) so that RVFI sees integer-register writes.
 * // That callback is an RVFI hook, not part of the architecture, and TruISA's
 * // wX_full (riscv_regs.sail:177) does not fire it either -- adding it here would make
 * // C() and X() disagree about when the callback happens. Left out deliberately; if
 * // RVFI is wired up later, both writers must change together. */
function wC(Regno(r) : regno, v : regtype) -> unit = wX_full(Regno(r), v)

function rC_bits(Regidx(i) : regidx) -> regtype = rC(Regno(unsigned(i)))

function wC_bits(Regidx(i) : regidx, v : regtype) -> unit = {
  wC(Regno(unsigned(i))) = v
}

/* ⭐ This `overload` is what makes `C(cd) = ...` legal as an assignment and `C(cs1)`
 * legal as a read: Sail resolves the left-hand side to wC_bits and the right-hand side
 * to rC_bits. Without it, `truisa_inst.sail`'s 6 assignment sites and 12 read sites do
 * not type-check -- and `C` would simply be undefined (grep -rn "^function C\b" model/
 * => 0, so it does not exist anywhere upstream either).
 *
 * Same shape as cheri_regs.sail:26. */
overload C = {rC_bits, wC_bits, rC, wC}

/* ⚠️ TRUISA DELTA: the blueprint's cap_reg_name (cheri_regs.sail:40) prints a capability
 * operand as "cN", because CHERI has a separate capability register file. TruISA has one
 * register file and C() is only a view of it (ADR-0001, ADR-0003), so a capability
 * operand IS an integer register and prints exactly the same way.
 *
 * Kept as a distinct name rather than deleting the call sites: the disassembly lines in
 * truisa_inst.sail read `cap_reg_name(cs1)`, which documents that the operand is a
 * pointer, and that is worth keeping visible.
 *
 * ⚠️ It must be a MAPPING, not a function. The blueprint has it as
 * `mapping cap_reg_name : regidx <-> string` (cheri_regs.sail:40) and the reason is
 * structural: every `mapping clause assembly` needs the operands to be invertible, so a
 * plain `function ... -> string` cannot appear in one --
 *   "cap_reg_name is not a union constructor or mapping in mapping-pattern
 *    cap_reg_name(cs1)"                                        (measured, 2026-10-30)
 * The earlier function form was never exercised, because nothing type-checked
 * truisa_inst.sail until the chain finally reached it. */
mapping cap_reg_name : regidx <-> string = {
  r <-> reg_name(r)
}
