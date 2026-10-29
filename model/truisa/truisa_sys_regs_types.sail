/*=======================================================================================*
 *  TruISA: MEnvcfg / SEnvcfg field layouts.
 *
 *  Counterpart: model/cheri/cheri_sys_regs_types.sail.
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that the two
 *  models can be read side by side and every position in model/CMakeLists.txt has a
 *  counterpart.
 *
 *  ⭐ WHAT IS COPIED, AND WHY EXACTLY THAT MUCH
 *  The two bitfields below are `model/riscv_sys_regs_types.sail` lines 1-32, verbatim.
 *  ⛔ The file is 40 lines; lines 33-40 define `bitfield Seccfg`, which
 *  `riscv_sys_regs.sail` ALREADY defines (it is the fork-patched copy that carries the
 *  CHERI `CRE` bit). Copying all 40 would put `Seccfg` into the chain twice and Sail stops
 *  with "Cannot create struct type Seccfg, name is already bound" -- measured, that is the
 *  first error you get if you simply swap in the upstream file.
 *
 *  ⛔ Do NOT take these from cheri/cheri_sys_regs_types.sail instead: its MEnvcfg and
 *  SEnvcfg each carry `CRE : 28`, which would pull a real enable bit into the chain, and
 *  it also defines `Tval2`, which has no definition anywhere in the base tree and no user
 *  on this chain.
 *
 *  ⚠️ `Seccfg.CRE` (bit 3, from riscv_sys_regs.sail) therefore still exists on this chain
 *  and is DEAD: `cheri_registers_enabled()` is defined only in cheri/cheri_sys_regs.sail
 *  and every caller of it is under cheri/. TruISA does not define CRE, no criterion reads
 *  it, writing it changes nothing, and software must not read "mseccfg bit 3 is writable"
 *  as "checks can be turned off" (ADR-0011 section 11.5, D-136). ⛔ Do not delete it: that
 *  file is shared with the baseline chain. ⛔ Do not write tests for it.
 *=======================================================================================*/

bitfield MEnvcfg : bits(64) = {
  // Supervisor TimeCmp Extension
  STCE   : 63,
  // Page Based Memory Types Extension
  PBMTE  : 62,
  // Reserved WPRI bits.
  wpri_1 : 61 .. 8,
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
