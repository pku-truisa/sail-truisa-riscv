/*=======================================================================================*/
/*  TruISA: the PC accessors. PCC is the single authority; PC is a mirror (D-411 甲2).   */
/*                                                                                       */
/*  Replaces `riscv_pc_access.sail` in the chain -- that file is not edited, it is        */
/*  simply not linked. Sail rejects a second definition of a `function`, so exactly one   */
/*  of the two may be in the source list (the blueprint does the same: its Makefile has   */
/*  `cheri_pc_access.sail` and never `riscv_pc_access.sail`).                              */
/*=======================================================================================*/

register PCC     : Capability
register nextPCC : Capability

val get_arch_pc : unit -> xlenbits
function get_arch_pc() = PCC.address

val get_next_pc : unit -> xlenbits
function get_next_pc() = nextPCC.address

// Metadata is carried over from the current PC (`ch06` five-source table, first three
// rows). The JALR family takes its metadata from cs1 and is a later batch (ADR-0036).
val set_next_pc : xlenbits -> unit
function set_next_pc(pc) = {
  sail_branch_announce(xlen, pc);
  nextPCC = struct { mode = PCC.mode, nc = PCC.nc, pac = PCC.pac, address = pc };
}

val tick_pc : unit -> unit
function tick_pc() = {
  PCC = nextPCC;
  PC = PCC.address;
  pc_write_callback(PC);
}

// The reset vector enters here: the C side calls force_pc(rom_base) / force_pc(elf_entry).
// Metadata stays as-is (null_cap, encoding-unavailable) until CRE is latched (P1-c).
//
// ⚠️ nextPCC and nextPC must be set too: `tick_pc` commits at the END of a step and
// writes `PC <- nextPC`; after reset `nextPC` holds no valid value, so it is set here.
val force_pc : bits(64) -> unit
function force_pc(pc) = {
  let addr = truncate(pc, xlen);
  PCC = struct { mode = PCC.mode, nc = PCC.nc, pac = PCC.pac, address = addr };
  nextPCC = PCC;
  PC = addr;
  nextPC = addr;
}

// Writes the link register as a full pointer (ADR-0035 decision 11.2 #1). Three things
// must hold: go through `wX_full` (`wX` would zero the metadata via regval_into_reg),
// keep `xreg_write_callback` -- it takes the address, not the pointer -- and take the
// address from `get_next_pc()` while the metadata comes from `PCC`, i.e. the old pc.
// Lives here because it needs both `PCC` and `get_next_pc`; the callers sit later.
val wLinkReg : regidx -> unit
function wLinkReg(Regidx(i) : regidx) = {
  let addr = get_next_pc();
  let ptr : Capability = struct { mode = PCC.mode, nc = PCC.nc, pac = PCC.pac,
                                  address = addr };
  wX_full(Regno(unsigned(i)), ptr);
  if unsigned(i) != 0 then xreg_write_callback(Regidx(i), addr);
}
