/*=======================================================================================*/
/*  TruISA: the capability itself -- widths, slices, encode/decode, bounds.              */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_cap_common.sail (700 lines).                          */
/*                                                                                       */
/*  Status: 1a DONE, 1b DONE (CR-MAC-01 Rev.1). Widths, the Capability struct, the eight  */
/*  read-only operators, then the MAC stub, sign/verify, makeCapAligned and setCapBounds. */
/*  SCBNDS/SCBNDSI therefore sign now. capToMetadataBits and the bounds decode stay out:  */
/*  TruISA has no metadata and no in-pointer bounds.                                       */
/*=======================================================================================*/

// Widths live in the prelude trio, not here:
//   truisa_prelude_64.sail / _32.sail   the per-XLEN literals
//   truisa_prelude_xlen.sail            picks between them and derives the rest
// This file contains no `if xlen == 32` and must never grow one. If a value needs to differ
// per XLEN, add a candidate there and choose it in prelude_xlen.

/*=======================================================================================*/
/*  1a -- the capability itself, and the operators that only READ it.                     */
/*                                                                                       */
/*  CR-MAC-01 Rev.1 items 1a-1 .. 1a-8. No MAC, no signing, no table: 1b owns those.      */
/*=======================================================================================*/

// Alias layer: names keep the blueprint's spelling so the two files read side by side.
// Every one of them is a RENAME of a prelude width -- none carries a constant of its own,
// and none knows which XLEN it is running on.
type cap_size      : Int = truisa_cap_size
let  cap_size      = sizeof(cap_size)
type log2_cap_size : Int = truisa_log2_cap_size
let  log2_cap_size = sizeof(log2_cap_size)

// The widths below are RENAMES, so that everything after this block speaks `cap_*` and the
// file reads as one unit. ⛔ A `truisa_*` name must not appear below this point (except in
// the algorithm boundary at 1b-3, which calls into truisa_pac.sail by design).
type cap_ptr_width      : Int = truisa_ptr_width
let  cap_ptr_width      = sizeof(cap_ptr_width)
type cap_mode_width     : Int = truisa_mode_width
let  cap_mode_width     = sizeof(cap_mode_width)
type cap_nc_width       : Int = truisa_nc_width
let  cap_nc_width       = sizeof(cap_nc_width)
type cap_address_width  : Int = truisa_address_width
let  cap_address_width  = sizeof(cap_address_width)
type cap_pac_width      : Int = truisa_pac_width
let  cap_pac_width      = sizeof(cap_pac_width)
type cap_tag_width      : Int = truisa_tag_width
let  cap_tag_width      = sizeof(cap_tag_width)
type cap_meta_width     : Int = truisa_meta_width
let  cap_meta_width     = sizeof(cap_meta_width)
type cap_salt_width     : Int = truisa_salt_width
let  cap_salt_width     = sizeof(cap_salt_width)
type cap_mac_msg_width  : Int = truisa_mac_msg_width
let  cap_mac_msg_width  = sizeof(cap_mac_msg_width)

type CapBits     = bits(8 * cap_size)
type CapAddrBits = bits(cap_address_width)
type CapTagBits  = bits(cap_tag_width)

type CapMetaBits = bits(cap_meta_width)

// VA + PAC_W - 1 .. VA -- never literal bit numbers, the slice moves with the profile.
type CapPacBits  = bits(cap_pac_width)

// Entry salt, or all zeros on the aligned path (ADR-0005 rev 11 c3). Warning: The zero segment
// is NOT omitted -- it is what fixes the MAC input length.
type CapSaltBits = bits(cap_salt_width)

// 1a-1. Two views, different widths (ADR-0029 decision 1):
//   memory    mode(1) | N/C(6) | PAC(9) | address(48)   <- CapBits; what SCEQ compares
//   register  mode+NC(7) | PAC(9) | address(64)        <- this struct
// address[63:48] is redundant (dropped on encode, sign-extended back; I1/I2).
// why: doc/truisa-deltas.md#layout
struct Capability = {
  mode    : bits(cap_mode_width),
  nc      : bits(cap_nc_width),
  pac     : bits(cap_pac_width),
  address : bits(cap_ptr_width),
}

