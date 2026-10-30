/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

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

/* Force the PC from C (D-168 / D-13).
 *
 * ⚠️ This function was deleted whole by D-144's CHERI strip, but only ONE of its five
 * lines was CHERI. The baseline (80a9e65) body was:
 *
 *     let addr = truncate(pc, xlen);
 *     PC = addr;                             <- NOT CHERI, belongs to every model
 *     PCC = setCapAddrChecked(PCC, addr);     <- CHERI, and only this line
 *
 * Deleting all five lines removed a function the C emulator still calls
 * (c_emulator/riscv_sim.cpp:443/459 -> zforce_pc, the `z`-prefixed C name of this
 * function), so the emulator failed to compile on an undeclared identifier. This is the
 * strip's boundary being measured wrong -- the opposite face of D-163's "the base file
 * exists but is not usable".
 *
 * ⛔ Nothing CHERI comes back: no PCC, no capability, no check. Just PC. */
val force_pc : bits(64) -> unit
function force_pc(pc : bits(64)) -> unit = {
  let addr = truncate(pc, xlen);
  PC = addr;
}
