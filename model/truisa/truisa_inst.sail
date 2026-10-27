/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* Capability versions of mode-dependent instructions */

/* Operations that extract parts of a capability into GPR */

union clause instruction = GCBASE : (regidx, regidx)
union clause instruction = GCBOUND: (regidx, regidx)
union clause instruction = GCADDR : (regidx, regidx)

/*!
 * insnref: gcbase_32bit
 * Capability get base address
 *
 * gcbase rd, rs1
 *
 * Decode the base integer address from rs1's bounds and write the result
 * to rd.
 */

function clause execute (GCBASE(rd, cs1)) = {
  let capVal = X(cs1);
  X(rd) = match getCapBoundsBits(capVal) {
    None() => zeros(),
    Some(base, _) => base
  };
  RETIRE_SUCCESS
}

/*!
 * insnref: gcbound_32bit
 * Capability get bound address
 *
 * gcbase rd, rs1
 *
 * Decode the bound integer address from rs1's bounds and write the result
 * to rd.
 */

function clause execute (GCBOUND(rd, cs1)) = {
  let capVal = X(cs1);
  X(rd) = match getCapBoundsBits(capVal) {
    None() => zeros(),
    Some(_, bound) => bound 
  };
  RETIRE_SUCCESS
}

/*!
 * insnref: gcaddr_32bit
 * Get pointer address
 *
 * gcaddr rd, rs1
 *
 * rd is set to the address field of rs1, sign-extended to XLEN.
 * The tag bits (mode / N/C / PAC) are ignored. A poisoned pointer still
 * yields its real address (only bits 47-0 are read).
 */
function clause execute (GCADDR(rd, cs1)) = {
  X(rd) = sign_extend(X(cs1)[47 .. 0]);
  RETIRE_SUCCESS
}

union clause instruction = CADD : (regidx, regidx, regidx)
/*!
 * insnref: cadd_32bit
 * Capability pointer increment
 *
 * cadd rd, rs1, rs2
 * caddi rd, rs1, imm
 *
 * Increment the address field of the capability rs1  and write the
 * result to rd . The output capability is POISON if rs1 is illegal, 
 * the incremented address is outside rs1's
 * Representable Range or rs1's PAC is checked failed.
 *
 * For CADD, the address is incremented by the value in rs2 .
 * For CADDI, the address is incremented by the immediate value imm.
 */
function clause execute (CADD(cd, cs1, rs2)) = {
  let cs1_val = X(cs1);
  let rs2_val = X(rs2);

  let newCap = incCapAddrChecked(cs1_val, rs2_val);

  C(cd) = newCap;
  RETIRE_SUCCESS
}

union clause instruction = CADDI : (regidx, regidx, bits(12))
/*!
 * insnref: cadd_32bit
 * Capability pointer increment
 *
 * cadd cd, cs1, rs2
 * caddi cd, cs1, imm
 *
 * Increment the address field of the capability cs1  and write the
 * result to cd . The tag bit of the output capability is 0 if cs1  did
 * not have its tag set to 1, the incremented address is outside cs1's
 * Representable Range or cs1  is sealed.
 *
 * For CADD, the address is incremented by the value in rs2 .
 * For CADDI, the address is incremented by the immediate value imm.
 */
function clause execute (CADDI(cd, cs1, imm)) = {
  let cs1_val = C(cs1);
  let immBits : xlenbits = sign_extend(imm);

  let newCap = incCapAddrChecked(cs1_val, immBits);

  C(cd) = newCap;
  RETIRE_SUCCESS
}

union clause instruction = SCADDR : (regidx, regidx, regidx)
/*!
 * insnref: scaddr_32bit
 * Capability set address
 *
 * scaddr cd, cs1, rs2
 *
 * Set the address field of capability cs1 to rs2 and write the output
 * capability to cd. The tag bit of the output capability is 0 if cs1 did
 * not have its tag set to 1, rs2 is outside the Representable Range of
 * cs1 or if cs1 is sealed.
 */
function clause execute (SCADDR(cd, cs1, rs2)) = {
  C(cd) = setCapAddrChecked(C(cs1), X(rs2));
  RETIRE_SUCCESS
}

