/*=======================================================================================*/
/*  TruISA: the PAC algorithm -- THE ONLY FILE TO CHANGE WHEN SWAPPING THE MAC.           */
/*                                                                                       */
/*  Nothing here knows the Capability struct: every input and output is a plain bit        */
/*  vector. That is deliberate, and it is what lets this file sit BEFORE                    */
/*  truisa_cap_common.sail in the chain: the width-dependent wrapper (truisaMac, which      */
/*  truncates to truisa_pac_width and zero-extends the message) lives there.               */
/*                                                                                       */
/*  Boundary:                                                                              */
/*    protocol  (cap_common, do NOT touch when swapping)  keySalt / signPtr / verifyPtr /   */
/*                                                        getCapPac / truisaMac             */
/*    algorithm (this file)                               key, fold, MAC                    */
/*=======================================================================================*/

// 1b-1. The key stub. spec/ch04 line 312: xpkey is 128 bits (xpkey1 || xpkey0), and
// xpkey == 0 is a defined-but-empty key.
// Warning: Placeholder for the xpkey CSR, which does not exist yet -- delete this when it lands.
// why: doc/truisa-deltas.md#xpkey
let truisa_xpkey_stub : bits(128) =
  0x0123_4567_89AB_CDEF_0123_4567_89AB_CDEF

// 1b-2. The mixing primitive. spec/ch04 line 314 pins the OUTPUT rule: the MAC yields at
// least PAC_W bits and the PAC slice takes the low ones.
// why: doc/truisa-deltas.md#foldxor

// XOR `x` with itself shifted by w, 2w, ... and keep all 128 bits; the caller takes the low
// PAC_W. That is exactly "split into w-bit blocks, XOR them, zero-extend the last block".
// Warning: `sail_shiftright` is a lib-internal symbol, used deliberately -- `slice` cannot
// express a variable-width chunk.  This file has no idea what PAC_W is.
val  truisa_pac_fold : (bits(128), int, int, bits(128)) -> bits(128)
function truisa_pac_fold(x : bits(128), w : int, i : int, acc : bits(128)) -> bits(128) =
  if i * w >= 128 then acc
  else truisa_pac_fold(x, w, i + 1, acc ^ sail_shiftright(x, i * w))

// 1b-3. The MAC. `msg` arrives already zero-extended to 128 bits, because its real length
// (tag || CentroID || salt) follows the VA profile and this file must not know it.
// `w` IS A PARAMETER, not a constant from cap_common -- that is what keeps this file free
// of any knowledge of PAC_W. The caller truncates the 128-bit result to PAC_W
// (spec/ch04: output >= PAC_W).
// Warning: STUB, as is truisa_xpkey_stub. Never quote its output as a strength figure --
// w = 2 leaves ~1/4 for ANY stub. Real implementations meet ADR-0005 decision 10.
// why: doc/truisa-deltas.md#mac
val  truisa_mac_raw : (bits(128), bits(128), int) -> bits(128)
function truisa_mac_raw(key : bits(128), msg128 : bits(128), w : int) -> bits(128) =
  truisa_pac_fold(key, w, 0, zeros()) ^ truisa_pac_fold(msg128, w, 0, zeros())
