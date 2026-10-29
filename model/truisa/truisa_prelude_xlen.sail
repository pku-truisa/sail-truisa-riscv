/*=======================================================================================*/
/*  TruISA: pick the capability width for the current XLEN.                             */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_prelude_xlen.sail (186 lines). Five groups there, only */
/*  the first survives; the other four are documented at the bottom of this file so the   */
/*  omission can be checked rather than taken on trust (D-94).                           */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * Group 1 (blueprint :9-10) -- KEPT AS IS, not a line changed.
 *
 * Which capability format this build uses. The two candidates are set in
 * truisa_prelude_64.sail (3, i.e. 8 bytes) and truisa_prelude_32.sail (2, i.e. 4 bytes);
 * this file only chooses. On RV64 it always resolves to 64-bit capabilities.
 *
 * The consumer on the TruISA side is cap_size in truisa_cap_common.sail, written as
 * 2 ^ log2_cap_size so that this constant is the single source of truth for the width
 * (D-94 option C). In the blueprint the only consumer was cheri_mem_metadata.sail:19-21,
 * which converts addresses to tag slots -- a mechanism TruISA does not have, so without
 * this line the constant would be correct but unused.
 * ---------------------------------------------------------------------------------- */
type log2_cap_size : Int = if xlen == 32 then log2_cap_size_32 else log2_cap_size_64
let  log2_cap_size = sizeof(log2_cap_size)

/* ------------------------------------------------------------------------------------
 * Deleted from the blueprint (D-94), in blueprint order. None of it is moved elsewhere:
 * these have no TruISA counterpart, they simply do not exist here.
 *
 *   Group 2 (:12-30)   the six Concentrate-format width parameters
 *                      (cap_sd_perms_width, cap_reserved_1_width, cap_reserved_0_width,
 *                      cap_mantissa_width, cap_E_width, cap_AP_M_width) plus cap_use_L8.
 *                      TruISA has no compressed encoding: bounds are computed by the DGU
 *                      from (C, S) (ADR-0001, ADR-0004), so there is no mantissa or
 *                      exponent to size.
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