union clause instruction = SCBNDSI : (regidx, regidx, bits(1), bits(5))
/*!
 * insnref: scbnds_32bit
 * Capability set bounds
 *
 * scbnds cd, cs1, rs2
 * scbndsi cd, cs1, uimm
 *
 * Capability register cd  is set to capability register cs1  with the
 * base address of its bounds replaced with the value of cs1.address and
 * the length of its bounds set to rs2  (or imm). If the resulting
 * capability cannot be represented exactly then set cd.tag to 0. In all
 * cases, cd.tag is set to 0 if its bounds exceed cs1's bounds, cs1's tag
 * is 0  or cs1 is sealed.
 * SCBNDSI uses the s bit to scale the immediate by 4 places
 * immediate = ZeroExtend(s ? uimm<<4 : uimm)
 */
function clause execute (SCBNDSI(cd, cs1, s, uimm5)) = {
  let cs1_val = C(cs1);
  let length : xlenbits =
    if s == 0b1 then zero_extend(uimm5 @ 0b0000) else zero_extend(uimm5);
  let newBase = cs1_val.address;
  let newTop : CapLenBits = zero_extend(newBase) + zero_extend(length);
  // (3) the source interval must contain the request
  // TODO(G2): inCapBoundsNoWrap still uses CHERI's top-based half-open test.
  let inBounds = inCapBoundsNoWrap(cs1_val, newBase, unsigned(length));
  // (4) a covering slot must exist (exact = "representable", over-coverage is OK)
  let (exact, newCap) = setCapBounds(cs1_val, newBase, newTop);
  // Poison instead of trap (spec/insns/scbnds.adoc "异常"):
  //   (1) L = 0   (2) poisoned source   (3) not in bounds   (4) no covering slot
  let cond = (length == zeros()) |
             ((cs1_val.mode == 0b0) & (cs1_val.nc == 0b111111)) |
             not(inBounds) | not(exact);
  C(cd) = poisonIf(newCap, cond);
  RETIRE_SUCCESS
}

union clause instruction = SCBNDS : (regidx, regidx, regidx)
/*!
 * insnref: scbnds_32bit
 * Capability set bounds
 *
 * scbnds cd, cs1, rs2
 * scbndsi cd, cs1, uimm
 *
 * Capability register cd  is set to capability register cs1  with the
 * base address of its bounds replaced with the value of cs1.address and
 * the length of its bounds set to rs2  (or imm). If the resulting
 * capability cannot be represented exactly then set cd.tag to 0. In all
 * cases, cd.tag is set to 0 if its bounds exceed cs1's bounds, cs1's tag
 * is 0  or cs1 is sealed.
 * SCBNDSI uses the s bit to scale the immediate by 4 places
 * immediate = ZeroExtend(s ? uimm<<4 : uimm)
 */
function clause execute (SCBNDS(cd, cs1, rs2)) = {
  let cs1_val = C(cs1);
  let length : xlenbits = X(rs2);
  let newBase = cs1_val.address;
  let newTop : CapLenBits = zero_extend(newBase) + zero_extend(length);
  // (3) the source interval must contain the request
  // TODO(G2): inCapBoundsNoWrap still uses CHERI's top-based half-open test.
  let inBounds = inCapBoundsNoWrap(cs1_val, newBase, unsigned(length));
  // (4) a covering slot must exist
  let (exact, newCap) = setCapBounds(cs1_val, newBase, newTop);
  // Poison instead of trap; same four conditions as SCBNDSI.
  let cond = (length == zeros()) |
             ((cs1_val.mode == 0b0) & (cs1_val.nc == 0b111111)) |
             not(inBounds) | not(exact);
  C(cd) = poisonIf(newCap, cond);
  RETIRE_SUCCESS
}

union clause instruction = CMV : (regidx, regidx)
/*!
 * insnref: cmv_32bit
 * Capability move
 *
 * cmv cd, cs1
 *
 * The contents of capability register cs1  are written to capability
 * register cd. CMV unconditionally moves the whole capability to cd .
 */
