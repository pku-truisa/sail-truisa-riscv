/*=======================================================================================*
 *  TruISA: replacement for the fork-patched model/riscv_pc_access.sail.
 *
 *  NOT a mirror position: there is no cheri/cheri_pc_access.sail, because the fork edited
 *  the shared base file in place (adding PCC / nextPCC / set_next_pcc / force_pc). This
 *  file drops all four: TruISA has no PC capability (ADR-0011 decision 2), and none of
 *  them has a reader or caller.
 *
 *  Why a replacement rather than an edit: riscv_pc_access.sail is shared with the baseline
 *  chain (cheri/ has no counterpart, i.e. the fork patched it in place), so changing it
 *  would break the baseline. The chain therefore swaps the file at its own position --
 *  CMakeLists.txt, truisa_arch_srcs.
 *
 *  ⚠️ tick_pc runs on EVERY instruction (riscv_step.sail). Its body is byte-for-byte the
 *  base version minus the `PCC = nextPCC;` assignment: ⛔ do not reorder
 *  `pc_write_callback(PC)` and ⛔ do not "simplify" convertInvalidAddr in set_next_pc --
 *  it is polymorphic and dispatches to convertInvalidAddrBits for xlenbits.
 *=======================================================================================*/

/* accessors for default architectural addresses, for use from within instructions */

/*!
  Retrieves the architectural PC value. This is not necessarily the value
  found in the PC register as extensions may choose to override this function.
  The value in the PC register is the absolute virtual address of the instruction
  to fetch.
 */
val get_arch_pc : unit -> xlenbits
function get_arch_pc() = PC

val get_next_pc : unit -> xlenbits
function get_next_pc() = nextPC

val set_next_pc : xlenbits -> unit
function set_next_pc(pc) = {
  /* could check for internal errors here on invalid pc */
  let pc = convertInvalidAddr(pc);
  sail_branch_announce(xlen, pc);
  nextPC = pc;
}

val tick_pc : unit -> unit
function tick_pc() = {
  PC = nextPC;
  pc_write_callback(PC);
}
