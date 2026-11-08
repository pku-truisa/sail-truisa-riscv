/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* The definition for the memory model. */

function clause execute (JALR(imm, rs1, rd)) = {
  /* FIXME: this does not check for a misaligned target address. See riscv_jalr_seq.sail. */
  /* write rd before anything else to prevent unintended strength */
  /* Synced with riscv_jalr_seq.sail for wLinkReg (ADR-0035 decision 11.2 #6-7).
     ⚠️ This file is NOT in the chain, so this line is UNVERIFIED. */
  wLinkReg(rd);                 /* compatible with JALR, C.JR and C.JALR */
  let newPC : xlenbits = X(rs1) + sign_extend(imm);
  nextPC = [newPC with 0 = bitzero];  /* Clear newPC[0] */
  RETIRE_SUCCESS
}
