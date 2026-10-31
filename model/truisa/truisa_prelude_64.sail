/*=======================================================================================*/
/*  TruISA: the 64-bit capability format, for RV64.                                     */
/*                                                                                       */
/*  ⚠️ READ THE BLUEPRINT PAIRING CAREFULLY -- it is the opposite of what the file names  */
/*  suggest. In CHERI:                                                                    */
/*      cheri_prelude_64.sail   is used when xlen == 32   (cap = 64 bits)                */
/*      cheri_prelude_128.sail  is used when xlen == 64   (cap = 128 bits)               */
/*      cheri_prelude_xlen.sail picks between them on `if xlen == 32`.                   */
/*  TruISA keeps the cap at 64 bits on RV64, so the file that corresponds to THIS one,    */
/*  line for line, is **cheri_prelude_128.sail**, not cheri_prelude_64.sail.              */
/*                                                                                       */
/*  Everything else in the blueprint's 127 lines -- the compressed-format widths           */
/*  (mantissa, exponent, software-defined permissions, reserved fields), the EncMetadata  */
/*  bitfield and the ap_m_encdec table -- is dropped: TruISA has no compression layer     */
/*  (bounds are computed by the DGU from (C, S), ADR-0001 / ADR-0004) and no permission   */
/*  bits (ADR-0011).                                                                      */
/*                                                                                       */
/*  D-92 ruling: see truisa_prelude_32.sail for the RV32 counterpart.                     */
/*=======================================================================================*/

/* ---- The per-XLEN values. Everything else is derived in truisa_prelude_xlen.sail. ---- */

// N/C width: log2 of the pointer width. Spelled as a literal, not as log2(ptr_width),
// because Sail folds 2^ but not log2. (The blueprint hard-codes 6, unexplained.)
type truisa_nc_width_64 : Int = 6
let  truisa_nc_width_64 = sizeof(truisa_nc_width_64)

// Address field: 48 is the ONLY profile the specification defines (ADR-0032 decision 1:
// single configuration; the old Sv39/Sv48/Sv57 split and PAC_W = 57 - VA are withdrawn).
type truisa_address_width_64 : Int = 48
let  truisa_address_width_64 = sizeof(truisa_address_width_64)

// Capability in bytes: 8, i.e. 64 bits.  ⛔ Not `2 ^ log2_cap_size` -- that route reaches
// a config variable and cannot be folded (D-94/D-96).
type truisa_cap_size_64 : Int = 8
let  truisa_cap_size_64 = sizeof(truisa_cap_size_64)

// Width of the capability in bytes, as log2. 3 means 2^3 = 8 bytes = 64 bits.
type truisa_log2_cap_size_64 : Int = 3
let  truisa_log2_cap_size_64 = sizeof(truisa_log2_cap_size_64)
