/*=======================================================================================*/
/*  TruISA: no in-memory tag -- this file is EMPTY BY DESIGN.                            */
/*                                                                                       */
/*  Status: NOT ADOPTED BY DECISION -- stays empty on purpose (D-184).                   */
/*  TruISA needs neither MEMr_tag nor MEMw_tag (still holds under D-111; see             */
/*  truisa_mem_metadata.sail:67). This file is the named return point if                 */
/*  ADR-0001 section 4 (per-16-byte in-memory tag) is ever lifted.                       */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_prelude.sail (12 lines, two declarations).            */
/*                                                                                       */
/*  What the blueprint declares:                                                        */
/*      MEMr_tag = pure   "read_tag_bool"  : bits(64) -> bool                            */
/*      MEMw_tag = impure "write_tag_bool" : (bits(64), bool) -> unit                    */
/*  These are the two hooks through which the model reaches an out-of-band tag store,     */
/*  i.e. the C emulator's per-address tag bit.                                          */
/*                                                                                       */
/*  Why TruISA has nothing here:                                                        */
/*    1. TruISA has no tag mechanism of any kind (ADR-0001). The label lives inside the   */
/*       pointer VALUE, in bits 63-57, and is not mirrored anywhere in memory. There is  */
/*       nothing to read and nothing to write, so there is no hook to declare.           */
/*    2. Nothing upstream needs them either. Checked, not assumed: the only callers of    */
/*       MEMr_tag / MEMw_tag in the whole tree are three lines inside                    */
/*       model/cheri/cheri_mem_metadata.sail (its __ReadRAM_Meta / __WriteRAM_Meta).     */
/*       TruISA does not compile that file -- it uses the upstream                       */
/*       prelude_mem_metadata.sail, whose mem_meta is `unit` -- so those three call sites */
/*       do not exist on this side.                                                     */
/*    3. Consequently the memory-metadata chain on the TruISA side is fully closed by the  */
/*       upstream files alone: prelude_mem_metadata.sail defines `type mem_meta = unit`,  */
/*       `default_meta = ()` and both __RAM_Meta functions as no-ops. TruISA adds nothing */
/*       because nothing is missing.                                                     */
/*                                                                                       */
/*  --------------------------------------------------------------------------------- */
/*  PAIRED WITH truisa_mem_metadata.sail (position 6) -- read the two together. */
/*  ⚠️ 前提已废（the old premise was refuted）：见 truisa_mem_metadata.sail:38-46 / D-111；   */
/*     结论仍成立（the conclusion still holds）——只加不删，保留历史层次（D-184 §6.2）。      */
/* */
/*  The reason these two hooks can be left out is that nothing calls them, and the only */
/*  callers are three lines inside truisa_mem_metadata.sail. That file in turn is empty */
/*  because TruISA has no tag store. The two decisions hold each other up: keep the */
/*  hooks without the caller file and they are dead declarations; keep the caller file */
/*  without the hooks and its three lines reference undefined names -- a compile break, */
/*  not a semantic nicety. Hence both land together and each points at the other (D-95). */
/*  --------------------------------------------------------------------------------- */
/* */
/*  ⚠️ If ADR-0001 §4 ("defer the per-16-byte in-memory tag") is ever lifted, this is the */
/*     file where the tag hooks would reappear, together with a granule width and a       */
/*     mem_meta that is no longer unit. Until then, an empty file is the truthful         */
/*     encoding of "the mechanism does not exist", and a stub returning false would be     */
/*     worse: it would look like a working no-tag policy while hiding that the question    */
/*     was never asked.                                                                  */
/*=======================================================================================*/

/* No definitions. See the reasoning above. */
