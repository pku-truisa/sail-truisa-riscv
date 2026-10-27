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
  // TODO(G1): getCapBoundsBits needs the FULL 64-bit pointer to tell the
  // form apart, but X() returns only the address (regval_from_reg =
  // sign_extend(address) after ruling B). Use capToBits(C(cs1)) once
  // capToBits exists.
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
  // TODO(G1): getCapBoundsBits needs the FULL 64-bit pointer to tell the
  // form apart, but X() returns only the address (regval_from_reg =
  // sign_extend(address) after ruling B). Use capToBits(C(cs1)) once
  // capToBits exists.
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
 * cd gets the pointer cs1 with its address incremented by rs2 (or imm).
 * If the source is poisoned, or the new address leaves cs1's slot, cd is
 * set to the poison code.
 *
 * For CADD, the address is incremented by the value in rs2 .
 * For CADDI, the address is incremented by the immediate value imm.
 */
function clause execute (CADD(cd, cs1, rs2)) = {
  let cs1_val = C(cs1);
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
 * cd gets the pointer cs1 with its address incremented by rs2 (or imm).
 * If the source is poisoned, or the new address leaves cs1's slot, cd is
 * set to the poison code.
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
 * cd gets the pointer cs1 with its address replaced by rs2.
 * If the source is poisoned, or the new address leaves cs1's slot, cd is
 * set to the poison code.
 */
function clause execute (SCADDR(cd, cs1, rs2)) = {
  C(cd) = setCapAddrChecked(C(cs1), X(rs2));
  RETIRE_SUCCESS
}

union clause instruction = SCBNDSI : (regidx, regidx, bits(9))
/*!
 * insnref: scbnds_32bit
 * Capability set bounds
 *
 * scbnds cd, cs1, rs2
 * scbndsi cd, cs1, imm
 *
 * Capability register cd  is set to capability register cs1  with the
 * cd becomes an ALIGNED-SLOT pointer: address = cs1.address, and the slot
 * exponent N_c is the smallest one whose slot covers the request length L
 * (rs2 for SCBNDS; a 9-bit bit-remapped immediate for SCBNDSI).
 * On failure -- L = 0, poisoned source, request not inside the source
 * pointer interval, or no covering slot -- cd is set to the poison code
 * (tag 0111111), NOT the CHERI behaviour of clearing a tag bit.
 */
// SCBNDSI immediate: pure bit remapping, no adder and no variable shifter
// (spec/insns/scbnds.adoc "SCBNDSI 的立即数解码"):
//   imm[8:0] = 0                    -> 4096                      (page)
//   imm[8]   = 0, imm[7:0] != 0     -> imm[7:0]                  (1..255, bytes)
//   imm[8]   = 1, imm[7:5] = 0      -> 256 | imm[3:0]<<4 | imm[4]<<3   (256..504, step 8)
//   otherwise                       -> imm[7:0] << 4             (512..4080, step 16)
// NOTE: the spec's third row is written as `256 | (imm[3:0] << 4) | (imm[4] << 3)`
//       while its prose says "256-504, step 8"; those two do not agree
//       (the formula tops out at 392). Implemented literally below; flagged
//       for the architecture group.
val  decode_scbndsi_imm : bits(9) -> xlenbits
function decode_scbndsi_imm(imm : bits(9)) -> xlenbits = {
  if imm == zeros() then
    zero_extend(to_bits(12, 4096))
  else if imm[8] == 0b0 then
    zero_extend(imm[7 .. 0])
  else if imm[7 .. 5] == 0b000 then
    zero_extend(to_bits(12, 256)) +
      (zero_extend(imm[3 .. 0]) << 4) +
      (zero_extend(imm[4]) << 3)
  else
    zero_extend(imm[7 .. 0]) << 4
}

function clause execute (SCBNDSI(cd, cs1, imm)) = {
  let cs1_val = C(cs1);
  let length : xlenbits = decode_scbndsi_imm(imm);
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
 * scbndsi cd, cs1, imm
 *
 * Capability register cd  is set to capability register cs1  with the
 * cd becomes an ALIGNED-SLOT pointer: address = cs1.address, and the slot
 * exponent N_c is the smallest one whose slot covers the request length L
 * (rs2 for SCBNDS; a 9-bit bit-remapped immediate for SCBNDSI).
 * On failure -- L = 0, poisoned source, request not inside the source
 * pointer interval, or no covering slot -- cd is set to the poison code
 * (tag 0111111), NOT the CHERI behaviour of clearing a tag bit.
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
mapping clause encdec = SCBNDSI(cd, cs1, imm)                                    if cheri_registers_enabled()
  <-> 0b111 @ imm : bits(9) @ encdec_reg(cs1) @ 0b101 @ encdec_reg(cd) @ 0b0010011 if cheri_registers_enabled()

mapping clause assembly = SCADDR(cd, cs1, rs2)  <-> "scaddr"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = CADD(cd, cs1, rs2)    <-> "cadd"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCBNDS(cd, cs1, rs2)  <-> "scbnds"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)

mapping clause assembly = SCEQ(rd, cs1, cs2)    <-> "sceq"    ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)

mapping clause assembly = CADDI(cd, cs1, imm12) <-> "caddi"   ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(imm12)

mapping clause assembly = SCBNDSI(cd, cs1, imm) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b111 @ imm)
