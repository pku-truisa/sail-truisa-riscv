/*=======================================================================================*
 *  TruISA: placeholder for model/cheri/cheri_insts_cext.sail
 *
 *  Status: 8 NOT ADOPTED, 2 PENDING (D-184, analysis 2026-10-30 section 4).
 *  Rejected: c.lc / c.sc / c.lcsp / c.scsp (they would take the c.fld / c.fsd
 *  slots and assume a 16-byte scale), c.mv (native c.mv already equals CMV),
 *  c.jalr / c.jr (ADR-0009 M7 covers them), c.jal (RV32 only).
 *  Pending: c.addi16sp / c.addi4spn -- decision D1. If D1 chooses option B,
 *  the redefinition of those two lands HERE. Do not delete this file.
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. An empty placeholder is still meaningful: it marks a position
 *  where the answer is "TruISA has nothing here", and that answer has to be justified
 *  like any other.
 *
 *  What the blueprint file does: the compressed capability instructions.
 *
 *  ⚠️ The old header said "NOT YET ANALYSED". Superseded (D-184): eight of the ten
 *  entries are decided as "not adopted", two are pending decision D1 -- so this is
 *  "decided, with two open", not "unknown". Nothing is defined below; files are still
 *  filled in dependency order, from the top of model/CMakeLists.txt down.
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* Nothing defined yet: 8 NOT ADOPTED / 2 PENDING (D1) -- see Status at the top.
 * ⛔ Do not delete this file: if D1 chooses option B, the redefinition of
 * c.addi16sp / c.addi4spn lands here rather than in a new file, because the CHERI
 * position exists (cheri_insts_cext.sail) and the mirror keeps positions, not files. */
