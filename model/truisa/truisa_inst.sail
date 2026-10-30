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
 * Get the first byte of the slot
 *
 * gcbase rd, cs1
 *
 * Decode the slot base from cs1 and write it to rd, sign-extended from
 * 48 bits (the address field) to XLEN. A poisoned pointer yields 0.
 */

function clause execute (GCBASE(rd, cs1)) = {
  let capVal = C(cs1);
  X(rd) = match getCapBoundsBits(capVal) {
    None() => zeros(),
    Some(base, _) => sign_extend(base)
  };
  RETIRE_SUCCESS
}

/*!
 * insnref: gcbound_32bit
 * Get the last byte of the slot
 *
 * gcbound rd, cs1
 *
 * Decode the slot bound (closed interval, last byte) from cs1 and write it
 * to rd, sign-extended from 48 bits (the address field) to XLEN. A poisoned
 * pointer yields 0.
 */

function clause execute (GCBOUND(rd, cs1)) = {
  let capVal = C(cs1);
  X(rd) = match getCapBoundsBits(capVal) {
    None() => zeros(),
    Some(_, bound) => sign_extend(bound)
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
  /* Slice [VA-1..0] BEFORE extending, and do not simplify this to
   * `C(cs1).address` even though they agree bit for bit on canonical pointers: the
   * slice is the only place a non-canonical address written by wX gets normalised
   * (ADR-0029 decision 7). */
  X(rd) = sign_extend(C(cs1).address[truisa_address_width - 1 .. 0]);
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
  /* ⛔ The delta is the WHOLE XLEN register, not its low VA bits (ADR-0029 decision
   * 10.1). Truncating here would map 2^48 + 1 onto +1 and silently disable criterion
   * (3): the address would wrap instead of poisoning. Wrapping is handled inside the
   * operator, on a 65-bit sum, where the field boundary is still visible. */
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
  /* sign_extend keeps a negative immediate negative. No truncation to VA bits: the
   * operator takes an XLEN delta (ADR-0029 decision 10.1), and |imm| <= 2048 is far
   * below 2^47, so the sign survives the widening anyway. */
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
  // rs2 is an XLEN register but an address is VA bits wide.
  C(cd) = setCapAddrChecked(C(cs1), X(rs2)[truisa_address_width - 1 .. 0]);
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
function clause execute (SCBNDSI(cd, cs1, imm)) = {
  let cs1_val = C(cs1);
  // ADR-0028: the immediate IS the slot exponent N, not a length.
  let nbits : bits(truisa_nc_width) = imm[truisa_nc_width - 1 .. 0];
  // Criterion (3): high bits must be zero -- fail loud. Silently ignoring them
  // is exactly how an old "length" operand would sneak through.
  let hi_ok : bool = imm[8 .. truisa_nc_width] == zeros();
  // Criteria (1)(2)(4) live in setCapBounds: form + N <= VA (via monotonicity)
  // + slot inside the parent's checked interval.
  let (inParent, newCap) = setCapBounds(cs1_val, cs1_val.address[truisa_address_width - 1 .. 0], nbits);
  C(cd) = poisonIf(newCap, not(hi_ok) | not(inParent));
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
  let rs2_val = X(rs2);
  // ADR-0028: rs2[5:0] IS the slot exponent N, not a length.
  let nbits : bits(truisa_nc_width) = rs2_val[truisa_nc_width - 1 .. 0];
  // Criterion (3): everything above N must be zero -- fail loud.
  let hi_ok : bool = rs2_val[xlen - 1 .. truisa_nc_width] == zeros();
  let (inParent, newCap) = setCapBounds(cs1_val, cs1_val.address[truisa_address_width - 1 .. 0], nbits);
  C(cd) = poisonIf(newCap, not(hi_ok) | not(inParent));
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
  /* ⛔ Do NOT compare the two structs directly. address[63:VA] is redundant, so wX can
   * put anything there; structural equality is therefore not pointer equality
   * (ADR-0029 invariant I2). The semantics is "all bits of the encoding are equal"
   * (blueprint 2.8.5.1 p52), so rebuild the 64-bit MEMORY encoding on both sides. */
  let e1 : CapBits = capToMetadataBits(cs1_val) @ cs1_val.address[truisa_address_width - 1 .. 0];
  let e2 : CapBits = capToMetadataBits(cs2_val) @ cs2_val.address[truisa_address_width - 1 .. 0];
  X(rd) = zero_extend(bool_to_bits(e1 == e2));
  RETIRE_SUCCESS
}

union clause instruction = CSUB   : (regidx, regidx, regidx)
/*!
 * insnref: csub_32bit
 * Pointer address subtraction
 *
 * csub rd, cs1, cs2
 *
 * rd is set to the SIGNED address difference addr(cs1) - addr(cs2). Both
 * operands are sign-extended from the 48-bit address field first, so a
 * high-half address counts as negative and the difference has the right sign.
 *
 * ⚠️ Since ADR-0029 decision 7, GCBASE / GCBOUND / GCADDR also sign-extend, so
 * the old "this is deliberately NOT the zero extension those three use" note no
 * longer distinguishes anything -- all four project the same way. What is still
 * specific to CSUB is the VALUE: a signed DISTANCE (the ptrdiff_t quantity),
 * not a field. Zero-extending either operand would flip the sign of any
 * difference taken across bit VA-1 and be off by 2^VA.
 *
 * The [VA-1..0] slice stays even though `address` is now 64 bits wide: it is
 * the normalisation point for non-canonical integers written by wX (decision 7).
 *
 * Ported from CHERIoT's CSub (cheriot-sail src/cheri_insts.sail:472), with
 * C(x).address replaced by sign_extend(X(x)[VA-1..0]) -- TruISA keeps pointers
 * in the integer register file.
 */
function clause execute (CSUB(rd, cs1, cs2)) = {
  X(rd) = sign_extend(C(cs1).address[truisa_address_width - 1 .. 0])
          - sign_extend(C(cs2).address[truisa_address_width - 1 .. 0]);
  RETIRE_SUCCESS
}

/* Two arg */

/* ⚠️ TRUISA DELTA: none of the encdec clauses below carry CHERI's
 * `if cheri_registers_enabled()` guard. The guard is a HYBRID-mode artefact: it stops
 * CHERI instructions from decoding on a core where CHERI is switched off. TruISA has no
 * hybrid mode (ADR-0011: the pointer model follows the privilege level, there is no
 * enable bit and no CSR switch), so the predicate has no TruISA counterpart and the
 * instructions are unconditionally decodable. Deleting the guard is therefore the
 * faithful translation, not a relaxation -- and it drops one CHERI-only name from this
 * file's dependency list (the others are a separate item, not solved by this change).
 *
 * CADD keeps its real discriminator, `(rs2 != zreg)`, which is architectural.
 *
 * ⛔ If a hybrid mode is ever introduced, every clause here needs the guard back
 * (architecture group, 2026-10-29, ruling (c) on the dev reply 16). */

mapping clause encdec = GCBASE(rd, cs1)
  <-> 0b0001000 @ 0b00101 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011
mapping clause encdec = GCADDR(rd, cs1)
  <-> 0b0001000 @ 0b01001 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011
mapping clause encdec = CSUB(rd, cs1, cs2)
  <-> 0b0001100 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011
mapping clause encdec = GCBOUND(rd, cs1)
  <-> 0b0001000 @ 0b01010 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011

mapping clause encdec = CMV(cd, cs1)
  <-> 0b0000110 @ 0b00000 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011

mapping clause assembly = GCBASE(rd, cs1) <-> "gcbase" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCADDR(rd, cs1) <-> "gcaddr" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = CSUB(rd, cs1, cs2) <-> "csub" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)
mapping clause assembly = GCBOUND(rd, cs1) <-> "gcbound" ^ spc() ^ reg_name(rd)   ^ sep() ^ cap_reg_name(cs1)

mapping clause assembly = CMV(cd, cs1)    <-> "cmv"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1)