// The poison value WITH A ZERO ADDRESS: mode 0, N/C all ones, PAC 0, address 0
// An encoding-unavailable value built from an address: bits 63-48 are a copy of that
// address's bit 47, bits 47-0 are the address itself.
//
// BOTH exits share this constructor -- they differ only in WHICH address goes in
// (spec/ch06 "输入非法出口"):
//   failure exit       (a criterion failed)  -> the CALLER's address   (repair entry, D-291)
//   input-illegal exit (the parent is unavailable) -> the RESULT address (D-318)
// Sharing the shape is deliberate; sharing the argument would erase the distinction.
//
//   bits 63-48 = a copy of bit 47   and   bits 47-0 = the caller's address
//
// so bit47 = 0 gives label 0000000 and bit47 = 1 gives label 1111111. Both are
// encoding-unavailable (getCapForm returns None()), which is what makes the exit
// fail-closed now that there is no third form (D-274/D-276/D-280) and no poisoning
// mechanism (D-280).
//
// Warning: the copy covers bits 56-48 AS WELL -- the 9-bit authentication segment. Do not
// keep it at zero: ch03's "bits 56-48 take no particular value" is about ARBITRARY
// unavailable encodings (e.g. a forged word loaded by LC), not about this exit, which is a
// specially specified one (S-297 section 2).
val  truisaUnavailable : bits(cap_ptr_width) -> Capability
function truisaUnavailable(addr : bits(cap_ptr_width)) -> Capability =
  if addr[cap_address_width - 1] == bitzero then
    struct { mode = 0b0, nc = zeros(), pac = zeros(), address = addr }
  else
    struct { mode = 0b1, nc = ones(),  pac = ones(),  address = addr }

// Notes: There is no `capToBits` any more (ADR-0029 decision 3): with `address` at 64 bits the
// blueprint's own shape applies too (cheri_insts.sail:211). Notes: Do not rescue it.
// encode . decode = id, ONLY on canonical capabilities (ADR-0029 invariant I1): a bare
// integer written by wX is not canonical and does not round-trip. Notes: Never rename this to
// `_tag` -- TruISA has no tag bit (ADR-0003 decision 4).
val  bitsToCap : (bool, CapBits) -> Capability
function bitsToCap(tag : bool, ptr : CapBits) -> Capability =
  struct {
    mode    = ptr[cap_ptr_width - 1 .. cap_ptr_width - cap_mode_width],
    nc      = ptr[cap_ptr_width - cap_mode_width - 1
                  .. cap_address_width + cap_pac_width],
    pac     = ptr[cap_address_width + cap_pac_width - 1 .. cap_address_width],
    /* Sign extension, not zero extension: address[63:48] carries no information, so
     * without a rule the same pointer would have 2^16 representations. Copying bit
     * (VA-1) is the only choice that makes encode . decode = id and that matches the
     * RISC-V canonical address form (ADR-0029 decision 5). */
    address = sign_extend(ptr[cap_address_width - 1 .. 0]),
  }

val  capToMetadataBits : Capability -> CapMetaBits
function capToMetadataBits(cap : Capability) -> CapMetaBits =
  cap.mode @ cap.nc @ cap.pac

/* ------------------------------------------------------------------------------------
 * 1a-4. The 7-bit label (bits 63-57): mode plus N/C. Every form decision hangs off it.
 * The slice is derived from the constants, never written as 63..57 -- that is exactly
 * the hard-coding that made the D-94/D-96 line numbers drift.
 * ---------------------------------------------------------------------------------- */
val  getCapTagBits : Capability -> CapTagBits
function getCapTagBits(cap : Capability) -> CapTagBits =
  capToMetadataBits(cap)[cap_meta_width - 1 .. cap_pac_width]

