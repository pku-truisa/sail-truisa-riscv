/*=======================================================================================*/
/*  TruISA: pick the capability format for the current XLEN, and derive everything from it.*/
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_prelude_xlen.sail (186 lines). Five groups there; only  */
/*  the first two survive, the other three are documented at the bottom of this file so    */
/*  the omission can be checked rather than taken on trust (D-94).                        */
/*                                                                                       */
/*  ⭐ THIS IS THE ONLY FILE IN model/truisa/ THAT BRANCHES ON XLEN. Everything downstream */
/*  -- truisa_cap_common.sail included -- consumes the names defined here and never asks   */
/*  which XLEN it is running on. If you find yourself writing `if xlen == 32` outside this */
/*  file, the value belongs in truisa_prelude_64.sail / _32.sail and gets chosen below.    */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * Group 1 (blueprint :9-10) -- KEPT, one line, as in the blueprint.
 *
 * Which capability format this build uses, in log2 bytes. The candidates live in
 * truisa_prelude_64.sail (3 = 8 bytes) and truisa_prelude_32.sail (2 = 4 bytes).
 * ---------------------------------------------------------------------------------- */
type log2_cap_size : Int = if xlen == 32 then log2_cap_size_32 else log2_cap_size_64
let  log2_cap_size = sizeof(log2_cap_size)

/* ------------------------------------------------------------------------------------
 * Group 2 -- THE TWO-WAY SPLIT. These three are the only per-XLEN values in the model.
 *
 * Each candidate is a literal in its own file; this is the single place they meet.
 * `cap_size` is taken from a candidate directly rather than from `2 ^ log2_cap_size`,
 * because that route reaches a config variable and cannot be folded (D-94/D-96).
 * ---------------------------------------------------------------------------------- */
type truisa_nc_width      : Int = if xlen == 32 then truisa_nc_width_32      else truisa_nc_width_64
let  truisa_nc_width = sizeof(truisa_nc_width)

type truisa_address_width : Int = if xlen == 32 then truisa_address_width_32 else truisa_address_width_64
let  truisa_address_width = sizeof(truisa_address_width)

type cap_size             : Int = if xlen == 32 then cap_size_32             else cap_size_64
let  cap_size = sizeof(cap_size)

/* ------------------------------------------------------------------------------------
 * Group 3 -- DERIVED. No XLEN branch below this line, and none may be added: a derived
 * width that needed to know the XLEN would mean a candidate is missing from Group 2.
 * ---------------------------------------------------------------------------------- */

// The pointer itself. IS xlen -- the blueprint's shape (cheri_cap_common.sail:14).
type truisa_ptr_width : Int = xlen
let  truisa_ptr_width = sizeof(truisa_ptr_width)

// One mode bit plus N/C.
type truisa_mode_width : Int = 1
let  truisa_mode_width = sizeof(truisa_mode_width)

// The label: mode + N/C. 7 bits at XLEN 64, 6 at 32.
type truisa_tag_width : Int = truisa_mode_width + truisa_nc_width
let  truisa_tag_width = sizeof(truisa_tag_width)

// Everything between the label and the address.
type truisa_pac_width : Int =
  truisa_ptr_width - truisa_address_width - truisa_mode_width - truisa_nc_width
let  truisa_pac_width = sizeof(truisa_pac_width)

// The struct's `address` is a full machine word, so the register representation is wider
// than the memory encoding (ADR-0029 decision 1).
type truisa_meta_width : Int = truisa_ptr_width - truisa_address_width
let  truisa_meta_width = sizeof(truisa_meta_width)

// Bookkeeping only (80 at XLEN 64, 40 at 32). ⛔ Never used inside bits().
type truisa_cap_repr_width : Int = truisa_ptr_width + truisa_meta_width
let  truisa_cap_repr_width = sizeof(truisa_cap_repr_width)

// Residue of the entry layout, not an input to it (D-223): a descriptor half-word is `xlen`
// wide and its valid field is truisa_address_width bits, so the two half-words leave
// exactly this many salt bits. 64 -> 32, 32 -> 16.  ⛔ NOT `truisa_meta_width * 2`.
// why: doc/truisa-deltas.md#saltwidth
type truisa_salt_width : Int = 2 * (xlen - truisa_address_width)
let  truisa_salt_width = sizeof(truisa_salt_width)

// MAC input = tag || CentroID || salt, a FIXED-length concatenation (spec/ch04), so no two
// distinct inputs share a shape. Spelled as a sum, never as 87 -- that number is only right
// at XLEN 64 (46 at 32).
// why: doc/truisa-deltas.md#mac
type truisa_mac_msg_width : Int =
  truisa_mode_width + truisa_nc_width + truisa_address_width + truisa_salt_width
let  truisa_mac_msg_width = sizeof(truisa_mac_msg_width)

// Lets Sail prove `bits(truisa_ptr_width - truisa_address_width)` non-negative.
constraint truisa_address_width <= truisa_ptr_width

/* ------------------------------------------------------------------------------------
 * Deleted from the blueprint (D-94), in blueprint order. None of it is moved elsewhere:
 * these have no TruISA counterpart, they simply do not exist here.
 *
 *   Group 3 (:47-121)  dec_EncMetadata / enc_EncMetadata -- the 32-bit encoded metadata
 *                      word. Nothing to encode.
 *   Group 4 (:123-165) the permission and mode encodings: ap_m_encdec, null_ap_m,
 *                      infinite_ap_m, legalizePermsAndMode. TruISA has no permission
 *                      bits and no mode bit in the pointer (ADR-0011).
 *   Group 5 (:167-186) getMetadataL8 / setMetadataL8 / getMetadataInternalExponent --
 *                      accessors for fields of the metadata word that no longer exists.
 *
 * The tier is not one of these: it is derived from the privilege level (ADR-0011
 * decision 1) and lives in truisa_addr_checks.sail as ExecTier.
 * ---------------------------------------------------------------------------------- */
