/*=======================================================================================*/
/*  TruISA: the 32-bit capability width, for RV32.                                      */
/*                                                                                       */
/*  Same role as truisa_prelude_64.sail, one step narrower. The blueprint counterpart is  */
/*  cheri_prelude_64.sail -- and, as noted there, the CHERI names are misleading: in      */
/*  CHERI, `_64` is the RV32 case (cap = 64 bits) and `_128` is the RV64 case. TruISA's   */
/*  `_32` (cap = 32 bits) has no CHERI equivalent at all, because CHERI never narrows the  */
/*  capability below 64 bits. It is the RV32 half of TruISA's own two-way split.          */
/*                                                                                       */
/*  ⚠️ This file is NOT a placeholder. cap_size depends only on the capability width,     */
/*  which is 32 bits here, so the value is determined: 4 bytes. Writing it is answering   */
/*  the question, not papering over it (contrast D-69 §5: a stub that merely satisfies    */
/*  the type checker would be different).                                                 */
/*                                                                                       */
/*  ⚠️⚠️ Having this file does NOT make RV32 build. It only supplies the capability       */
/*  width. Three things still block RV32, and none of them is a matter of adding files:   */
/*    - ADR-0003's three VA profiles are 39 / 48 / 57, all wider than 32;                 */
/*    - the pointer's bit fields (mode 1 + N/C 6 + PAC 8 + reserved 1) eat 16 of 32 bits, */
/*      leaving 16 for the address;                                                       */
/*    - truisa_pac_width = 32 - 48 - 1 - 6 = -23, so bits(truisa_pac_width) cannot even   */
/*      be formed.                                                                        */
/*  Do NOT add `constraint xlen == 64` to silence this: that would lock out the very      */
/*  direction this file exists for. Do NOT temporarily shrink truisa_address_width to     */
/*  make RV32 compile either -- the VA profile is a spec decision (ADR-0003), not a       */
/*  convenience.                                                                          */
/*=======================================================================================*/

/* Width of the capability in bytes, as log2. 2 means 2^2 = 4 bytes = 32 bits. */
type log2_cap_size_32 : Int = 2
let  log2_cap_size_32 = sizeof(log2_cap_size_32)
