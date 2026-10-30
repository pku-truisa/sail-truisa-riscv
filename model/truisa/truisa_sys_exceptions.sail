/*=======================================================================================*
 *  TruISA: the one function the base exception file is missing.
 *
 *  What this file is for: model/riscv_sys_exceptions.sail is in the chain and provides
 *  everything else the trap path needs, but this fork moved `prepare_xret_target` out of
 *  it and into cheri/cheri_sys_exceptions.sail -- while the base caller
 *  (riscv_sys_control.sail, the MRET/SRET arms) kept calling it. The CHERI file says so
 *  itself: "TODO: This is duplicated in 'riscv_sys_exceptions.sail' which is unfortunate."
 *  So the function belongs here rather than in a base file we may not edit (ADR-0024
 *  section 11.4b: base files change only to delete CHERI code).
 *
 *  ⭐ Semantics: TruISA has no PC capability (ADR-0011 decision 2 -- instruction addresses
 *  are plain Bare addresses), so there is no target capability to build, seal or install.
 *  The target is simply the corresponding EPC. Alignment needs no separate step either:
 *  get_mepc()/get_sepc() already return align_pc(...).
 *
 *  ⚠️ CHERI's version does three things this one must not copy: align_pc on the capability
 *  address (already covered by get_*epc), set_next_pcc (there is no PCC register here --
 *  the caller takes the RETURN VALUE as the next PC, see exception_handler), and
 *  unsealCap (TruISA has no sealed capabilities).
 *
 *  ⭐ WHY THERE IS NO set_next_pc IN THIS FUNCTION -- do not "fix" this by adding one.
 *  The PC is set by the caller, one level above the ctl_result match:
 *
 *      riscv_insts_base.sail:547  set_next_pc(exception_handler(cur_privilege(), CTL_MRET(), PC));
 *      riscv_insts_base.sail:571  set_next_pc(exception_handler(cur_privilege(), CTL_SRET(), PC));
 *
 *  and exception_handler itself is `-> xlenbits` (riscv_sys_control.sail:265), returning
 *  whatever this function returned. So the chain is: this function returns the target,
 *  exception_handler returns it unchanged, and the MRET/SRET clause hands it to
 *  set_next_pc. Adding set_next_pc here as well would run it twice -- convertInvalidAddr
 *  is idempotent, but sail_branch_announce is not, and the trace would carry two branch
 *  announcements for one xRET. prepare_trap_vector in riscv_sys_exceptions.sail follows
 *  the same shape: it returns the vector, the caller sets the PC.
 *
 *  ⚠️ The two line numbers above are a snapshot of THIS revision, not a fact about those
 *  files -- a line number points into another tree and drifts silently. Re-derive with
 *      grep -n "set_next_pc(exception_handler" model/riscv_insts_base.sail
 *  before trusting them; the hit count is the evidence, not the number.
 *
 *  ⚠️ The User arm: CHERI raises internal_error there. The ruling for this file is
 *  "Machine => mepc, otherwise => sepc", so User falls through to sepc. Unreachable today
 *  -- the only two call sites pass Machine (MRET) and Supervisor (SRET) -- but noted so
 *  that a future User-mode return does not silently read the supervisor EPC.
 *=======================================================================================*/

val prepare_xret_target : Privilege -> xlenbits
function prepare_xret_target(p : Privilege) -> xlenbits =
  match p {
    Machine    => get_mepc(),
    Supervisor => get_sepc(),
    User       => get_sepc(),   /* unreachable today; see the note above */
  }
