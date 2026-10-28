/*=======================================================================================*/
/*  TruISA: pointer width profile.                                                       */
/*                                                                                       */
/*  Copy-and-adapt of model/cheri/cheri_prelude.sail (and its _64/_128/_xlen variants).  */
/*  Only the numbers change: TruISA keeps a 64-bit in-band pointer with a 48-bit address */
/*  field, so there is one profile instead of CHERI's 128/64 split.                      */
/*                                                                                       */
/*  ⭐ This file is the ONLY place to change the VA profile (ADR-0003 rev 12).            */
/*                                                                                       */
/*  TRUISA DELTA vs cheri_prelude*.sail:                                                 */
/*    - no cap_xe_width / cap_E_width / cap_mantissa_width (no compressed encoding)      */
/*    - cap_pac_width is new (CHERI has no in-band authentication field)                 */
/*    - cap_size is unchanged (xlen_bytes) but cap_addr_width is VA, not xlen            */
/*=======================================================================================*/

/* ===== Pointer layout, from the top bit down ===== */
//   bit 63        mode    truisa_mode_width = 1
//   bits 62-57    N/C     truisa_nc_width   = 6
//   bits 56-48    PAC     truisa_pac_width  = ptr - VA - mode - N/C (computed)
//   bits 47-0     address truisa_va
// Every width is derived from these; no bit position is hard-coded anywhere else.
type truisa_ptr_width   : Int = xlen           // 64 on RV64 (TruISA targets RV64)
let  truisa_ptr_width   = sizeof(truisa_ptr_width)
type truisa_va          : Int = 48              // Sv48; Sv39 -> 39, Sv57 -> 57
let  truisa_va          = sizeof(truisa_va)
type truisa_mode_width  : Int = 1
let  truisa_mode_width  = sizeof(truisa_mode_width)
type truisa_nc_width    : Int = 6
let  truisa_nc_width    = sizeof(truisa_nc_width)
// PAC takes whatever is left between the tag and the address:
//   Sv39 -> 64-39-7 = 18 | Sv48 -> 64-48-7 = 9 | Sv57 -> 64-57-7 = 0
type truisa_pac_width   : Int = truisa_ptr_width - truisa_va - truisa_mode_width - truisa_nc_width
let  truisa_pac_width   = sizeof(truisa_pac_width)

/* ===== Blueprint-compatible aliases =====
 * The rest of the model (and every name inherited from cheri_cap_common) refers to
 * cap_*_width, so these aliases keep those call sites unchanged. The truisa_* names
 * above remain the single source of truth.
 */
type cap_mode_width : Int = truisa_mode_width
let  cap_mode_width = sizeof(cap_mode_width)
type cap_nc_width : Int = truisa_nc_width
let  cap_nc_width = sizeof(cap_nc_width)
type cap_pac_width : Int = truisa_pac_width
let  cap_pac_width = sizeof(cap_pac_width)
