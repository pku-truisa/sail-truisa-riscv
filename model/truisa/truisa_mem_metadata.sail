/*=======================================================================================*
 *  TruISA: mem_meta = unit -- the metadata carries no information.
 *
 *  Counterpart: model/cheri/cheri_mem_metadata.sail (60 lines).
 *
 *  What the blueprint defines: mem_meta / default_meta / the two __RAM_Meta accessors
 *  and the tag helpers that turn an address into a tag-store address
 *  (mem_tag_write_callback, mem_tag_read_callback, addr_to_tag_addr, tag_addr_to_addr,
 *  tagaddrbits), plus an is_taggable predicate.
 *
 *  What TruISA defines here (D-111): mem_meta / default_meta / both __RAM_Meta
 *  accessors -- four symbols, no tag store, no tag address translation.
 *
 *  Why mem_meta is unit, and not the blueprint's bool: ADR-0001 §4 defers the
 *  per-16-byte in-memory tag, so there is no per-granule bit to carry. This is a
 *  semantic consequence, not a convenience: a bool here would model a tag store that
 *  does not exist.
 *
 *  Why the other five blueprint symbols stay out -- two existence proofs, not a
 *  preference (D-95; proof 3 was refuted, see below):
 *
 *    1. Five of the six symbols have ZERO external users. mem_tag_write_callback,
 *       mem_tag_read_callback, addr_to_tag_addr, tag_addr_to_addr and tagaddrbits are
 *       referenced nowhere outside this file. They exist only to serve the tag store,
 *       and TruISA has no tag store (ADR-0001): the label lives in the pointer value,
 *       bits 63-57, and is not mirrored in memory.
 *
 *    2. The sixth, is_taggable, ALREADY EXISTS UPSTREAM and with a fuller definition:
 *       riscv_pma.sail:117 defines it from the PMA map. This file only repeats the
 *       `val` declaration. So excluding this file does not lose is_taggable -- it
 *       makes the model use the upstream definition, which is the correct one.
 *
 *  ---------------------------------------------------------------------------------
 *  ⚠️ THE OLD PROOF 3 WAS FALSE (D-111, refuting D-95 #3). It read:
 *
 *       "mem_meta itself is closed by the upstream files. prelude_mem_metadata.sail
 *        already provides `type mem_meta = unit`, `default_meta = ()` and both
 *        __RAM_Meta functions as no-ops ..."
 *
 *    That premise does not hold: prelude_mem_metadata.sail is in NEITHER source list
 *    (grep -c prelude_mem_metadata model/CMakeLists.txt => 0). `type mem_meta` has
 *    exactly two definitions in the tree:
 *
 *        model/prelude_mem_metadata.sail:13        type mem_meta = unit   <- in neither list
 *        model/cheri/cheri_mem_metadata.sail:11    type mem_meta = bool   <- CHERI chain only
 *
 *    So the TruISA chain had NO mem_meta at all, and prelude_mem.sail:81
 *    (`val write_ram : ... -> bool`, whose signature mentions mem_meta) had to stop.
 *    The fix is this file, NOT a line in model/CMakeLists.txt: "each chain supplies
 *    its own" is the existing convention (cheri_mem_metadata.sail depends on no
 *    prelude), so the counterpart of a chain-local file is a chain-local file.
 *  ---------------------------------------------------------------------------------
 *
 *  ⚠️ PAIRED WITH truisa_prelude.sail (position 1) -- read the two together.
 *
 *  truisa_prelude.sail is empty on the grounds that MEMr_tag / MEMw_tag have no
 *  callers; and their ONLY callers are this file, at lines 38, 46 and 53 of the
 *  blueprint. So the two decisions hold each other up:
 *
 *    - judge only position 1 and keep this file  -> lines 38/46/53 call MEMr_tag and
 *      MEMw_tag, which would then be undefined: a hard compile break, not a semantic
 *      nicety;
 *    - judge only this file and keep position 1  -> two hooks declared with no callers
 *      anywhere: dead declarations.
 *
 *  Both must land together, which is why each file points at the other (D-95).
 *  This still holds under D-111 -- TruISA needs neither MEMr_tag nor MEMw_tag,
 *  because __WriteRAM_Meta / __ReadRAM_Meta below are no-ops and touch no tag store.
 *  ---------------------------------------------------------------------------------
 *
 *  ⚠️ CONSEQUENCE FOR truisa_mem.sail (position 22), recorded here so that round does
 *  not have to rediscover it: with mem_meta = unit, the blueprint's cheri_mem.sail:34
 *  passes cap.tag (a bool) as the metadata argument. Under unit that is a type error,
 *  not a semantic mismatch -- further evidence that the blueprint block cannot be
 *  copied over (D-89 registered the semantic side; this is the compile-level one).
 *  D-111 does not change this: TruISA's truisa_mem.sail passes no tag, so the error
 *  only appears if the blueprint block is copied verbatim.
 *
 *  If ADR-0001 §4 (per-16-byte in-memory tag) is ever lifted, this is the file where
 *  the tag store, its address translation and a non-unit mem_meta come back.
 *=======================================================================================*/

/* TRUISA DELTA: blueprint uses bool (cheri_mem_metadata.sail:11) because CHERI stores
 * a 1-bit tag per capability granule. TruISA has no per-granule tag (ADR-0001 §4
 * deferred), so the metadata carries no information: unit.
 */

type mem_meta = unit

let default_meta : mem_meta = ()

/* No tag store: both accessors are no-ops that only preserve the signature.
 * The blueprint's versions call is_taggable, addr_to_tag_addr, MEMw_tag / MEMr_tag
 * and the two callbacks -- all of which are absent here by proof 1 above.
 */
val __WriteRAM_Meta : (physaddrbits, mem_access_width, mem_meta) -> unit
function __WriteRAM_Meta(addr, width, meta) = ()

val __ReadRAM_Meta : (physaddrbits, mem_access_width) -> mem_meta
function __ReadRAM_Meta(addr, width) = default_meta