/* Three arg */

mapping clause encdec = SCADDR(cd, cs1, rs2)
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b001 @ encdec_reg(cd) @ 0b0110011
mapping clause encdec = CADD(cd, cs1, rs2)                                               if (rs2 != zreg)
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if (rs2 != zreg)
mapping clause encdec = SCBNDS(cd, cs1, rs2)
  <-> 0b0000111 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011

mapping clause encdec = SCEQ(rd, cs1, cs2)
  <-> 0b0000110 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b100 @ encdec_reg(rd) @ 0b0110011

mapping clause encdec = CADDI(cd, cs1, imm12)
  <-> imm12 : bits(12) @ encdec_reg(cs1) @ 0b010 @ encdec_reg(cd) @ 0b0011011
mapping clause encdec = SCBNDSI(cd, cs1, imm)
  <-> 0b111 @ imm : bits(9) @ encdec_reg(cs1) @ 0b101 @ encdec_reg(cd) @ 0b0010011

mapping clause assembly = SCADDR(cd, cs1, rs2)  <-> "scaddr"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = CADD(cd, cs1, rs2)    <-> "cadd"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCBNDS(cd, cs1, rs2)  <-> "scbnds"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)

mapping clause assembly = SCEQ(rd, cs1, cs2)    <-> "sceq"    ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)

