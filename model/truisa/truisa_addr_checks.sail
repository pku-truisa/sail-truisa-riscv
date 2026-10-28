/*=======================================================================================*/
/*  TruISA: execution tier and (later) address checks.                                   */
/*                                                                                       */
/*  Copy-and-adapt of model/cheri/cheri_addr_checks.sail. Same file role: this is where  */
/*  the model answers "what execution mode/tier are we in" and where the ext_* address   */
/*  hooks that upstream riscv_mem / riscv_vmem call are implemented.                     */
/*                                                                                       */
/*  TRUISA DELTA vs cheri_addr_checks.sail:                                              */
/*    - effective_cheri_mode (CHERI: ExecutionMode, derived from PCC's mode bits) is     */
/*      replaced by tierOf / bareBaseAllowed (TruISA: the tier is derived from the        */
/*      privilege level, ADR-0011 decision 1). There is no PCC and no mode bit in a       */
/*      pointer to consult.                                                              */
/*    - handle_cheri_exception is NOT here yet: it needs the mcause decision that is      */
/*      still open with the architecture group (see the CRE notice)                       */
/*    - ext_data_get_addr is NOT here yet: it is the part that performs the bounds        */
/*      check, and writing it now would have to be redone once the CRE question is        */
/*      settled (an instruction that runs while the check does not is worse than no       */
/*      check at all). Until then the upstream default in riscv_addr_checks.sail          */
/*      (pass-through) is what gets compiled.                                            */
/*=======================================================================================*/

/* ===== Execution tier (ADR-0011 decision 1) =====
 * The tier is DERIVED from the RISC-V privilege level. There is no separate mode CSR
 * and no enable bit -- ADR-0011 rev 1 is explicit that the tier decides ONLY whether a
 * Bare base is ACCEPTED; it never decides whether a tagged pointer is checked. Both
 * tiers check.
 *
 *   U    -> strict (pure-cap): a load/store base that is Bare is a violation
 *   S/M  -> permissive: tagged pointers AND Bare are both accepted
 *
 * ⛔ Terminology: S/M is "permissive", NOT CHERI's "hybrid". CHERI's hybrid is a
 * migration path INSIDE user space; TruISA's split is BY privilege level. The same
 * word would otherwise read as "TruISA kept CHERI's hybrid path", which it did not
 * (ADR-0017 decision 5 rules it out).
 *
 * ⚠️ "Accepted" is not "checked": a permissive-tier Bare base still goes through the
 * bounds check like any other form. The only difference between the tiers is this one
 * admission question.
 */
enum ExecTier = {
  TierStrict,        // U: tagged pointers only
  TierPermissive,    // S/M: tagged pointers and Bare
}

val  tierOf : Privilege -> ExecTier
function tierOf(priv : Privilege) -> ExecTier =
  if priv == User then TierStrict else TierPermissive

// May a load/store base be a Bare pointer at this privilege level?
// This is the ONLY thing the tier decides (ADR-0011 rev 1).
val  bareBaseAllowed : Privilege -> bool
function bareBaseAllowed(priv : Privilege) -> bool =
  match tierOf(priv) {
    TierStrict     => false,
    TierPermissive => true,
  }
