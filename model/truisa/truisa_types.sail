/*=======================================================================================*/
/*  TruISA: enumerated types of the pointer model and of the failure reporting.           */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_types.sail (91 lines). Defines 2 enums and 2          */
/*  functions -- nothing else. See D-90 / D-91 for the eleven per-declaration rulings.   */
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
 * Why the capability check failed. This is the bottom half of mtval2 (CAUSE, bits 3-0).
 *
 * // TRUISA DELTA: the names are carried over from the blueprint
 * // (model/cheri/cheri_types.sail) but the SEMANTICS have changed -- 3 of the 7 reasons
 * // are TruISA's own, and 2 of CHERI's cannot occur here (no tag: ADR-0001; nothing is
 * // sealed; no permission bits: ADR-0011).
 * // Do NOT infer semantics from the name (D-91 ruling 1).
 *
 * Codes are the external ABI (mtval2), so they line up with the blueprint's value grid:
 *   0x0  6    integrity check failed     (blueprint calls code 0 TagViolation -- same
 *                                        "this pointer is not trustworthy" slot, and 0
 *                                        was free in TruISA since there is no tag)
 *   0x2  1    strict tier rejects a Bare base  (blueprint: permission; same "this
 *                                        operation is not allowed here" slot)
 *   0x3  *    illegal address: reserved code point / out-of-range slot exponent /
 *             non-Bare instruction address / zero address
 *   0x4  1    out of bounds
 *   0x5  345  table subsystem: missing entry / table not configured / full or slot
 *             clash -- ONE code for all three, because the spec states they cannot be
 *             told apart from mtval2 alone. Splitting them would be finer than the
 *             norm (self-invented).
 *   0x6  7    monotonicity violation
 *   0x1       left empty (blueprint: seal violation -- TruISA has no sealing)
 *
 * Two reasons share 0x3 and three share 0x5, which is why capex_code below is a
 * function and not a mapping.
 * ---------------------------------------------------------------------------------- */
enum CapEx = {
  IntegrityFailure,     // 0x0
  BareInStrictTier,     // 0x2
  IllegalForm,          // 0x3
  ZeroAddress,          // 0x3
  OutOfBounds,          // 0x4
  TableSubsystem,       // 0x5
  Monotonicity,         // 0x6
}

/* function, NOT mapping -- and the reason is NOT "7 values onto 6 codes".
 * It is that the correspondence is no longer one-to-one: two reasons share 0x3 and
 * three share 0x5, so there is no inverse. Even if the counts happened to match, a
 * mapping <-> would still be ill-formed as soon as any two reasons share a code
 * (D-90; the blueprint's capex_code at cheri_types.sail:33-39 IS a bijection because
 * CHERI's five reasons map onto five distinct codes).
 */
val capex_code : CapEx -> bits(4)
function capex_code(ex : CapEx) -> bits(4) =
  match ex {
    IntegrityFailure => 0x0,
    BareInStrictTier => 0x2,
    IllegalForm      => 0x3,
    ZeroAddress      => 0x3,
    OutOfBounds      => 0x4,
    TableSubsystem   => 0x5,
    Monotonicity     => 0x6,
  }

/* ------------------------------------------------------------------------------------
 * What kind of access was being checked. Top half of mtval2 (TYPE, bits 19-16).
 *
 * No TRUISA DELTA: same three checks, same codes 0/1/2 as cheri_types.sail:49-58
 * (D-87 ruling 2). All three are reachable -- isa/08 has fetch (0,*) / data (1,*) /
 * jump-branch (2,*), which are exactly Inst / Data / JBr. And mtval2.TYPE IS this
 * enum: cheri/test_main_ext.sail:17 asserts
 *   mtval2[TYPE] == capchecktype_code(CapCheckType_Data).
 * ADR-0011 rev 1 "instruction addresses must be Bare" does NOT mean fetch is not
 * checked: a non-Bare instruction address is precisely what produces (0, 3).
 * ---------------------------------------------------------------------------------- */
enum CapCheckType = {
  CapCheckType_Inst,
  CapCheckType_Data,
  CapCheckType_JBr,
}

/* function for symmetry with capex_code above: one shape for both views of both enums,
 * rather than a mapping here and a function there for the same kind of lookup. */
val capchecktype_code : CapCheckType -> bits(4)
function capchecktype_code(ty : CapCheckType) -> bits(4) =
  match ty {
    CapCheckType_Inst => 0x0,
    CapCheckType_Data => 0x1,
    CapCheckType_JBr  => 0x2,
  }

/* ------------------------------------------------------------------------------------
 * Deliberately NOT defined here (D-90, each checked for users before dropping):
 *
 *   CPtrCmpOp (blueprint :9-18, 8 constructors)  -- zero users anywhere.
 *   ClearRegSet (blueprint :20-23)               -- zero users anywhere.
 *   capex_name (blueprint :41-47)                -- one debug print in
 *                                                   cheri_addr_checks.sail:26-27, no
 *                                                   TruISA user.
 *   capchecktype_name (blueprint :61-66)         -- same, and its values are CHERI's
 *                                                   exception names
 *                                                   (InstructionAccessFault /
 *                                                   LdStAmoDataFault / JBrFault), which
 *                                                   would suggest TruISA raises those.
 *   ExecutionMode + execution_mode_encdec (:68-78) -- zero users upstream, and all four
 *                                                   of its mechanisms (mode bit stored in
 *                                                   pointer permissions, MODESW, decoding
 *                                                   twice by mode, ap_m_encdec packing)
 *                                                   are absent from TruISA: the tier is a
 *                                                   function of the privilege level
 *                                                   (ADR-0011 decision 1) and lives in
 *                                                   truisa_addr_checks.sail as ExecTier.
 *   ArchPerms + null_perms (blueprint :80-91)     -- zero users in riscv_*.sail; all 7
 *                                                   users are inside cheri/ (the whole directory).
 *
 * ExecutionMode's SEMANTICS stay (two tiers, ADR-0011 decision 1); only the TYPE goes.
 * If some place genuinely needs a type, use a TruISA-owned name (ExecTier), not
 * ExecutionMode -- reusing the blueprint's word would be the same "same word, different
 * meaning" trap that ADR-0011 already warns about with "hybrid".
 * ---------------------------------------------------------------------------------- */
