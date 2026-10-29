/*=======================================================================================*
 *  TruISA: placeholder for model/cheri/cheri_reg_type.sail
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. An empty placeholder is still meaningful: it marks a position
 *  where the answer is "TruISA has nothing here", and that answer has to be justified
 *  like any other.
 *
 *  What the blueprint file does: regtype / zero_reg / RegStr — the register value type.
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