mapping clause assembly = CADDI(cd, cs1, imm12) <-> "caddi"   ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(imm12)

mapping clause assembly = SCBNDSI(cd, cs1, imm) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b111 @ imm)

/* ====================================================================================
 * The data plane: LC / SC (ADR-0030).
 *
 * A pointer is 80 bits in a register and 64 bits in memory. Until now nothing moved one
 * across that boundary, which meant the "80-bit register representation" was an internal
 * detail no test could exercise. These two instructions are that boundary, and they are
 * the only place where the compression is visible in the ISA:
 *
 *     raw[63 .. 48] = mode @ nc @ pac        (capToMetadataBits)
 *     raw[47 .. 0]  = address[VA-1 .. 0]
 *
 * ⭐ NEITHER instruction verifies the signature. For `sc` the reason is that checking
 * would buy nothing -- an attacker who wants a bad encoding in memory can simply store a
 * value they built by hand, without going through a signed pointer. For `lc` it is
 * consistency with CADD: violations are detected AT THE USE POINT, not at every hop
 * (ADR-0030 decisions 3 and 4 -- decision 4 enumerates the five use points).
 *
 * ⛔ These are NOT `sc.d` / `lr.d`. The `Zalrsc` store-conditional lives in
 * riscv_insts_zalrsc.sail under OP = 0x2F; ours is OP = 0x23 with funct3 = 100, and the
 * mnemonics differ by the absence of a width suffix. An assembler must keep them apart.
 *
 * ⛔ Do not route these through X()/wX: a pointer operand is read with C() and nothing
 * else. Going through the integer view is exactly how the metadata gets lost.
 * ==================================================================================== */

/* --- LC: load 8 bytes and decompress --------------------------------------------- */
union clause instruction = LC : (regidx, regidx, bits(12))
/*!
 * insnref: lc
 * Load capability
 *
 * lc cd, offset(cs1)
 *
 * cd gets the 80-bit pointer decompressed from the 64-bit encoding at memory[cs1+offset].
 * The base address check is the ordinary load path; the LOADED VALUE produces no
 * exception and no poisoning (this instruction does not verify signatures).
 *
 * ⛔ Only valid on an 8-byte object last written by SC. If those 64 bits are an ordinary
 * integer, its bits 63-57 are read as a label and the result is a well-formed pointer
 * made of garbage -- so using LC on integers is UNDEFINED (ADR-0030 decision 5). The
 * load-bearing premise is that the compiler's type information is correct: that is an
 * ABI/toolchain contract, ⛔ not a hardware guarantee.
 *
 * ⚠️ Non-canonical integers do not survive the round trip: compression keeps 48 bits and
 * decompression sign-extends, so a 64-bit value written by wX with a non-canonical high
 * half comes back canonicalised. Same cost as ADR-0029 decision 6, via a second door.
 */
