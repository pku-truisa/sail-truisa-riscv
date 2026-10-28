/*=======================================================================================*/
/*  TruISA: system register field layouts.                                               */
/*                                                                                       */
/*  Copy-and-adapt of model/cheri/cheri_sys_regs_types.sail. Same file role: it replaces */
/*  the upstream riscv_sys_regs_types.sail for the fork, because the upstream version     */
/*  defines Seccfg (which riscv_sys_regs.sail also defines -- including both is a         */
/*  duplicate-definition error) while this one does not.                                 */
/*                                                                                       */
/*  TRUISA DELTA vs cheri_sys_regs_types.sail:                                           */
/*    - MEnvcfg / SEnvcfg: the CRE bit (28) is KEPT with its CHERI meaning for now.       */
/*      ADR-0011 says TruISA has no enable bit, but removing it changes the meaning of    */
/*      mseccfg/menvcfg/senvcfg and would break cheri_registers_enabled, so the decision  */
/*      is with the architecture group (see the CRE notice). Do not delete it unilaterally. */
/*    - Tval2: KEPT unchanged. It is the mtval2 layout required by ADR-0024 decision 7    */
/*      (trap TYPE in bits 19-16, CAUSE in bits 3-0), and TruISA needs it for exactly the */
/*      same reason CHERI does.                                                          */
/*    - Seccfg: NOT defined here. It lives in riscv_sys_regs.sail upstream and is shared. */
/*=======================================================================================*/

bitfield MEnvcfg : bits(64) = {
  // Supervisor TimeCmp Extension
  STCE   : 63,
  // Page Based Memory Types Extension
  PBMTE  : 62,
  // Reserved WPRI bits.
  wpri_2 : 61 .. 29,
  // CHERI Register Enable
  // Controls whether less privileged levels can perform explicit accesses to
  // CHERI registers. Less priviledged levels can read and write CHERI
  // registers when CRE=1 and can't when CRE=0.
  // ⚠️ TruISA PENDING DECISION: ADR-0011 says there is no enable bit; see the CRE notice.
  CRE    : 28,
  // Reserved WPRI bits.
  wpri_1 : 27 .. 8,
  // Cache Block Zero instruction Enable
  CBZE   : 7,
  // Cache Block Clean and Flush instruction Enable
  CBCFE  : 6,
  // Cache Block Invalidate instruction Enable
  CBIE   : 5 .. 4,
  // Reserved WPRI bits.
  wpri_0 : 3 .. 1,
  // Fence of I/O implies Memory
  FIOM   : 0,
}

bitfield SEnvcfg : xlenbits = {
  // CHERI Register Enable
  // Controls whether less privileged levels can perform explicit accesses to
  // CHERI registers. Less priviledged levels can read and write CHERI
  // registers when CRE=1 and can't when CRE=0.
  // ⚠️ TruISA PENDING DECISION: ADR-0011 says there is no enable bit; see the CRE notice.
  CRE    : 28,
  // Cache Block Zero instruction Enable
  CBZE   : 7,
  // Cache Block Clean and Flush instruction Enable
  CBCFE  : 6,
  // Cache Block Invalidate instruction Enable
  CBIE   : 5 .. 4,
  // Reserved WPRI bits.
  wpri_0 : 3 .. 1,
  // Fence of I/O implies Memory
  FIOM   : 0,
}

/* mtval2 layout, required by ADR-0024 decision 7: a single mcause (28) plus this
 * field to distinguish what the capability check failed on.
 *   TYPE  : which check failed (data / fetch / control)
 *   CAUSE : the TruISA failure reason inside that type
 */
bitfield Tval2 : xlenbits = {
  // Reserved WPRI bits
  wpri_1 : xlen - 1 .. 20,
  // Trap type
  TYPE   : 19 .. 16,
  // Reserved WPRI bits
  wpri_0 : 15 .. 4,
  // Trap cause
  CAUSE  : 3 .. 0,
}
