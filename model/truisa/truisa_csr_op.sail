/*=======================================================================================*/
/*  TruISA: the CSR operation override (D-302 / ADR-0034).                              */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_csr_op.sail -- the blueprint defines handle_csr_op in */
/*  its own one-line-build-slot file for exactly this reason: riscv_csr_op.sail says     */
/*  "This just exists so it can be overridden". Replacing the slot is the designed       */
/*  mechanism, not a patch to the baseline.                                             */
/*                                                                                       */
/*  mroot is the ONLY CSR read in this architecture that yields a pointer, so it cannot   */
/*  go through the generic integer view: X(rd) would pin tagbits to 0000000              */
/*  (regval_into_reg), which is encoding-unavailable, and the bootstrap chain would      */
/*  break at its very first instruction.                                                 */
/*                                                                                       */
/*  NOT a general rule: this architecture has NO register-view dispatch by CSR address.   */
/*  xdtp / xpkey0,1 / xfailcnt / xfailctl / xfailkey are integer CSRs and must keep      */
/*  X(rd). Do not grow this into a table.                                                */
/*=======================================================================================*/

/* Three prohibitions (each corresponds to a silent failure):
 *  1. Never write X(rd) here -- that yields tagbits 0000000 and only explodes at the
 *     first dereference (CAUSE = 3), which looks exactly like the D-300 report.
 *  2. No write path for mroot -- read-only and M-only are enforced by bits 11-10 = 11 and
 *     bits 9-8 = 11 in the CSR address, so a write case here would be dead code that
 *     also implies the CSR is writable.
 *  3. Do not branch on privilege or CRE -- ADR-0034 decision 7: the mroot mechanism has
 *     zero CRE dependence, and "readable at CRE = 0" is the bootstrap precondition, not
 *     an special case.
 */
function handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead) =
  if csr == 0xFC0 then {
    C(rd) = truisaMroot();
    RETIRE_SUCCESS
  } else default_handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead)
