/*=======================================================================================*
 *  TruISA: annotation carrier for `riscv_addr_checks.sail`, plus the two CSR hooks the
 *  base file cannot supply (D-7).
 *
 *  ⚠️ What this file is: first an ANNOTATION (D-162 section 4.3 constraint 1 -- the
 *  stub/real distinction has to be recorded next to the position it governs, in a file the
 *  rule checkers can grep, because the base file itself may not be edited: ADR-0024
 *  section 11.4b). Second, exactly TWO definitions, at the very bottom, each with its own
 *  TRUISA DELTA entry. ⛔ Anything added here without such an entry breaks the invariant
 *  this file is judged by:
 *
 *      grep -cE '^function ' model/truisa/truisa_addr_checks.sail   ==  rows in the D-7 table
 *                                                                      (2 == 2 as of D-7)
 *
 *  (`val` lines are the declarations that pair with those two functions, not extra hooks.)
 *
 *  The rest of the address-check hooks come from model/riscv_addr_checks.sail, which
 *  enters the chain at this position as-is. That file was a dormant upstream extension
 *  hook (not compiled at the fork point) until 2026-10-30; it is on the chain now because
 *  "Function ext_pma_check not found" (riscv_mem.sail:161) blocked everything downstream
 *  of memory access.
 *
 *  ⛔ Nothing here may be read as "TruISA has spatial safety". Every hook below is a
 *  permissive stub -- every check it performs currently returns TRUE.
 *=======================================================================================*/

/*=======================================================================================*
 *  TRUISA DELTA (ADR-0017) -- the ten hooks, read one by one.
 *
 *  Method: each row was read out of model/riscv_addr_checks.sail, not inferred from the
 *  name. "Stub?" = can the body ever return a failure?
 *
 *  | # | hook (line)                          | what the body actually does                          | stub? |
 *  |---|--------------------------------------|------------------------------------------------------|-------|
 *  | 1 | ext_fetch_check_pc          (:17)    | Ext_FetchAddr_OK(Virtaddr(pc))                       | YES   |
 *  | 2 | ext_handle_fetch_check_error(:20)    | ()                                                   | YES   |
 *  | 3 | ext_control_check_addr      (:37)    | Ext_ControlAddr_OK(Virtaddr(convertInvalidAddr(pc))) | YES   |
 *  | 4 | ext_control_check_pc        (:41)    | same as #3                                           | YES   |
 *  | 5 | ext_handle_control_check_error(:44)  | ()                                                   | YES   |
 *  | 6 | ext_data_get_addr           (:54)    | Virtaddr(X(base) + offset) -> Ext_DataAddr_OK        | YES   |
 *  | 7 | ext_handle_data_check_error (:59)    | ()                                                   | YES   |
 *  | 8 | ext_check_phys_mem_read     (:63)    | Ext_PhysAddr_OK ()                                   | YES   |
 *  | 9 | ext_check_phys_mem_write    (:66)    | Ext_PhysAddr_OK ()                                   | YES   |
 *  |10 | ext_pma_check               (:70)    | `= true`                                             | YES   |
 *
 *  ⭐ Why all ten are YES, in one sentence: #1/#3/#4/#6 only *build* an address and wrap it
 *  in the OK constructor, #2/#5/#7 are `()`, #8/#9 return the OK constructor
 *  unconditionally, #10 is literally `true`. No branch can produce an Ext_*_Error value.
 *
 *  ⚠️ Two of them change meaning under TruISA's pointer model, and both matter for A-3:
 *    - ext_data_get_addr (#6) computes `X(base) + offset`. In this fork `X(r)` is the
 *      register's `address` field (ADR-0029), so the pointer's `bound` and `C` never enter
 *      the computation: a load through an in-bounds pointer and one through a wild pointer
 *      are indistinguishable at this hook. It is exactly the hook CHERI overrides
 *      (cheri/cheri_addr_checks.sail) and one of the two candidate enforcement points in
 *      D-162 section 5.
 *    - ext_control_check_addr (#3) / ext_control_check_pc (#4) call convertInvalidAddr,
 *      which in this chain is `convertInvalidAddrBits` = identity
 *      (riscv_convert_invalid_addr.sail:4; the CHERI overload is not on the chain). They do
 *      not even normalise the address.
 *
 *  Who replaces them: A-3 (架构组). The enforcement point is NOT yet decided, so
 *  ⛔ no TruISA implementation may be written here yet, and ⛔ no claim of ADR-0017
 *  compliance may be made before A-3 lands. The only honest status word: 桩态 (stub state).
 *
 *  ⛔ Constraint 3 of D-162 section 4.3: if a hook is ever found to do a REAL check, stop
 *  and reply -- do not quietly keep it as a stub. As of this writing all ten are stubs.
 *=======================================================================================*/

/*=======================================================================================*
 *  TRUISA DELTA (D-7) -- the two CSR hooks, 4 parameters each.
 *
 *  ⚠️ Why these are NOT taken from base riscv_ext_regs.sail, even though that file passes
 *  all three "can this file be used as-is" questions (no unresolved reference, no name
 *  collision outside model/cheri/, its family is only two names):
 *
 *      base  riscv_ext_regs.sail:17   val ext_check_CSR : (csreg, Privilege, bool, csrop, bool) -> ...
 *                                     5 parameters -- it carries an `is_imm` the call site
 *                                     does not pass
 *      call  riscv_insts_zicsr.sail:47  match ext_check_CSR(csr, cur_privilege(), is_CSR_Write, op)
 *                                     4 parameters
 *
 *  Question 3 ("did we take the whole family") cannot catch this: the names match, the
 *  SHAPE does not. Cause: base riscv_ext_regs.sail is not in the fork-point build list at
 *  all -- the 4-parameter version that this tree needs came from
 *  cheri/cheri_addr_checks.sail:223, and CHERI's copy is exactly where this file mirrors.
 *  Same family as plat_enable_dirty_update() in D-161: a file that exists but was never
 *  compiled.
 *
 *  ext_check_CSR      -> None()  : no extension-level CSR is forbidden. D-127 decision 1 --
 *                                  none of CHERI's 23 CSRs is adopted, and TruISA's own six
 *                                  CSRs go through base check_CSR's encoding table, NOT
 *                                  through this hook.
 *  ext_check_CSR_fail -> ()      : unreachable while the line above always returns None();
 *                                  ext_csr_exc_type exists as a real enum in this fork
 *                                  (D-160) but this hook never produces a value of it.
 *                                  User: riscv_step.sail:204 (Ext_CSR_Check_Failure arm).
 *
 *  ⛔ Stub state, not compliance: this records that TruISA adds no CSR-level access control
 *  beyond base check_CSR. It is NOT a statement that ADR-0017 is implemented.
 *=======================================================================================*/

val ext_check_CSR : (csreg, Privilege, bool, csrop) -> option(ext_csr_exc_type)
function ext_check_CSR (csrno, p, isWrite, op) = None()

val ext_check_CSR_fail : (ext_csr_exc_type) -> unit
function ext_check_CSR_fail (fail_type) = ()
