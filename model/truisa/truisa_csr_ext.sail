/*=======================================================================================*
 *  TruISA: placeholder for model/cheri/cheri_csr_ext.sail
 *
 *  Status: ORDERED, NOT YET WRITTEN (D-168 #9 / D-132 改动 2).
 *  Content is already decided: six is_CSR_defined cases and six csr_name_map
 *  entries for 0x5C0-0x5C5 (xdtp / xpkey0 / xpkey1 / xfailcnt / xfailctl /
 *  xfailkey). The scattered clauses must sit between csr_begin and csr_end
 *  (see CODE_STYLE.md:147). The architecture group owes the normative text
 *  (A-5 / D-8). Do not delete this file: deleting it cancels an order.
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. An empty placeholder is still meaningful: it marks a position
 *  where the answer is "TruISA has nothing here", and that answer has to be justified
 *  like any other.
 *
 *  What the blueprint file does: the capability CSR extension hook.
 *
 *  ⚠️ The old header said "NOT YET ANALYSED". Superseded (D-184): the content is
 *  decided (D-132 改动 2), so the status is "ordered, not written", not "unknown".
 *  Nothing is defined below yet; files are still filled in dependency order, from the
 *  top of model/CMakeLists.txt down.
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* Nothing defined yet: ORDERED, NOT YET WRITTEN -- see Status at the top (D-132 改动 2).
 * ⛔ Do not delete this file and do not add a stub: the six CSR entries are a decision
 * already taken, and a stub would satisfy the type checker while hiding that. */
