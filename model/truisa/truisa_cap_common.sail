/*=======================================================================================*/
/*  TruISA: the capability itself -- widths, slices, encode/decode, bounds.              */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_cap_common.sail (700 lines).                          */
/*                                                                                       */
/*  Status: PARTIAL. Position 7 in the dependency order. The width block below is         */
/*  settled (D-96); the rest of the blueprint -- the Capability struct, bitsToCap,         */
/*  capToBits, capToMetadataBits, the bounds decode and the slot geometry -- has not      */
/*  been analysed yet and is a separate agenda item (structure, not widths).             */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * Width block. Everything below derives from TWO target constants; nothing else is
 * written down twice.
 *
 * // TRUISA DELTA vs cheri_cap_common.sail:10-26: the blueprint writes cap_size from
 * // xlen_bytes and cap_addr_width from xlen, so its widths are functions of the config
 * // variable. TruISA cannot do that. Two reasons, both measured on this model:
 * //
 * //   1. `xlen` is a CONFIG variable. Any constant that reaches it cannot be folded at
 * //      type-check time, and bits() then rejects it. (D-96; the evidence is the
 * //      correction in D-94 -- `bits(xlen - 55)` reports "recursive types are
 * //      forbidden", which is Sail's generic wording for "I could not evaluate this
 * //      width".)
 * //   2. Sail folds multiplication and 2^ well but NOT division and log2 --
 * //      riscv_xlen.sail:11-12 says so in as many words. That is the real reason the
 * //      blueprint detours through log2_cap_size instead of computing a width directly.
 * //
 * // So the parameterising base is truisa_ptr_width, a literal, and a constraint ties it
 * // to xlen. Writing 64 here while configuring an RV32 build is then a compile error
 * // rather than a silent mismatch of the kind two independent constants allow.
 * ---------------------------------------------------------------------------------- */

/* Target constant 1: the pointer width. Change this ONE line for RV32. */
type truisa_ptr_width : Int = 64
let  truisa_ptr_width = sizeof(truisa_ptr_width)

/* ⭐ The seam that makes the constant above safe. It turns "this file says 64 but the
 * build is rv32" into a type error at configure time. Without it the literal would be
 * an unchecked duplicate of the config value.
 * TRUISA DELTA: the blueprint has no such constraint; it never writes a width down. */
constraint truisa_ptr_width == xlen

/* Bits 63-57: one mode bit plus six bits of N/C. */
type truisa_mode_width : Int = 1
let  truisa_mode_width = sizeof(truisa_mode_width)

/* N/C must be able to name any bit position of the pointer, so its width is log2 of the
 * pointer width: 6 for 64 bits, 5 for 32. Written as a conditional on a LITERAL rather
 * than as log2(truisa_ptr_width) because Sail does not fold log2 (see above).
 * TRUISA DELTA: the blueprint hard-codes 6 with no explanation of where it comes from. */
type truisa_nc_width : Int = if truisa_ptr_width == 64 then 6 else 5
let  truisa_nc_width = sizeof(truisa_nc_width)

/* Target constant 2: the address field width, set by the VA profile (ADR-0003):
 * Sv39 -> 39, Sv48 -> 48, Sv57 -> 57. Change this ONE line to switch profile. */
type truisa_address_width : Int = 48
let  truisa_address_width = sizeof(truisa_address_width)

/* Everything left between the label and the address. Sv48 -> 64-48-1-6 = 9. */
type truisa_pac_width : Int =
  truisa_ptr_width - truisa_address_width - truisa_mode_width - truisa_nc_width
let  truisa_pac_width = sizeof(truisa_pac_width)

/* Size of the capability in bytes: 8 for a 64-bit pointer, 4 for a 32-bit one.
 *
 * // TRUISA DELTA: `if truisa_ptr_width == 64 then 8 else 4`, not `2 ^ log2_cap_size`
 * // as D-94 first proposed. That form had to be corrected (D-96) because
 * // log2_cap_size is selected with `if xlen ...` in truisa_prelude_xlen.sail, so it
 * // reaches the config variable and cannot be folded here. The parameterisation
 * // survives -- it now depends on truisa_ptr_width, which is a literal -- but the
 * // single-source-of-truth route through log2_cap_size is closed on this path.
 * // ⛔ Do not add a second constant alongside this expression.
 * ---------------------------------------------------------------------------------- */
type cap_size : Int = if truisa_ptr_width == 64 then 8 else 4
let  cap_size = sizeof(cap_size)