// 1a-5. Which of the five forms the label denotes (docs/isa/03 section 3.3). The order is
// Order is not negotiable: both Bare codes first (a descriptor with C = 0 encodes as
// 0000000), then the poison code, then bit 63. why: doc/truisa-deltas.md#forms
// None() means "encoding unavailable" -- there is no third form (spec/ch03 3.1).
// The range checks below are the whole test: every rejected label (0000000, 0111111,
// 1111111) falls out of them, so there is no per-label branch to keep in sync.
// why: doc/truisa-deltas.md#forms
val  getCapForm : Capability -> option(CapPtrForm)
function getCapForm(cap : Capability) -> option(CapPtrForm) = {
  let n : int = unsigned(cap.nc);
  if cap.mode == 0b1 then
    (if n <= cap_address_width then Some(FormAligned) else None())
  else
    (if n >= 1 & n <= cap_address_width - 1 then Some(FormDescriptor) else None())
}

// 1a-6. Slot base: S = p with the low N bits cleared, i.e. (p >> N) << N.
// Warning: Written as a shift PAIR, not `p & ~(2^N - 1)`: the mask form needs a negative-shaped
// literal in this width, which Sail will not take.
// why: doc/truisa-deltas.md#slotbase
val  getCapSlotBase : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapSlotBase(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits =
  (p >> unsigned(n)) << unsigned(n)

// 1a-7. CentroID canonical point m = S + 2^(N-1) (ADR-0004: the pair is (m-1, m), and m is
// the canonical one). Returns an ADDRESS, not a key -- the table is keyed by (C, S).
//   N = 0   -> m = S by definition, so m = 0 is reachable and legal (spec/ch04).
//   N = VA  -> m = 0 by ruling (ADR-0026). A different zero, hence D-108.
// Never call 0 "reserved" without naming which case. "1B not in table" (ADR-0006) is a
// matched pair with the N = 0 case: with m = S, an entry at m = 0 collides with address 0.
// why: doc/truisa-deltas.md#centroid
/* There are TWO different quantities here, and folding them into one function is what made
 * D-284 read as "N = 0 returns 0":
 *
 *   m     (MAC input, D-108)  N = 0 -> S (the slot base)   N = 48 -> 2^47
 *   key   (table key, D-66)   N = 0 -> 0 (reserved)        N = 48 -> 2^47
 *
 * They agree at N = 48 and differ ONLY at N = 0. The single caller of the MAC-input form
 * is signPtr; the key form has no caller in phase A (no table yet).
 *
 * N = 48 needs no special case: base = getCapSlotBase(p, 48) = 0 and half = 2^47, so the
 * general formula already yields 2^47. D-284 raised this from the old `zeros()`.
 */
val  getCapMacInput : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapMacInput(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits = {
  // Warning: k must be nat, not int. Written as int (unsigned(n) coerced) Sail cannot prove
  // `k >= 0` and rejects the shift with "Could not resolve quantifiers for shiftl".
  let k : nat = unsigned(n);
  let base : CapAddrBits = getCapSlotBase(p, n);
  if k == 0 then base
  else {
    let twop : bits(64) = 0x0000_0000_0000_0001 << k;
    // Warning: truncate takes TWO arguments in Sail: the value and the target width
    // (bitvector('n), int('m)). One-argument form fails to resolve.
    let half : CapAddrBits = truncate(twop >> 1, cap_address_width);
    base + half
  }
}

// The table key. Same as the MAC input except at N = 0, where a one-byte object has no
// midpoint and the key uses the reserved value 0 (D-66 / isa/03 3.4.4 item 1).
//
// The two quantities differ ONLY at N = 0. The asserts below are the documentation of that
// fact (D-297 3.1) -- they are compile-time, so they also fail the build if either formula
// drifts. p0 is deliberately non-zero: with p = 0 "key is 0" and "m is base = p" would
// coincide and prove nothing.
val  getCapKey : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapKey(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits =
  if unsigned(n) == 0 then zeros() else getCapMacInput(p, n)

// Three properties that pin the split down (D-297 3.1). They are stated here because the
// model has no top-level assert, and because writing a test for them belongs to the test
// group (who own the expectations, not us):
//
//   N = 0   getCapKey(p, 0)      == 0        and   getCapMacInput(p, 0) == p      (DIFFER)
//   N = 48  getCapKey(p, 48)     == 2^47     and   getCapMacInput(p, 48) == 2^47  (SAME)
//
// Use a NON-zero p when testing the first line: with p = 0 the two formulas coincide and
// the test proves nothing.

// 1a-8. poisonIf -- the single failure exit of every PTR-producing instruction, and the
// ADDRESS IS PRESERVED (ADR-0003 r25): it is the repair entry point, so it must not hold
// the address that failed to be written. Sail is NOT lazy (D-99 V-5).
// why: doc/truisa-deltas.md#poisonif
val  poisonIf : (Capability, bool) -> Capability
function poisonIf(cap : Capability, cond : bool) -> Capability =
  if cond then truisaUnavailable(cap.address) else cap


// ---- PAC algorithm boundary ------------------------------------------------------------
// The algorithm itself (key, fold, MAC) lives in truisa_pac.sail. Swap THAT file to change
// the MAC; nothing below it here changes. What stays here is the part that knows how wide
// PAC_W is, because that is protocol, not algorithm.
// ----------------------------------------------------------------------------------------

// 1b-3. truisaMac -- the width-aware wrapper the architecture fixes. cap_mac_msg_width
// (tag || CentroID || salt, a FIXED-length concatenation) is defined in prelude_xlen with
// the other derived widths. The result is truncated to PAC_W here, which is the only place
// the algorithm's 128-bit output meets the profile's width.
// why: doc/truisa-deltas.md#mac
val  truisaMac : (bits(128), bits(cap_mac_msg_width)) -> bits(cap_pac_width)
function truisaMac(key : bits(128), msg : bits(cap_mac_msg_width)) -> bits(cap_pac_width) =
  truncate(truisa_mac_raw(key, zero_extend(msg), cap_pac_width), cap_pac_width)


val  getCapPac : Capability -> CapPacBits
function getCapPac(cap : Capability) -> CapPacBits =
  capToMetadataBits(cap)[cap_pac_width - 1 .. 0]


// 1b-5. signPtr -- the single signing operator (spec/ch04 line 233-242), called ONLY at PTR
// production points. The m = 0 cases are resolved by D-108 ruling A: for a one-byte slot at
// address 0 it is reachable and legal, while N = VA returning 0 is an ADR-0026 ruling.
// why: doc/truisa-deltas.md#signptr
// The key is decided by FORM alone (ADR-0034 decision 3): an aligned pointer with N = VA
// uses rootkey, everything else uses xpkey. There is no selector bit and no dependence on
// CRE or privilege -- that is what keeps the bootstrap chain independent of both.
val  isRootForm : Capability -> bool
function isRootForm(cap : Capability) -> bool =
  (cap.mode == 0b1) & (unsigned(cap.nc) == cap_address_width)

val  signPtr : (Capability, CapSaltBits) -> Capability
function signPtr(cap : Capability, salt : CapSaltBits) -> Capability = {
  let hi7 = getCapTagBits(cap);
  /* Slices [VA-1..0]: getCapMacInput's first parameter is CapAddrBits (48), not the
   * 64-bit struct field. The redundant high bits are not part of the address. */
  let m   = getCapMacInput(cap.address[cap_address_width - 1 .. 0], cap.nc);
  let msg : bits(cap_mac_msg_width) = hi7 @ m @ salt;
  struct {
    mode    = cap.mode,
    nc      = cap.nc,
    pac     = truisaMac(if isRootForm(cap) then truisa_rootkey_stub else truisa_xpkey_stub, msg),
    address = cap.address,
  }
}

// 1b-6. verifyPtr -- recompute and compare (D-99). Signing is idempotent on the fields that
// matter, so "compare against signPtr(cap)" is a real test and not a tautology.
val  verifyPtr : (Capability, CapSaltBits) -> bool
function verifyPtr(cap : Capability, salt : CapSaltBits) -> bool =
  getCapPac(cap) == getCapPac(signPtr(cap, salt))

// 1b-6b. keySalt -- THE ONLY place a salt is obtained (D-220). No call site passes a
// literal; that is what makes "is the descriptor side wired up?" greppable at all.
//   aligned     -> all-zero BY SPEC, permanently (spec/ch04; ADR-0005 rev 11 item 3).
//   descriptor  -> the entry's salt; NOT written yet -- phase A produces no such form.
// Do not change CapSaltBits's type or width here (D-220 section 4.3).
// why: doc/truisa-deltas.md#keysalt
// Warning: `cap` is unused in phase A BY DESIGN, not by oversight (D-223 ruling 5): the salt is
// a constant here, so there is nothing to look up. Phase B computes the entry identifier
// FROM this argument; do not change the signature to (form, nc) -- that would push form
// knowledge back to the call sites, which is the thing keySalt exists to prevent.
val  keySalt : Capability -> CapSaltBits
function keySalt(cap : Capability) -> CapSaltBits = zeros()

// Warning: The body MUST be `if fail then poison else sign`: Sail evaluates arguments before the
// call, so `poisonIf(signPtr(q, ...), fail)` would compute a MAC and throw it away (D-99 V-5).
val  makeCapAligned : (Capability, bits(cap_nc_width), bool) -> Capability
function makeCapAligned(parent : Capability, n : bits(cap_nc_width), fail : bool)
    -> Capability =
  // Notes: `parent.address`, not the slot base and not 0 (D-224) -- the slot base is a
  // derived position that can fall outside `parent` as n grows, and 0 carries no information.
  if fail then truisaUnavailable(parent.address)
  else {
    let q : Capability = struct {
      mode    = 0b1,
      nc      = n,
      pac     = zeros(),
      /* getCapSlotBase takes and returns CapAddrBits (48); the struct field is 64 bits,
       * so the result is sign-extended back into canonical form (ADR-0029 decision 5). */
      address = sign_extend(getCapSlotBase(parent.address[cap_address_width - 1 .. 0], n)),
    };
    signPtr(q, keySalt(q))
  }

// 1b-8. setCapBounds -- called by SCBNDS/SCBNDSI; the operand is the slot exponent N, not a
// length (ADR-0028). Four criteria, in the instruction pages' order:
//   (1) form: Aligned or Bare (Descriptor fails until the table exists).
//   (2) N <= VA.
//   (3) monotonicity as a SLOT test, N >= Np -- TruISA carries no bounds in the pointer;
//       a Bare parent constrains nothing.
//   (4) ABSENT by design: CR-MAC-01's "L = 0 fails" does not apply -- N = 0 is a legal
//       one-byte slot.
// Failure returns the parent UNSIGNED and the caller poisons it (truisa_inst.sail:175).
// why: doc/truisa-deltas.md#setbnds
val  setCapBounds : (Capability, CapAddrBits, bits(cap_nc_width))
                    -> (bool, Capability)
function setCapBounds(parent : Capability, base : CapAddrBits,
                      n : bits(cap_nc_width)) -> (bool, Capability) = {
  // `base` is the address the child slot must start at. Both current call sites pass
  // cs1_val.address, so it always equals parent.address today; it is kept as a separate
  // parameter because a future instruction may derive base from somewhere else, and
  // makeCapAligned's signature (fixed by CR-MAC-01 Rev.1) has no place for it.
  let k         = unsigned(n);
  let kp        = unsigned(parent.nc);
  let n_ok      = k <= cap_address_width;
  /* Input-illegal exit (spec/ch06, D-318): an unavailable parent does NOT trap and does NOT
   * fall through to the failure exit -- the blueprint narrows the address as usual and only
   * clears the tag. The RESULT address is the slot base of the requested exponent, computed
   * from the parent's address field exactly as it would be for a usable parent. */
  if getCapForm(parent) == None() then
    (true, truisaUnavailable(sign_extend(
             getCapSlotBase(parent.address[cap_address_width - 1 .. 0], n))))
  else {
  // The parent must be an ALIGNED pointer: there is no Bare form any more (D-274/D-276),
  // and a Descriptor parent has no N to nest under.
  let form_ok   = getCapForm(parent) == Some(FormAligned);
  let in_parent = k >= kp;
  /* `base` is CapAddrBits (48) and the struct field is 64: slice the right-hand side so
   * the comparison is between addresses, not between an address and 16 redundant bits
   * (ADR-0029 invariant I2 -- those bits are not part of the value). */
  let base_ok   = base == parent.address[cap_address_width - 1 .. 0];
  if form_ok & n_ok & in_parent & base_ok then
    // ADR-0034 decision 4: when the child exponent equals the parent's there is nothing to
    // narrow, so copying the parent bit for bit is the right answer -- re-signing would
    // stamp an xpkey signature onto an N = VA pointer, which verifies under rootkey and
    // would therefore always mismatch. In the bootstrap chain this is NOT hit: scbnds
    // there narrows, so it takes the re-signing branch.
    if k == kp then (true, parent)
    else (true, makeCapAligned(parent, n, false))
  else
    (false, parent)
  }
}

// 1c. The bounds projection, and the checked pointer increment. Both requested by the
// architecture group's CADD notification (D-117): CADD is the first instruction that moves a
// pointer within its slot.

// 1c-1. The bounds projection used by GCBASE / GCBOUND. spec/insns/gcbase.adoc states the
// three forms as ONE formula, SlotBase(addr, K); the body does NOT fold bare into it,
// deliberately. Notes: None() has three sources and they are NOT the same thing (gcbase.adoc).
// why: doc/truisa-deltas.md#gcbase
// Returns the bounds ALREADY SIGN-EXTENDED to the register width, so that every caller
// (GCBASE / GCBOUND) can write the value straight to X(rd) without repeating the rule.
// The rule is gcbound.adoc: "sign extended by bit (VA-1)", i.e. bits 63-48 copy bit (VA-1).
// Bare is the case that makes this visible: its bound is 2^VA - 1, which sign-extends to
// 0xFFFF_FFFF_FFFF_FFFF = -1 -- that is what the spec says, not an accident.
// Notes: the blueprint's getCapBoundsBits returns the FIELD widths (CapAddrBits, CapLenBits)
// and leaves the extension to each caller; there is no GCBase/GCBound there to compare
// against, so this is a TruISA choice, not a divergence from a blueprint body.
// The N/C field encoding of an exponent (D-305 section 5). One definition so that every
// producer of an Aligned pointer converts the same way -- if the field width ever changes,
// this is the only line to touch.
// Warning: `n` must be a legal exponent. The bound is asserted rather than clamped,
// because a clamp would turn a spec violation into a silently wrong slot.
val  ncOfN : int -> bits(cap_nc_width)
function ncOfN(n : int) -> bits(cap_nc_width) = {
  assert(n >= 0 & n <= cap_address_width);
  get_slice_int(cap_nc_width, n, 0)
}

// The root pointer mroot hands out (D-302): an ALIGNED pointer with N = VA and address 0
// -- the whole-address-space slot, its base being SlotBase(0, VA) = 0. Signed with rootkey
// because isRootForm(signPtr) keys it that way. salt is zero: the aligned path has no
// entry and therefore carries no salt (ADR-0005 decision 12).
// Nothing here reads memory or the table, which is what lets it run before a stack exists.
val  truisaMroot : unit -> Capability
function truisaMroot(_ : unit) -> Capability = {
  let n_va : bits(cap_nc_width) = ncOfN(cap_address_width);
  let raw : Capability = struct {
    mode    = 0b1,
    nc      = n_va,
    pac     = zeros(),
    address = zeros(),
  };
  signPtr(raw, zeros())
}

val  getCapBoundsBits : Capability -> option((bits(cap_ptr_width), bits(cap_ptr_width)))
function getCapBoundsBits(cap : Capability) -> option((bits(cap_ptr_width), bits(cap_ptr_width))) = {
  // Only the aligned form has bounds. A descriptor needs the table (phase B); an
  // encoding-unavailable pointer has none by definition.
  if getCapForm(cap) != Some(FormAligned) then None()
  else {
    /* Aligned: [S, S + 2^N - 1]. S is already N-aligned, so the addition cannot leave
     * the field. N = VA is legal (ADR-0026) and lands on the same all-ones value. */
    let a : CapAddrBits = cap.address[cap_address_width - 1 .. 0];
    let k : nat = unsigned(cap.nc);
    let base : CapAddrBits = getCapSlotBase(a, cap.nc);
    let span64 : bits(64) = ((0x0000_0000_0000_0001 : bits(64)) << k) - 1;
    let span : CapAddrBits = truncate(span64, cap_address_width);
    Some((sign_extend(base), sign_extend(base + span)))
  }
}

// 1c-2a. The three predicates behind BOTH address operators. Each criterion has EXACTLY ONE
// definition here -- before this round (1) and (2) were written twice and kept in sync by a
// comment, which is not an invariant.
// why: doc/truisa-deltas.md#predicates

/* (1) representable: the result stays in the source pointer's slot; for bare, which has
 * no slot, it degrades to the same bit (VA-1) HALF. Notes: NOT `true` for bare: letting CADD
 * cross the half while SCADDR refuses to would make relative moves and absolute writes
 * disagree about legality (ADR-0029 decision 11.4). Cost: a bare pointer cannot cross
 * 2^(VA-1). */
// Both predicates used to take a `form` argument to special-case Bare. Bare is gone
// (D-274/D-276), so the aligned slot rule is the only one left.
val  sameSlot : (CapAddrBits, bits(cap_nc_width), CapAddrBits) -> bool
function sameSlot(a : CapAddrBits, nc : bits(cap_nc_width), b : CapAddrBits) -> bool =
  getCapSlotBase(a, nc) == getCapSlotBase(b, nc)

val  ptrIntact : Capability -> bool
function ptrIntact(cap : Capability) -> bool = verifyPtr(cap, keySalt(cap))

// (3) a carry out of the address field, judged ON THE FIELD. Notes: never judge it as
// `sign_extend(new48) == sum`, which is identically false whenever bit(VA-1) is set, so it
// would poison the whole upper half. why: doc/truisa-deltas.md#carry
val  carryOutOfAddrField : (CapAddrBits, xlenbits) -> bool
function carryOutOfAddrField(a : CapAddrBits, delta : xlenbits) -> bool = {
  let sum : bits(cap_ptr_width + 1) = zero_extend(a) + sign_extend(delta);
  (sum[cap_ptr_width] == 0b0)
  & (sum[cap_ptr_width - 1 .. cap_address_width] != zeros())
}

// Not "setCapAddr plus a sealed check" -- TruISA has no seal (ADR-0001). Two criteria, in
// spec order: (1) representable = same slot (bare: the same bit(VA-1) half), (2) intact --
// SCADDR does have an integrity criterion (ADR-0029 decision 11.5 corrected an earlier
// reading that dropped it). `pac` is copied: the MAC covers the CentroID, and (1) just
// proved the slot held. The blueprint's unchecked `setCapAddr` is not defined here -- no
// caller would exist. why: doc/truisa-deltas.md#scaddr
val  setCapAddrChecked : (Capability, CapAddrBits) -> Capability
function setCapAddrChecked(cap : Capability, addr : CapAddrBits) -> Capability = {
  /* Inputs whose encoding is unavailable are copied as they are, never laundered into
   * something usable. This is the ONE place the form is dispatched for the address setter.
   *
   * TODO(phase B): this branch also swallows FormDescriptor, which is only right while
   * there is no table -- a descriptor pointer's criterion (2) needs its entry. When the
   * table lands, descriptors must take the look-up path here; do NOT leave them on the
   * copy-as-is path (D-297 3.2). */
  if getCapForm(cap) == None() then
    /* Input-illegal exit (spec/ch06, D-318): a derivation instruction does NOT trap when its
     * parent is unavailable -- the blueprint computes the address as usual and only clears
     * the tag, and this architecture has no out-of-band tag, so the invalidity goes into
     * bits 63-48. The address here is the RESULT (the new address we were asked to set),
     * not the parent's: SCADDR computes it either way. */
    truisaUnavailable(sign_extend(addr))
  else if getCapForm(cap) == Some(FormDescriptor) then
    // TODO(phase B): descriptors need their entry for criterion (2). Until the table
    // exists they are copied as-is -- do NOT leave them here once the table lands.
    cap
  else {
    let a : CapAddrBits = cap.address[cap_address_width - 1 .. 0];
    let newCap : Capability = struct {
      mode    = cap.mode,
      nc      = cap.nc,
      pac     = cap.pac,
      address = sign_extend(addr),
    };
    /* Criteria (1) then (2), in the spec's order, so a future xtval can say which failed
     * first. One call each -- the definitions are in 1c-2a, not here.
     * Notes: the poisoned result carries the CALLER's address, not `addr` (D-224). The
     * poison address is a REPAIR ENTRY POINT: software re-binds from it (SCBNDS/DSTR), so
     * handing back the address that failed to be written would rebuild the pointer in
     * somebody else's object -- fail-then-repair must not become a privilege escalation. */
    poisonIf(cap, not(sameSlot(a, cap.nc, addr)) | not(ptrIntact(cap)))
  }
}

// 1c-2. The checked pointer increment used by CADD / CADDI.
// Arithmetic + delegate: criteria (1) and (2) are applied by setCapAddrChecked, (3) here.
// `delta` is XLEN bits, NOT VA bits (ADR-0029 decision 10.1). `pac` is copied because the
// MAC covers the slot, not the address (ADR-0004). (3) is a FIELD test -- never
// `sign_extend(new) == sum`, which is identically false for the whole upper half. Downward
// overflow is ALLOWED (mod 2^VA). why: doc/truisa-deltas.md#incaddr
val  incCapAddrChecked : (Capability, xlenbits) -> Capability
function incCapAddrChecked(cap : Capability, delta : xlenbits) -> Capability = {
  let a : CapAddrBits = cap.address[cap_address_width - 1 .. 0];
  let sum : bits(cap_ptr_width + 1) = zero_extend(a) + sign_extend(delta);
  // Warning: THE FORM GATE IS LOAD-BEARING: `poisonIf` runs AFTER the delegation, so without
  // it an input whose encoding is unavailable would be poisoned by the outer call even
  // though criteria (1)/(2) never ran -- "unavailable" laundered into the failure exit.
  let carries : bool =
    (getCapForm(cap) != None()) & carryOutOfAddrField(a, delta);
  /* Poisoned / invalid inputs come back untouched from setCapAddrChecked's own form
   * dispatch, and `carries` is false for them, so they are returned exactly as given. */
  /* Notes: the OUTER poison must pass `cap` too, not the inner result -- the inner call
   * already returns `addr = new48` on success, so poisoning that value would put the
   * carried-into-nowhere address into the repair entry point (D-224). Fixing only the
   * inner one changes nothing here. */
  poisonIf(if carries then cap else setCapAddrChecked(cap, truncate(sum, cap_address_width)),
           carries)
}
