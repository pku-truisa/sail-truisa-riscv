/*=======================================================================================*/
/*  TruISA: the capability itself -- widths, slices, encode/decode, bounds.              */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_cap_common.sail (700 lines).                          */
/*                                                                                       */
/*  Status: NOT YET ANALYSED as a whole. It is position 7 in the dependency order, and    */
/*  its analysis has not started. One definition is already here because something else   */
/*  needs it now: cap_size, which gives log2_cap_size from truisa_prelude_xlen.sail a     */
/*  consumer on the TruISA side (D-94 option C). Everything else the blueprint defines in */
/*  this file -- the compressed base/top encoding, the bounds decode, the permission       */
/*  checks, the tag plumbing -- is still to be examined block by block.                  */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * Size of the capability in bytes (excluding tag).
 *
 * // TRUISA DELTA: written as 2 ^ log2_cap_size, not as a literal and not as
 * // xlen_bytes * 2 (the blueprint's form, cheri_cap_common.sail:12).
 * //
 * // Reason: log2_cap_size is chosen in truisa_prelude_xlen.sail and therefore already
 * // knows the answer -- 2^3 = 8 on RV64, 2^2 = 4 on RV32. Writing a second independent
 * // number here would create two sources of truth that the compiler cannot cross-check:
 * // `2 ^ 3` and `8` are indistinguishable at the type level, so a drift between them
 * // would be silently accepted.
 * //
 * // ⛔ Do NOT add a constant alongside this expression, and do not "simplify" it to 8.
 * // // That would restore the second source of truth immediately.
 * //
 * // Ordering: truisa_prelude_xlen.sail (position 5) precedes this file (position 7), so
 * // log2_cap_size is already defined when this line is read.
 * //
 * // The blueprint's own comment above this type ("TODO: Rename to clen_bytes and
 * // clen?") is not carried over: it is a blueprint-internal rename note with no TruISA
 * // bearing.
 * ---------------------------------------------------------------------------------- */
type cap_size : Int = 2 ^ log2_cap_size
let  cap_size = sizeof(cap_size)
