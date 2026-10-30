/*=======================================================================================*
 *  TruISA: annotation carrier for `riscv_addr_checks.sail` -- which IS in the chain now.
 *
 *  ⚠️ This file defines NOTHING. It exists because D-162 section 4.3 constraint 1 requires
 *  the stub/real distinction to be recorded *next to the position it governs*, in a file
 *  the rule checkers can grep -- and the base file itself may not be edited
 *  (ADR-0024 section 11.4b).
 *
 *  The definitions come from model/riscv_addr_checks.sail, which enters the chain at this
 *  position as-is. That file was a dormant upstream extension hook (not compiled at the
 *  fork point) until 2026-10-30; it is on the chain now because "Function ext_pma_check
 *  not found" (riscv_mem.sail:161) blocks everything downstream of memory access.
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
