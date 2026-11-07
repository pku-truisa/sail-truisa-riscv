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
// Registration. Without this, check_CSR rejects 0xFC0 before handle_csr_op is ever
// reached -- the run silently falls back to the generic path and mroot reads as 0.
// (Measured: the probe produced a zero signature until this clause existed.)
// csr_name_map is a `scattered mapping`, not a function; leaving it default only costs a
// hex number instead of the name in traces.
function clause is_CSR_defined (0xFC0) = true

// From cheri_sys_regs.sail:49, renamed per D-416. Single global bit: no debug escape,
// no per-privilege chain (D-410). Seccfg has no `CRE` field, so bit 3 is wpri_0[3].
val truisa_registers_enabled : unit -> bool
function truisa_registers_enabled() = mseccfg[wpri_0][3] == 0b1

function handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead) =
  if csr == 0xFC0 then {
    C(rd) = truisaMroot();
    RETIRE_SUCCESS
  } else if csr == 0x747 then {
    // Latch bit 3 after `default`: doing it first would make read_CSR see the new value
    // and X(rd) would return the wrong old value.
    let src : xlenbits = if is_imm then zero_extend(regidx_bits(rs1)) else X(rs1);
    let tries : bool = isWrite & ((op == CSRRW) | (op == CSRRS)) & src[3] == 0b1;
    let res = default_handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead);
    match res {
      Retire_Success() => {
        if tries then {
          mseccfg = [mseccfg with wpri_0 = mseccfg[wpri_0] | 0x08];
          // P1-c: at CRE 0 -> 1, adopt mroot's metadata; the address must not move
          // (ch06). nextPCC takes the same metadata -- `tick_pc` reloads PCC from it at
          // the end of this very step, so setting PCC alone would be undone.
          let root = truisaMroot();
          PCC    = struct { mode = root.mode, nc = root.nc, pac = root.pac,
                            address = PCC.address };
          nextPCC = struct { mode = root.mode, nc = root.nc, pac = root.pac,
                             address = nextPCC.address };
        };
        res
      },
      _ => res
    }
  } else default_handle_csr_op(csr, rs1, rd, is_imm, op, isWrite, isRead)
