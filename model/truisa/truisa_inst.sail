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

/*!
 * insnref: gcbase_32bit
 * Capability get base address
 *
 * gcbase rd, rs1
 *
 * Decode the base integer address from rs1's bounds and write the result
 * to rd.
 */

function clause execute (GCBASE(rd, rs1)) = {
  let capVal = X(rs1);
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

function clause execute (GCBOUND(rd, rs1)) = {
  let capVal = X(rs1);
  X(rd) = match getCapBoundsBits(capVal) {
    None() => zeros(),
    Some(_, bound) => bound 
  };
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
function clause execute (CADD(rd, rs1, rs2)) = {
  let cs1_val = X(rs1);
  let rs2_val = X(rs2);

  let newCap = incCapAddrChecked(cs1_val, rs2_val);

  C(rd) = newCap;
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

union clause instruction = SCBNDSR : (regidx, regidx, regidx)
/*!
 * insnref: scbndsr_32bit
 * Capability set bounds, rounding up if necessary
 *
 * scbndsr cd, cs1, rs2
 *
 * Capability register cd  is set to capability register cs1  with the
 * base address of its bounds replaced with the value of cs1.address
 * field and the length of its bounds set to rs2. The base is rounded
 * down and the length is rounded up by the smallest amount needed to
 * form a representable capability covering the requested bounds. In all
 * cases, cd.tag is set to 0 if its bounds exceed cs1's bounds, cs1's tag
 * is 0 or cs1  is sealed.
 */
function clause execute (SCBNDSR(cd, cs1, rs2)) = {
  let cs1_val = C(cs1);
  let length = X(rs2);
  let newBase = cs1_val.address;
  let newTop : CapLenBits = zero_extend(newBase) + zero_extend(length);
  assert(2 ^ xlen <= cap_max_len);
  // inCapBoundsNoWrap returns false if the input bounds are malformed.
  let inBounds = inCapBoundsNoWrap(cs1_val, newBase, unsigned(length));
  let (_, newCap) : (bool, Capability) = setCapBounds(cs1_val, newBase, newTop);
  let cond = not(inBounds) |
             boundsMalformed(newCap) |
             not(capReservedValid(newCap)) |
             capIsSealed(newCap);
  C(cd) = clearTagIf(newCap, cond);
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
  let length = if s == 0b1 then uimm5 @ 0b0000 else 0b0000 @ uimm5;
  let newBase = cs1_val.address;
  let newTop : CapLenBits = zero_extend(newBase) + zero_extend(length);
  assert(xlen >= 32);
  assert(512 <= cap_max_len);
  // inCapBoundsNoWrap returns false if the input bounds are malformed.
  let inBounds = inCapBoundsNoWrap(cs1_val, newBase, unsigned(length));
  let (exact, newCap) : (bool, Capability) = setCapBounds(cs1_val, newBase, newTop);
  assert(exact, "SCBNDSI immediate too small for non-exact lengths");
  let cond = not(inBounds) |
             boundsMalformed(newCap) |
             not(capReservedValid(newCap)) |
             capIsSealed(newCap);
  C(cd) = clearTagIf(newCap, cond);
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
  let length = X(rs2);
  let newBase = cs1_val.address;
  let newTop : CapLenBits = zero_extend(newBase) + zero_extend(length);
  assert(2 ^ xlen <= cap_max_len);
  // inCapBoundsNoWrap returns false if the input bounds are malformed.
  let inBounds = inCapBoundsNoWrap(cs1_val, newBase, unsigned(length));
  let (exact, newCap) : (bool, Capability) = setCapBounds(cs1_val, newBase, newTop);
  let cond = not(inBounds & exact) |
             boundsMalformed(newCap) |
             not(capReservedValid(newCap)) |
             capIsSealed(newCap);
  C(cd) = clearTagIf(newCap, cond);
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

union clause instruction = CBLD : (regidx, regidx, regidx)
/*!
 * insnref: cbld_32bit
 * Capability build
 *
 * cbld cd, cs1, cs2
 *
 * Copy cs2 to cd and set cd.tag to 1 if
 *
 * . cs1.tag is set, and
 * . cs1's bounds are not malformed, and all reserved fields are zero,
 * and
 * . cs1's permissions could have been legally produced by ACPERM, and
 * . cs1 is not sealed, and
 * . cs2's permissions and bounds are equal to or a subset of cs1's, and
 * . cs2's bounds are not malformed, and all reserved fields are zero,
 * and
 * . cs2's permissions could have been legally produced by ACPERM, and
 * . All reserved bits in cs2's metadata are 0;
 * Otherwise, copy cs2 to cd and clear cd's tag.
 * CBLD is typically used alongside SCHI to build capabilities from
 * integer values.
 */
function clause execute (CBLD(cd, cs1, cs2)) = {
  let cs1_val = C(cs1);
  let cs2_val = C(cs2);

  let tag = cs1_val.tag &
            not(capIsSealed(cs1_val)) &
            capIsSubset(cs2_val, cs1_val); /* Subset checks for malformed bounds,
                                              perms, and reserved bits */

  C(cd) = { cs2_val with tag = tag };
  RETIRE_SUCCESS
}

union clause instruction = CRAM : (regidx, regidx)
/*!
 * insnref: cram_32bit
 * Get Capability Representable Alignment Mask (CRAM)
 *
 * cram rd, rs1
 *
 * Integer register rd is set to a mask that can be used to round
 * addresses down to a value that is sufficiently aligned to set exact
 * bounds for the nearest representable length of rs1.
 */
function clause execute(CRAM(rd, rs1)) = {
  let len = X(rs1);
  X(rd) = getRepresentableAlignmentMask(len);
  RETIRE_SUCCESS
}

union clause instruction = SCSS : (regidx, regidx, regidx)
/*!
 * insnref: scss_32bit
 * Capability test subset
 *
 * scss rd, cs1, cs2
 *
 * rd is set to 1 if the tag of capabilities cs1 and cs2 are equal and
 * the bounds and permissions of cs2 are a subset of those of cs1.
 * If either cs1 or cs2:
 *
 * . Have bounds which are malformed, or
 * . Have any bits set in reserved fields, or
 * . Have permissions that could not have been legally produced by ACPERM
 * then the instruction returns zero.
 */
function clause execute (SCSS(rd, cs1, cs2)) = {
  let cs1_val = C(cs1);
  let cs2_val = C(cs2);

  X(rd) = zero_extend(bool_bits(
    (cs1_val.tag == cs2_val.tag) &
    capIsSubset(cs2_val, cs1_val) /* capIsSubset returns false if either input
                                     has malformed bounds, perms, or non-zero
                                     reserved bits */
  ));
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

union clause instruction = SENTRY : (regidx, regidx)
/*!
 * insnref: sentry_32bit
 * Seal capability as sealed entry.
 *
 * sentry cd, cs1
 *
 * Capability `cd` is written with the capability in `cs1` with its type bit set to 1.
 * Attempting to seal an already sealed capability will lead to the tag of `cd` being set to 0.
 */
function clause execute (SENTRY(cd, cs1)) = {
  let cs1_val = C(cs1);
  let inCap = clearTagIf(cs1_val, capIsSealed(cs1_val));
  C(cd) = sealCap(inCap);
  RETIRE_SUCCESS
}

enum CapAccessType = { Cap_Read, Cap_Write, Cap_ReadWrite }

function cap_mem_access_exception(auth_val : Capability, Virtaddr(vaddr) : virtaddr, acc_type : CapAccessType) -> option(CapEx) = {
  assert(xlen >= 32);
  assert(cap_size <= cap_max_len);
  if not(capTaggedAndReservedValid(auth_val)) then {
    Some(CapEx_TagViolation)
  } else if capIsSealed(auth_val) then {
    Some(CapEx_SealViolation)
  } else if not((match acc_type {
    Cap_Read => canR(auth_val),
    Cap_Write => canW(auth_val),
    Cap_ReadWrite => canR(auth_val) & canW(auth_val),
  }) : bool) then {
    Some(CapEx_PermissionViolation)
  } else if not(validAddrRange(vaddr, cap_size) | capBoundsInfinite(auth_val)) then {
    Some(CapEx_InvalidAddressViolation)
  } else if not(inCapBounds(auth_val, vaddr, cap_size)) then {
    Some(CapEx_LengthViolation)
  } else {
    None()
  }
}

function cap_mem_standard_errors(auth_val : Capability, vaddr : virtaddr, acc_type : CapAccessType) -> option(ExecutionResult) = {
  match cap_mem_access_exception(auth_val, vaddr, acc_type) {
    Some(e) => {
      Some(CHERI_Exception(CapCheckType_Data, e, vaddr))
    },
    None() => {
      // All loads and stores of capabilities must be aligned.
      if not(is_aligned_addr(vaddr, cap_size)) then {
        Some(Memory_Exception(vaddr, match acc_type {
          Cap_Read => E_Load_Addr_Align(),
          Cap_Write => E_SAMO_Addr_Align(),
          Cap_ReadWrite => E_SAMO_Addr_Align(),
        }))
      } else {
        None()
      }
    },
  }
}

union clause instruction = LoadResCap : (regidx, regidx, bool, bool)
/*
 * insnref: load_res_cap_32bit modedep
 * Load Reserved Capability (LR.C), 32-bit encodings
 *
 * Capability Pointer Mode:
 * lr.c cd, 0(cs1)
 *
 * Integer Pointer Mode:
 * lr.c cd, 0(rs1)
 *
 * Capability Pointer Mode:
 * Load reserved instructions, authorised by the capability in cs1. All
 * misaligned load reservations cause a load address misaligned exception
 * to allow software emulation (Zam extension, see citation).
 *
 * Integer Pointer Mode:
 * Load reserved instructions, authorised by the capability in ddc. All
 * misaligned load reservations cause a load address misaligned exception
 * to allow software emulation (Zam extension, see citation).
 */
function clause execute (LoadResCap(cd, rs1_cs1, aq, rl)) = {
  let (auth_val, vaddr) = get_cheri_mode_cap_addr(rs1_cs1, zeros());

  match cap_mem_standard_errors(auth_val, vaddr, Cap_Read) {
    Some(r) => r,
    None() => {
      // If we don't have C capability then the tag will always be cleared and
      // it is treated as an untagged load.
      match translateAddr(vaddr, Read(if canC(auth_val) then Tagged else Data)) {
        Err(e, ext_ptw)          => Translate_Exception(vaddr, e, ext_ptw),
        Ok(addr, pbmt, ext_ptw) => {
          let c = mem_read_cap(Read(Data), addr, pbmt, aq, aq & rl, true);
          match c {
            Ok(v) => {
              if v.tag & ext_ptw.tagged_load_behaviour == TaggedLoadTrap then {
                Translate_Exception(vaddr, E_Load_Page_Fault(), { ext_ptw with cheri_page_fault = PageFault_Cheri })
              } else {
                load_reservation(bits_of_physaddr(addr));
                let cr = clearTagIf(v, ext_ptw.tagged_load_behaviour == TaggedLoadClear | not(canC(auth_val)));
                C(cd) = legalizeLoadedPermissions(cr, auth_val);
                RETIRE_SUCCESS
              }
            },
            Err(e) => Memory_Exception(vaddr, e),
          }
        }
      }
    },
  }
}

union clause instruction = LoadCapImm : (regidx, regidx, bits(12))
/*!
 * insnref: load_32bit_cap modedep
 * Load capability
 *
 * Capability Pointer Mode:
 * lc cd, offset(cs1)
 *
 * Integer Pointer Mode:
 * lc cd, offset(rs1)
 *
 * Capability Pointer Mode:
 * Load a CLEN+1 bit value from memory and writes it to cd. The
 * capability in cs1 authorizes the operation. The effective address of
 * the memory access is obtained by adding the address of cs1 to the
 * sign-extended 12-bit offset. The tag value written to cd is 0 if the
 * tag of the memory location loaded is 0 or cs1 does not grant
 * C-permission.
 *
 * Integer Pointer Mode:
 * Loads a CLEN+1 bit value from memory and writes it to cd. The
 * capability authorising the operation is ddc. The effective address of
 * the memory access is obtained by adding rs1 to the sign-extended
 * 12-bit offset. The tag value written to cd is 0 if the tag of the
 * memory location loaded is 0 or ddc does not grant C-permission.
 */
function clause execute LoadCapImm(cd, rs1_cs1, imm) = {
  let offset : xlenbits = sign_extend(imm);
  let (auth_val, vaddr) = get_cheri_mode_cap_addr(rs1_cs1, offset);

  match cap_mem_standard_errors(auth_val, vaddr, Cap_Read) {
    Some(r) => r,
    None() => {
      // If we don't have C capability then the tag will always be cleared and
      // it is treated as an untagged load.
      match translateAddr(vaddr, Read(if canC(auth_val) then Tagged else Data)) {
        Err(e, ext_ptw)          => Translate_Exception(vaddr, e, ext_ptw),
        Ok(addr, pbmt, ext_ptw) => {
          let aq = false;
          let rl = false;
          match mem_read_cap(Read(Data), addr, pbmt, aq, aq & rl, false) {
            Ok(v) => {
              if v.tag & ext_ptw.tagged_load_behaviour == TaggedLoadTrap then {
                Translate_Exception(vaddr, E_Load_Page_Fault(), { ext_ptw with cheri_page_fault = PageFault_Cheri })
              } else {
                let cr = clearTagIf(v, ext_ptw.tagged_load_behaviour == TaggedLoadClear | not(canC(auth_val)));
                C(cd) = legalizeLoadedPermissions(cr, auth_val);
                RETIRE_SUCCESS
              }
            },
            Err(e) => Memory_Exception(vaddr, e),
          }
        }
      }
    },
  }
}

union clause instruction = StoreCapImm : (regidx, regidx, bits(12))
/*!
 * insnref: store_32bit_cap modedep
 * Store capability
 *
 * Capability Pointer Mode:
 * sc cs2, offset(cs1)
 *
 * Integer Pointer Mode:
 * sc cs2, offset(rs1)
 *
 * Capability Pointer Mode:
 * Store the CLEN+1 bit value in cs2 to memory. The capability in cs1
 * authorizes the operation. The effective address of the memory access
 * is obtained by adding the address of cs1 to the sign-extended 12-bit
 * offset. The capability written to memory has the tag set to 0 if the
 * tag of cs2 is 0 or cs1 does not grant C-permission.
 *
 * Integer Pointer Mode:
 * Store the CLEN+1 bit value in cs2 to memory. The capability
 * authorising the operation is ddc. The effective address of the memory
 * access is obtained by adding rs1 to the sign-extended 12-bit offset.
 * The capability written to memory has the tag set to 0 if cs2's tag is
 * 0 or ddc does not grant C-permission.
 */
function clause execute StoreCapImm(cs2, rs1_cs1, imm) = {
  let offset : xlenbits = sign_extend(imm);
  let (auth_val, vaddr) = get_cheri_mode_cap_addr(rs1_cs1, offset);

  match cap_mem_standard_errors(auth_val, vaddr, Cap_Write) {
    Some(r) => r,
    None() => {
      let cs2_val = C(cs2);
      let cs2_val = clearTagIf(cs2_val, not(canC(auth_val)));
      let cs2_val = legalizeStoredPermissions(cs2_val, auth_val);

      match translateAddr(vaddr, Write(if cs2_val.tag then Tagged else Data)) {
        Err(e, ext_ptw)    => Translate_Exception(vaddr, e, ext_ptw),
        Ok(addr, pbmt, _) => {
          let aq = false;
          let rl = false;
          match mem_write_ea_cap(addr, aq & rl, rl, false) {
            Err(e) => { Memory_Exception(vaddr, e) },
            Ok(_)  => {
              match mem_write_cap(addr, pbmt, cs2_val, aq & rl, rl, false) {
                Ok(true)  => RETIRE_SUCCESS,
                Ok(false) => internal_error(__FILE__, __LINE__, "store got false from mem_write_value"),
                Err(e)    => Memory_Exception(vaddr, e),
              }
            }
          }
        }
      }
    },
  }
}

union clause instruction = StoreCondCap : (regidx, regidx, regidx, bool, bool)
/*!
 * insnref: store_cond_cap_32bit modedep
 * Store Conditional (SC.C), 32-bit encoding
 *
 * Capability Pointer Mode:
 * sc.c rd, cs2, 0(cs1)
 *
 * Integer Pointer Mode:
 * sc.c rd, cs2, 0(rs1)
 *
 * Capability Pointer Mode:
 * Store conditional instructions, authorised by the capability in cs1.
 * All misaligned store conditionals cause a store/AMO address misaligned
 * exception to allow software emulation (Zam extension, see citation).
 *
 * Integer Pointer Mode:
 * Store conditional instructions, authorised by the capability in ddc.
 * All misaligned store conditionals cause a store/AMO address misaligned
 * exception to allow software emulation (Zam extension, see citation).
 */
function clause execute StoreCondCap(rd, cs2, rs1_cs1, aq, rl) = {
  let (auth_val, vaddr) = get_cheri_mode_cap_addr(rs1_cs1, zeros());

  match cap_mem_standard_errors(auth_val, vaddr, Cap_Write) {
    Some(r) => r,
    None() => {
      let cs2_val = C(cs2);
      let cs2_val = clearTagIf(cs2_val, not(canC(auth_val)));
      let cs2_val = legalizeStoredPermissions(cs2_val, auth_val);

      match translateAddr(vaddr, Write(if cs2_val.tag then Tagged else Data)) {
        Err(e, ext_ptw)    => Translate_Exception(vaddr, e, ext_ptw),
        Ok(addr, pbmt, _) => {
          if not(match_reservation(bits_of_physaddr(addr))) then {
            /* cannot happen in rmem */
            X(rd) = zero_extend(0b1);
            cancel_reservation();
            RETIRE_SUCCESS
          } else {
            match mem_write_ea_cap(addr, aq & rl, rl, true) {
              Err(e) => Memory_Exception(vaddr, e),
              Ok(_)  => {
                match mem_write_cap(addr, pbmt, cs2_val, aq & rl, rl, true) {
                  Ok(true) => {
                    X(rd) = zero_extend(0b0);
                    cancel_reservation();
                    RETIRE_SUCCESS
                  },
                  Ok(false) => {
                    X(rd) = zero_extend(0b1);
                    cancel_reservation();
                    RETIRE_SUCCESS
                  },
                  Err(e) => Memory_Exception(vaddr, e),
                }
              }
            }
          }
        }
      }
    },
  }
}

union clause instruction = AMOSwapCap : (regidx, regidx, regidx, bool, bool)
/*!
 * insnref: amoswap_32bit_cap modedep
 * Atomic Operation (AMOSWAP.C), 32-bit encoding
 *
 * Capability Pointer Mode:
 * amoswap.c cd, cs2, offset(cs1)
 *
 * Integer Pointer Mode:
 * amoswap.c cd, cs2, offset(rs1)
 *
 * Capability Pointer Mode:
 * Atomic swap of capability type, authorised by the capability in cs1.
 *
 * Integer Pointer Mode:
 * Atomic swap of capability type, authorised by the capability in ddc.
 */
function clause execute AMOSwapCap(cd, cs2, rs1_cs1, aq, rl) = {
  let (auth_val, vaddr) = get_cheri_mode_cap_addr(rs1_cs1, zeros());

  match cap_mem_standard_errors(auth_val, vaddr, Cap_ReadWrite) {
    Some(r) => r,
    None() => {
      let cs2_val = C(cs2);
      let cs2_val = clearTagIf(cs2_val, not(canC(auth_val)));
      let cs2_val = legalizeStoredPermissions(cs2_val, auth_val);

      // If we don't have C capability then the tag will always be cleared and
      // it is treated as an untagged access.
      let typ = ReadWrite(if canC(auth_val) then Tagged else Data, if cs2_val.tag then Tagged else Data);

      match translateAddr(vaddr, typ) {
        Err(e, ext_ptw)          => Translate_Exception(vaddr, e, ext_ptw),
        Ok(addr, pbmt, ext_ptw) => {
          match mem_write_ea_cap(addr, aq & rl, rl, false) {
            Err(e) => Memory_Exception(vaddr, e),
            Ok(_)  => {
              match mem_read_cap(typ, addr, pbmt, aq, aq & rl, false) {
                Ok(v) => {
                  match mem_write_cap(addr, pbmt, cs2_val, aq & rl, rl, false) {
                    Ok(_) => {
                      if v.tag & ext_ptw.tagged_load_behaviour == TaggedLoadTrap then {
                        Translate_Exception(vaddr, E_Load_Page_Fault(), { ext_ptw with cheri_page_fault = PageFault_Cheri })
                      } else {
                        let cr = clearTagIf(v, ext_ptw.tagged_load_behaviour == TaggedLoadClear | not(canC(auth_val)));
                        C(cd) = legalizeLoadedPermissions(cr, auth_val);
                        RETIRE_SUCCESS
                      }
                    },
                    Err(e) => Memory_Exception(vaddr, e),
                  }
                },
                Err(e) => Memory_Exception(vaddr, e),
              }
            }
          }
        }
      }
    },
  }
}

/* Zero arg */

mapping execution_mode_funct7 : ExecutionMode <-> bits(7) = {
  CapPtrMode <-> 0b0001001,
  IntPtrMode <-> 0b0001010,
}

mapping clause encdec = MODESW(mode)                                                if cheri_registers_enabled()
  <-> execution_mode_funct7(mode) @ 0b00000 @ 0b00000 @ 0b001 @ 0b00000 @ 0b0110011 if cheri_registers_enabled()

mapping execution_mode_mnemonic : ExecutionMode <-> string = {
  CapPtrMode <-> "cap",
  IntPtrMode <-> "int",
}

mapping clause assembly = MODESW(mode) <-> "modesw." ^ execution_mode_mnemonic(mode)

/* Two arg */

mapping clause encdec = GCMODE(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00011 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCTYPE(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00010 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCPERM(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00001 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCBASE(rd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00101 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCLEN(rd, cs1)                                           if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00110 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCTAG(rd, cs1)                                           if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00000 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = GCHI(rd, cs1)                                            if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00100 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = CMV(cd, cs1)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ 0b00000 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SENTRY(cd, cs1)                                          if cheri_registers_enabled()
  <-> 0b0001000 @ 0b01000 @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = CRAM(rd, rs1)                                            if cheri_registers_enabled()
  <-> 0b0001000 @ 0b00111 @ encdec_reg(rs1) @ 0b000 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()

mapping clause assembly = GCMODE(rd, cs1) <-> "gcmode" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCTYPE(rd, cs1) <-> "gctype" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCPERM(rd, cs1) <-> "gcperm" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCBASE(rd, cs1) <-> "gcbase" ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCLEN(rd, cs1)  <-> "gclen"  ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCTAG(rd, cs1)  <-> "gctag"  ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = GCHI(rd, cs1)   <-> "gchi"   ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1)

mapping clause assembly = CMV(cd, cs1)    <-> "cmv"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1)
mapping clause assembly = SENTRY(cd, cs1) <-> "sentry" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1)

mapping clause assembly = CRAM(rd, rs1)   <-> "cram"   ^ spc() ^ reg_name(rd)     ^ sep() ^ reg_name(rs1)

/* Three arg */

mapping clause encdec = ACPERM(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b010 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SCMODE(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b111 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SCADDR(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b001 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SCHI(cd, cs1, rs2)                                               if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b011 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = CADD(cd, cs1, rs2)                                               if cheri_registers_enabled() & (rs2 != zreg)
  <-> 0b0000110 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled() & (rs2 != zreg)
mapping clause encdec = SCBNDSR(cd, cs1, rs2)                                            if cheri_registers_enabled()
  <-> 0b0000111 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b001 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SCBNDS(cd, cs1, rs2)                                             if cheri_registers_enabled()
  <-> 0b0000111 @ encdec_reg(rs2) @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = CBLD(cd, cs1, cs2)                                               if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b101 @ encdec_reg(cd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = SCEQ(rd, cs1, cs2)                                               if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b100 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()
mapping clause encdec = SCSS(rd, cs1, cs2)                                               if cheri_registers_enabled()
  <-> 0b0000110 @ encdec_reg(cs2) @ encdec_reg(cs1) @ 0b110 @ encdec_reg(rd) @ 0b0110011 if cheri_registers_enabled()

mapping clause encdec = CADDI(cd, cs1, imm12)                                 if cheri_registers_enabled()
  <-> imm12 : bits(12) @ encdec_reg(cs1) @ 0b010 @ encdec_reg(cd) @ 0b0011011 if cheri_registers_enabled()
mapping clause encdec = SCBNDSI(cd, cs1, s, uimm5)                                                    if cheri_registers_enabled() & not(s == 0b1 & uimm5 <=_u 0b00001)
  <-> 0b000001 @ s : bits(1) @ uimm5 : bits(5) @ encdec_reg(cs1) @ 0b101 @ encdec_reg(cd) @ 0b0010011 if cheri_registers_enabled() & not(s == 0b1 & uimm5 <=_u 0b00001)

mapping clause assembly = ACPERM(cd, cs1, rs2)  <-> "acperm"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCMODE(cd, cs1, rs2)  <-> "scmode"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCADDR(cd, cs1, rs2)  <-> "scaddr"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCHI(cd, cs1, rs2)    <-> "schi"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = CADD(cd, cs1, rs2)    <-> "cadd"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCBNDSR(cd, cs1, rs2) <-> "scbndsr" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = SCBNDS(cd, cs1, rs2)  <-> "scbnds"  ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ reg_name(rs2)
mapping clause assembly = CBLD(cd, cs1, cs2)    <-> "cbld"    ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)

mapping clause assembly = SCEQ(rd, cs1, cs2)    <-> "sceq"    ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)
mapping clause assembly = SCSS(rd, cs1, cs2)    <-> "scss"    ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ cap_reg_name(cs2)

mapping clause assembly = CADDI(cd, cs1, imm12) <-> "caddi"   ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(imm12)

mapping clause assembly = SCBNDSI(cd, cs1, 0b0, uimm5) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b0000000 @ uimm5)
mapping clause assembly = SCBNDSI(cd, cs1, 0b1, uimm5) <-> "scbndsi" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(0b000 @ uimm5 @ 0b0000)

/* Loads and stores */

let haveRV128 = xlen >= 128
let haveRV64  = xlen >= 64

mapping clause encdec = LoadCapImm(cd, rs1, offset)                 if cheri_registers_enabled()  /* lc */
  <-> offset @ encdec_reg(rs1) @ 0b100 @ encdec_reg(cd) @ 0b0001111 if cheri_registers_enabled()

mapping clause encdec = StoreCapImm(cs2, rs1, off7 @ off5)                                    if cheri_registers_enabled()
  <-> off7 : bits(7) @ encdec_reg(cs2) @ encdec_reg(rs1) @ 0b100 @ off5 : bits(5) @ 0b0100011 if cheri_registers_enabled() /* sc */

mapping clause assembly = LoadCapImm(cd, rs1, offset)   <-> "lc" ^ spc() ^ cap_reg_name(cd)  ^ sep() ^ hex_bits_12(offset) ^ opt_spc() ^ "(" ^ opt_spc() ^ reg_name(rs1) ^ opt_spc() ^ ")"
mapping clause assembly = StoreCapImm(cs2, rs1, offset) <-> "sc" ^ spc() ^ cap_reg_name(cs2) ^ sep() ^ hex_bits_12(offset) ^ opt_spc() ^ "(" ^ opt_spc() ^ reg_name(rs1) ^ opt_spc() ^ ")"

mapping clause encdec = LoadResCap(cd, rs1, aq, rl)                                                            if cheri_registers_enabled() & currentlyEnabled(Ext_Zalrsc)
  <-> 0b00010 @ bool_bits(aq) @ bool_bits(rl) @ 0b00000 @ encdec_reg(rs1) @ 0b100 @ encdec_reg(cd) @ 0b0101111 if cheri_registers_enabled() & currentlyEnabled(Ext_Zalrsc) /* lr.c */

mapping clause encdec = StoreCondCap(rd, cs2, rs1, aq, rl)                                                             if cheri_registers_enabled() & currentlyEnabled(Ext_Zalrsc)
  <-> 0b00011 @ bool_bits(aq) @ bool_bits(rl) @ encdec_reg(cs2) @ encdec_reg(rs1) @ 0b100 @ encdec_reg(rd) @ 0b0101111 if cheri_registers_enabled() & currentlyEnabled(Ext_Zalrsc) /* sc.c */

mapping clause encdec = AMOSwapCap(cd, cs2, rs1, aq, rl)                                                               if cheri_registers_enabled() & currentlyEnabled(Ext_Zaamo)
  <-> 0b00001 @ bool_bits(aq) @ bool_bits(rl) @ encdec_reg(cs2) @ encdec_reg(rs1) @ 0b100 @ encdec_reg(cd) @ 0b0101111 if cheri_registers_enabled() & currentlyEnabled(Ext_Zaamo) /* amoswap.c */

mapping clause assembly = LoadResCap(cd, rs1, aq, rl)        <-> "lr.c"      ^ maybe_aqrl(aq, rl) ^ spc() ^ cap_reg_name(cd) ^ sep() ^ reg_name(rs1)
mapping clause assembly = StoreCondCap(rd, cs2, rs1, aq, rl) <-> "sc.c"      ^ maybe_aqrl(aq, rl) ^ spc() ^ reg_name(rd)     ^ sep() ^ cap_reg_name(cs2) ^ sep() ^ reg_name(rs1)
mapping clause assembly = AMOSwapCap(cd, cs2, rs1, aq, rl)   <-> "amoswap.c" ^ maybe_aqrl(aq, rl) ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs2) ^ sep() ^ reg_name(rs1)

/*
  CHERI really needs sub word atomic operations because bounds checks mean you
  can't implement them in software with word sized operations. The RISC-V
  spec. does not define lr / sc for bytes or half words although the obvious
  encodings are vacant. Since the base Sail model actually implements the unused
  widths but refuses to decode them we can implement them for CHERI simply by
  adding the decodings here.
*/
mapping clause encdec = LOADRES(aq, rl, rs1, size, rd)
  <-> 0b00010 @ bool_bits(aq) @ bool_bits(rl) @ 0b00000 @ encdec_reg(rs1) @ 0b0 @ size_enc(size) @ encdec_reg(rd) @ 0b0101111
      when currentlyEnabled(Ext_Zalrsc) & ((size == 1) | (size == 2))
mapping clause encdec = STORECON(aq, rl, rs2, rs1, size, rd)
  <-> 0b00011 @ bool_bits(aq) @ bool_bits(rl) @ encdec_reg(rs2) @ encdec_reg(rs1) @ 0b0 @ size_enc(size) @ encdec_reg(rd) @ 0b0101111
      when currentlyEnabled(Ext_Zalrsc) & ((size == 1) | (size == 2))

/*
 * Encoding/assembly mappings for capmode specific instructions. This does not
 * include loads/stores since they are not decoded differently, but instead
 * use hooks for semantic differences.
 */
mapping clause encdec_capmode = AUIPC_capmode(imm, cd)
  <-> imm @ encdec_reg(cd) @ 0b0010111
mapping clause assembly = AUIPC_capmode(imm, cd)
  <-> "auipc" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ hex_bits_20(imm)
mapping clause encdec_capmode = JALR_capmode(imm, cs1, cd)
  <-> imm @ encdec_reg(cs1) @ 0b000 @ encdec_reg(cd) @ 0b1100111
mapping clause assembly = JALR_capmode(imm, cs1, cd)
  <-> "jalr" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ cap_reg_name(cs1) ^ sep() ^ hex_bits_12(imm)
/* See `mapping clause encdec = RISCV_JAL` for why we have to use this syntax */
mapping clause encdec_capmode = JAL_capmode(imm_19 @ imm_7_0 @ imm_8 @ imm_18_13 @ imm_12_9 @ 0b0, cd)
  <-> imm_19 : bits(1) @ imm_18_13 : bits(6) @ imm_12_9 : bits(4) @ imm_8 : bits(1) @ imm_7_0 : bits(8) @ encdec_reg(cd) @ 0b1101111
mapping clause assembly = JAL_capmode(imm, cd)
  <-> "jal" ^ spc() ^ cap_reg_name(cd) ^ sep() ^ hex_bits_21(imm)