function clause execute (CMV(cd, cs1)) = {
  C(cd) = C(cs1);
  RETIRE_SUCCESS
}

union clause instruction = SCEQ : (regidx, regidx, regidx)
/*!
 * insnref: sceq_32bit
 * Set if Capabilities are EQual
 *
 * sceq rd, cs1, cs2
 *
 * rd is set to 1 if all bits (i.e. CLEN bits and the tag) of
 * capabilities cs1 and cs2  are equal, otherwise rd is set to 0.
 */
function clause execute (SCEQ(rd, cs1, cs2)) = {
  let cs1_val = C(cs1);
  let cs2_val = C(cs2);
  X(rd) = zero_extend(bool_to_bits(cs1_val == cs2_val));
  RETIRE_SUCCESS
}

union clause instruction = CSUB   : (regidx, regidx, regidx)
/*!
 * insnref: csub_32bit
 * Pointer address subtraction
 *
 * csub rd, rs1, rs2
 *
 * rd is set to addr(rs1) - addr(rs2), modulo 2^XLEN.
 * Ported from CHERIoT's CSub (cheriot-sail src/cheri_insts.sail:472), with
 * C(x).address replaced by sign_extend(X(x)[47..0]) -- TruISA keeps pointers
 * in the integer register file.
 */
function clause execute (CSUB(rd, cs1, cs2)) = {
  X(rd) = sign_extend(X(cs1)[47 .. 0]) - sign_extend(X(cs2)[47 .. 0]);
  RETIRE_SUCCESS
}

/* Two arg */

mapping clause encdec = GCBASE(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00101 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCADDR(rd, cs1)                                           if cheri_registers_enabled()
  <-> 0b0001000 @ 0b01001 @ encdec_reg(rs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = CSUB(rd, cs1, cs2)                                        if cheri_registers_enabled()
  <-> 0b0001100 @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCBOUND(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b01010 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = CMV(cd, cs1)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ 0b00000 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()

mapping clause assembly = GCBASE(rd, cs1) <-> "gcbase" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCADDR(rd, cs1) <-> "gcaddr" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = CSUB(rd, cs1, cs2) <-> "csub" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)
mapping clause assembly = GCBOUND(rd, cs1) <-> "gcbound" ^ spc() ^ reg_name(rd)   ^ sep() ^ cap_reg_name(cs1)

mapping clause assembly = CMV(cd, cs1)    <-> "cmv"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1)

/* Three arg */

mapping clause encdec = SCADDR(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b001 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = CADD(cd, cs1, rs2)                                               if cheri_registers_enabled() & (rs2 != zreg)
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled() & (rs2 != zreg)
mapping clause encdec = SCBNDS(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000111 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = SCEQ(rd, cs1, cs2)                                               if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b100 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = CADDI(cd, cs1, imm12)                                 if cheri_registers_enabled()
  <-> imm12 : bits(12) @ encdec_reg(cs1) @ 0b010 @ encdec_reg(cd) @ 0b0011011 if cheri_registers_enabled()
mapping clause encdec = SCBNDSI(cd, cs1, s, uimm5)                                                    if cheri_registers_enabled() & not(s == 0b1 & uimm5 <=_u 0b00001)
  <-> 0b000001 @ s : bits(1) @ uimm5 : bits(5) @ encdec_reg(cs1) @ 0b101 @ encdec_reg(cd) @ 0b0010011 if cheri_registers_enabled() & not(s == 0b1 & uimm5 <=_u 0b00001)

mapping clause assembly = SCADDR(cd, cs1, rs2)  <-> "scaddr"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = CADD(cd, cs1, rs2)    <-> "cadd"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCBNDS(cd, cs1, rs2)  <-> "scbnds"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)

mapping clause assembly = SCEQ(rd, cs1, cs2)    <-> "sceq"    ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)

mapping clause assembly = CADDI(cd, cs1, imm12) <-> "caddi"   ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(imm12)

mapping clause assembly = SCBNDSI(cd, cs1, 0b0, uimm5) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b0000000 @ uimm5)
mapping clause assembly = SCBNDSI(cd, cs1, 0b1, uimm5) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b000 @ uimm5 @ 0b0000)
