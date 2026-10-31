/*=======================================================================================*/
/*  TruISA: the 32-bit capability format, for RV32.                                     */
/*                                                                                       */
/*  Same role as truisa_prelude_64.sail, one step narrower. The blueprint counterpart is  */
/*  cheri_prelude_64.sail -- and, as noted there, the CHERI names are misleading: in      */
/*  CHERI, `_64` is the RV32 case (cap = 64 bits) and `_128` is the RV64 case. TruISA's   */
/*  `_32` (cap = 32 bits) has no CHERI equivalent at all, because CHERI never narrows the  */
/*  capability below 64 bits. It is the RV32 half of TruISA's own two-way split.          */
/*                                                                                       */
/*  ⚠️ This branch is a MODEL CAPABILITY, not a spec commitment: it is deliberately        */
/*  absent from docs/isa and spec/ (ADR-0032 decision 3). Do not cite it as normative,    */
/*  and do not add a spec sentence for it.                                                */
/*                                                                                       */
/*  The three values below are what makes mode + N/C + PAC + address fill the 32-bit      */
/*  pointer exactly: 1 + 5 + 2 + 24 = 32, so PAC_W = 2 falls out of the arithmetic.       */
/*=======================================================================================*/

/* ---- The per-XLEN values. Everything else is derived in truisa_prelude_xlen.sail. ---- */

// N/C width: log2 of the pointer width, i.e. log2(32) = 5.
type truisa_nc_width_32 : Int = 5
let  truisa_nc_width_32 = sizeof(truisa_nc_width_32)

// Address field: 24, chosen so the fields fill the pointer with nothing left over.
type truisa_address_width_32 : Int = 24
let  truisa_address_width_32 = sizeof(truisa_address_width_32)

// Capability in bytes: 4, i.e. 32 bits.  ⛔ Not `2 ^ log2_cap_size` (D-94/D-96).
type cap_size_32 : Int = 4
let  cap_size_32 = sizeof(cap_size_32)

// Width of the capability in bytes, as log2. 2 means 2^2 = 4 bytes = 32 bits.
type log2_cap_size_32 : Int = 2
let  log2_cap_size_32 = sizeof(log2_cap_size_32)
