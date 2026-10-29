/*=======================================================================================*
 *  TruISA: no per-granule tag metadata -- this file is EMPTY BY DESIGN.
 *
 *  Counterpart: model/cheri/cheri_mem_metadata.sail (60 lines).
 *
 *  What the blueprint defines: mem_meta / default_meta / the two __RAM_Meta accessors
 *  and the tag helpers that turn an address into a tag-store address
 *  (mem_tag_write_callback, mem_tag_read_callback, addr_to_tag_addr, tag_addr_to_addr,
 *  tagaddrbits), plus an is_taggable predicate.
 *
 *  Why TruISA has nothing here -- three existence proofs, not a preference (D-95):
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
 *    3. mem_meta itself is closed by the upstream files. prelude_mem_metadata.sail
 *       already provides `type mem_meta = unit`, `default_meta = ()` and both
 *       __RAM_Meta functions as no-ops, and all nine upstream uses of mem_meta are
 *       generic pass-throughs -- not one of them assumes it is a bool. TruISA
 *       therefore loses nothing by not defining it again.
 *
 *  ---------------------------------------------------------------------------------
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
 *  ---------------------------------------------------------------------------------
 *
 *  ⚠️ CONSEQUENCE FOR truisa_mem.sail (position 22), recorded here so that round does
 *  not have to rediscover it: with mem_meta = unit, the blueprint's cheri_mem.sail:34
 *  passes cap.tag (a bool) as the metadata argument. Under unit that is a type error,
 *  not a semantic mismatch -- further evidence that the blueprint block cannot be
 *  copied over (D-89 registered the semantic side; this is the compile-level one).
 *
 *  If ADR-0001 §4 (per-16-byte in-memory tag) is ever lifted, this is the file where
 *  the tag store, its address translation and a non-unit mem_meta come back.
 *=======================================================================================*/

/* No definitions. See the reasoning above. */
