/*=======================================================================================*
 *  TruISA: placeholder for model/cheri/cheri_sys_regs_access.sail
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. An empty placeholder is still meaningful: it marks a position
 *  where the answer is "TruISA has nothing here", and that answer has to be justified
 *  like any other.
 *
 *  What the blueprint file does: get_mtvec / legalize_tvecc and friends.
 *
 *  Status: NOT YET ANALYSED. Nothing is defined below. Files are analysed in
 *  dependency order, from the top of model/CMakeLists.txt down; until then the fork
 *  does not type-check, and that is expected -- a missing definition is a question for
 *  spec, not something to paper over with a stub that compiles.
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* TODO(truisa): analysis pending. */

/* The shared base file riscv_sys_regs_access.sail:7 calls this, but nothing in the
 * vendored tree defines it -- it belongs to an extension that is not in this tree
 * (the same is true of the 72a56e9 upstream baseline, so stripping CHERI does not
 * remove the hole).
 *
 * This is NOT a stub added to make the checker quiet: the identity IS the architecture
 * here. There is no separate U-mode trap vector in TruISA -- stvec is a single register
 * with base semantics (ADR-0011 decision 2) -- so reading it back is reading the value
 * itself. Contrast with PCC, which was pure scaffolding and was deleted outright. */
function read_stvec_utvec(v : xlenbits) -> xlenbits = v
