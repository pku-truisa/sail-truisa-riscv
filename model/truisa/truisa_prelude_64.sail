/*=======================================================================================*/
/*  TruISA: the 64-bit capability width, for RV64.                                      */
/*                                                                                       */
/*  ⚠️ READ THE BLUEPRINT PAIRING CAREFULLY -- it is the opposite of what the file names  */
/*  suggest. In CHERI:                                                                    */
/*      cheri_prelude_64.sail   is used when xlen == 32   (cap = 64 bits)                */
/*      cheri_prelude_128.sail  is used when xlen == 64   (cap = 128 bits)               */
/*      cheri_prelude_xlen.sail picks between them on `if xlen == 32`.                   */
/*  TruISA keeps the cap at 64 bits on both XLENs, so the file that corresponds to THIS  */
/*  one, line for line, is **cheri_prelude_128.sail**, not cheri_prelude_64.sail.         */
/*  Reading it side by side with cheri_prelude_64.sail would compare RV32 against RV64.   */
/*                                                                                       */
/*  Everything else in the blueprint's 127 lines -- the compressed-format widths           */
/*  (mantissa, exponent, software-defined permissions, reserved fields), the EncMetadata  */
/*  bitfield and the ap_m_encdec table -- is dropped: TruISA has no compression layer     */
/*  (bounds are computed by the DGU from (C, S), ADR-0001 / ADR-0004) and no permission   */
/*  bits (ADR-0011). One constant out of 127 lines is the expected outcome, not an        */
/*  omission.                                                                            */
/*=======================================================================================*/

/* Width of the capability in bytes, as log2. 3 means 2^3 = 8 bytes = 64 bits.
 *
 * This is the ONLY thing that varies between the 32- and 64-bit capability formats, and
 * it depends on the CAPABILITY width (chosen here as 64 bits for every XLEN), not on the
 * address width. TruISA narrows the *address field* by profile (39/48/57, ADR-0003);
 * it does not narrow the pointer. Do not confuse the two: truisa_address_width lives in
 * truisa_cap_common.sail and is a different quantity.
 *
 * D-92 ruling: see truisa_prelude_32.sail for the RV32 counterpart. */
type log2_cap_size_64 : Int = 3
let  log2_cap_size_64 = sizeof(log2_cap_size_64)
