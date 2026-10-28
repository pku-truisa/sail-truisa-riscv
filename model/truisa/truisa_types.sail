/*=======================================================================================*/
/*  TruISA: enumerated types of the pointer model and of the failure reporting.           */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_types.sail (91 lines).                                */
/*                                                                                       */
/*  Kept, with the reasons (D-87):                                                       */
/*    CapCheckType  -- 3 values, codes 0/1/2, unchanged from cheri_types.sail:49-58.      */
/*                     TruISA produces all three (isa/08: fetch (0,3) / data (1,4) /      */
/*                     jump-branch (2,3)), and mtval2.TYPE IS this enum -- proof:         */
/*                     cheri/test_main_ext.sail:17 asserts                              */
/*                     mtval2[TYPE] == capchecktype_code(CapCheckType_Data).             */
/*    CapEx         -- 5 TruISA failure reasons, codes 2/2/3/3/4.                       */
/*                     ⚠️ NOT CHERI's five names: TruISA has no tag and no sealing, so    */
/*                     those reasons do not exist; the semantics differ even where the    */
/*                     count happens to match.                                            */
/*                                                                                       */
/*  Dropped, with the reasons:                                                           */
/*    CPtrCmpOp     -- cheri_types.sail:9-18, the eight capability-compare operations.     */
/*                     TruISA has CSEQ and no ordering compares (ADR-0018 lists the ops). */
/*    ClearRegSet   -- cheri_types.sail:20-23, "which register file to clear the tags in". */
/*                     There are no tags to clear (ADR-0001).                             */
/*    ExecutionMode -- cheri_types.sail:68-78 (IntPtrMode/CapPtrMode). TruISA has no mode */
/*                     bit in the pointer; the execution tier is derived from the         */
/*                     privilege level instead (ADR-0011 rev 1) and lives in              */
/*                     truisa_addr_checks.sail as ExecTier.                              */
/*    ArchPerms     -- cheri_types.sail:80-91. TruISA has no permission bits at all       */
/*                     (ADR-0011); GCBOUND/GCBASE carry no permission check.              */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * The five forms a 7-bit pointer label can denote. TruISA-only: CHERI asks "is the tag
 * bit set", TruISA asks "which of five forms is this label".
 * Decision order is documented at getCapForm in truisa_cap_common.sail -- the order is
 * not arbitrary, see the comment there.
 * ---------------------------------------------------------------------------------- */
enum CapPtrForm = {
  FormPoisoned,
  FormBare,
  FormInvalid,
  FormDescriptor,      // reserved: no operator produces it in phase 1
  FormAligned,
}

/* ------------------------------------------------------------------------------------
 * What kind of access was being checked. This is the top half of mtval2 (ADR-0024
 * decision 7: TYPE in bits 19-16), so the codes are an external ABI and must match the
 * blueprint's values exactly.
 * ---------------------------------------------------------------------------------- */
enum CapCheckType = {
  CapCheckType_Inst,
  CapCheckType_Data,
  CapCheckType_JBr,
}

mapping capchecktype_code : CapCheckType <-> bits(4) = {
  CapCheckType_Inst <-> 0x0,
  CapCheckType_Data <-> 0x1,
  CapCheckType_JBr  <-> 0x2,
}

mapping capchecktype_name : CapCheckType <-> string = {
  CapCheckType_Inst <-> "InstructionAccessFault",
  CapCheckType_Data <-> "LdStAmoDataFault",
  CapCheckType_JBr  <-> "JBrFault",
}

/* ------------------------------------------------------------------------------------
 * Why the capability check failed. This is the bottom half of mtval2 (CAUSE in bits
 * 3-0).
 *
 * // TRUISA DELTA: the five reasons are TruISA's own, not CHERI's (D-87 ruling 3).
 * // CHERI's set (cheri_types.sail:25-31) is TagViolation / SealViolation /
 * // PermissionViolation / InvalidAddressViolation / LengthViolation -- three of those
 * // cannot occur here: there is no tag to violate (ADR-0001), nothing is sealed, and
 * // there are no permission bits (ADR-0011). The count is five either way, which is a
 * // coincidence, not a correspondence.
 * //
 * // The CODES, on the other hand, are reused deliberately: mtval2 is an external ABI
 * // and its values have to line up with the blueprint's, so the three code values that
 * // exist there (2, 3, 4) keep their meaning slots. Two of our reasons share code 2 and
 * // two share code 3; only OutOfBounds gets a code of its own.
 * ---------------------------------------------------------------------------------- */
enum CapEx = {
  IntegrityFailure,
  BareInStrictTier,
  IllegalForm,
  ZeroAddress,
  OutOfBounds,
}

/* ⚠️ function, NOT mapping.
 * CHERI's capex_code (cheri_types.sail:33-39) is a mapping because its five reasons map
 * one-to-one onto five codes. TruISA's five reasons map onto THREE codes, so there is no
 * inverse and a `mapping <->` would be ill-formed -- Sail would reject it, and "fixing"
 * that by inventing extra codes would change the external ABI (D-82 ④: an internal enum
 * need not correspond one-to-one with an external encoding).
 */
val capex_code : CapEx -> bits(4)
function capex_code(ex : CapEx) -> bits(4) =
  match ex {
    IntegrityFailure => 0x2,
    BareInStrictTier => 0x2,
    IllegalForm      => 0x3,
    ZeroAddress      => 0x3,
    OutOfBounds      => 0x4,
  }

/* Also a function, for the same reason: kept parallel with capex_code rather than mixing
 * a bijective mapping with a non-bijective function for two views of one enum. */
val capex_name : CapEx -> string
function capex_name(ex : CapEx) -> string =
  match ex {
    IntegrityFailure => "IntegrityFailure",
    BareInStrictTier => "BareInStrictTier",
    IllegalForm      => "IllegalForm",
    ZeroAddress      => "ZeroAddress",
    OutOfBounds      => "OutOfBounds",
  }