function clause execute (LC(cd, cs1, imm)) = {
  let offset : xlenbits = sign_extend(imm);
  match vmem_read(cs1, offset, 8, Read(Data), false, false, false) {
    Ok(raw) => {
      C(cd) = bitsToCap(false, raw);
      RETIRE_SUCCESS
    },
    Err(e) => e,
  }
}

/* --- SC: compress and store 8 bytes ---------------------------------------------- */
union clause instruction = SC : (regidx, regidx, bits(12))
/*!
 * insnref: sc
 * Store capability
 *
 * sc cs2, offset(cs1)
 *
 * Stores C(cs2) as its 64-bit encoding. No signature check and no table lookup: the
 * STORED VALUE is not validated (ADR-0030 decision 3) -- storing another object's
 * pointer, or the poison code, is legal.
 *
 * ✅ The poison code survives the round trip: 0111111 compresses to 0x7E00_0000_0000_0000
 * and decompresses with the same label, so poisoning propagates through memory.
 *
 * ⛔ Never mix with `sd` on the same object: `sd` does not decompress, so a word written
 * by SC and read by LD silently loses nc and pac (ADR-0030 decision 6). Same for AMO / FP
 * / SIMD on a word written by SC -- the encoding is not a number, and arithmetic carries
 * into the metadata segment (decision 9).
 */
function clause execute (SC(cs2, cs1, imm)) = {
  let offset : xlenbits = sign_extend(imm);
  let raw : CapBits = capToMetadataBits(C(cs2)) @ C(cs2).address[truisa_address_width - 1 .. 0];
  match vmem_write(cs1, offset, 8, raw, Write(Data), false, false, false) {
    Ok(_) => RETIRE_SUCCESS,
    Err(e) => e,
  }
}

/* Encoding and disassembly.
 *
 * `lc` uses funct3 = 100 on OP-FENCE (0x0F), which base RISC-V leaves reserved
 * (fence = 000, fence.i = 001, cbo.* = 010) -- so this defines a reserved encoding rather
 * than working around base.
 *
 * `sc` uses funct3 = 100 on STORE (0x23), unallocated in base (sb/sh/sw/sd use 000-011).
 * The 12-bit offset splits S-type style: imm[11:5] and imm[4:0] around rs2.
 *
 * Both are the CHERI-RISC-V 0.9.3 encodings and mnemonics (ADR-0024 two-tier reading). */
mapping clause encdec = LC(cd, cs1, imm)
  <-> imm @ encdec_reg(cs1) @ 0b100 @ encdec_reg(cd) @ 0b0001111
mapping clause encdec = SC(cs2, cs1, imm)
  <-> imm[11 .. 5] @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b100 @ imm[4 .. 0] @ 0b0100011

mapping clause assembly = LC(cd, cs1, imm)
  <-> "lc" ^ spc() ^ cap_reg_name(cd)  ^ sep() ^ hex_bits_12(imm) ^ opt_spc() ^ "(" ^ opt_spc() ^ reg_name(cs1) ^ opt_spc() ^ ")"
mapping clause assembly = SC(cs2, cs1, imm)
  <-> "sc" ^ spc() ^ cap_reg_name(cs2) ^ sep() ^ hex_bits_12(imm) ^ opt_spc() ^ "(" ^ opt_spc() ^ reg_name(cs1) ^ opt_spc() ^ ")"
