/*=======================================================================================*/
/*  TruISA: enumerated types of the pointer model.                                       */
/*                                                                                       */
/*  Copy-and-adapt of model/cheri/cheri_types.sail. Same file role: CHERI keeps its       */
/*  enum / struct definitions there and its bits()/range() slice types in                 */
/*  cheri_cap_common.sail -- TruISA follows that split exactly.                          */
/*                                                                                       */
/*  TRUISA DELTA vs cheri_types.sail:                                                    */
/*    - CapPtrForm is new: CHERI asks "is the tag bit set", TruISA asks "which of five    */
/*      forms is this 7-bit label".                                                      */
/*    - NOT here (TruISA has no counterpart): CPtrCmpOp (no capability compare op),       */
/*      ClearRegSet (no tag clearing set), ExecutionMode (the tier lives in               */
/*      truisa_addr_checks.sail as ExecTier), ArchPerms / null_perms (no permission       */
/*      bits at all).                                                                    */
/*    - CapCheckType / CapEx are still pending: upstream riscv_inst_retire.sail declares  */
/*      CHERI_Exception : (CapCheckType, CapEx, virtaddr), so TruISA must eventually       */
/*      provide both here -- but the set of CapEx values is waiting on the architecture    */
/*      group's ruling (see the CRE notice), so they are deliberately absent for now.     */
/*=======================================================================================*/

// The five forms a 7-bit label can denote. Decision order is documented at
// getCapForm in truisa_cap_common.sail (the order is not arbitrary -- see there).
enum CapPtrForm = {
  FormPoisoned,
  FormBare,
  FormInvalid,
  FormDescriptor,      // reserved: no operator produces it in phase 1
  FormAligned,
}
