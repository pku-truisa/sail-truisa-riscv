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

// truisa_ptr_width IS xlen -- the blueprint's shape (cheri_cap_common.sail:14).
type truisa_ptr_width : Int = xlen
let  truisa_ptr_width = sizeof(truisa_ptr_width)

// Tag bits: one mode bit plus log2(xlen) bits of N/C.
type truisa_mode_width : Int = 1
let  truisa_mode_width = sizeof(truisa_mode_width)

// log2 of the pointer width.
type truisa_nc_width : Int = if xlen == 32 then 5 else 6
let  truisa_nc_width = sizeof(truisa_nc_width)

type truisa_tag_width : Int = truisa_mode_width + truisa_nc_width
let  truisa_tag_width = sizeof(truisa_tag_width)

// 64 -> 48, the only profile in the spec (ADR-0032 d1); 32 -> 24, filling the pointer.
// Notes: The XLEN 32 branch is a MODEL CAPABILITY, not a spec commitment (ADR-0032 d3).
type truisa_address_width : Int = if xlen == 32 then 24 else 48
let  truisa_address_width = sizeof(truisa_address_width)

// PAC bits: all bits between the tag and the address.
type truisa_pac_width : Int =
  truisa_ptr_width - truisa_address_width - truisa_mode_width - truisa_nc_width
let  truisa_pac_width = sizeof(truisa_pac_width)


// The struct's `address` is a full machine word, so it exceeds CapBits (ADR-0029 d1).
// Notes: Never restate truisa_pac_width via truisa_meta_width -- the second is derived.
// why: doc/truisa-deltas.md#repr

// Lets Sail prove `bits(truisa_ptr_width - truisa_address_width)` non-negative.
constraint truisa_address_width <= truisa_ptr_width

type truisa_meta_width : Int = truisa_ptr_width - truisa_address_width
let  truisa_meta_width = sizeof(truisa_meta_width)

/* Bookkeeping only: 80/40. Notes: Never used inside bits() -- CapBits stays bits(64/32). */
type truisa_cap_repr_width : Int = truisa_ptr_width + truisa_meta_width
let  truisa_cap_repr_width = sizeof(truisa_cap_repr_width)

// Residue of the entry layout, not an input to it (D-223). Notes: NOT meta_width * 2.
// why: doc/truisa-deltas.md#saltwidth
type truisa_salt_width : Int = 2 * (xlen - truisa_address_width)
let  truisa_salt_width = sizeof(truisa_salt_width)

let truisa_poison_tag : bits(truisa_tag_width) = 0b0 @ ones()

/*=======================================================================================*/
/*  1a -- the capability itself, and the operators that only READ it.                     */
/*                                                                                       */
/*  CR-MAC-01 Rev.1 items 1a-1 .. 1a-8. No MAC, no signing, no table: 1b owns those.      */
/*=======================================================================================*/

// Alias layer: `Cap*` keeps the blueprint's spelling so the two files read side by side.
// Each is defined from a `truisa_*` width above; none carries a constant of its own.

// Capability size in bytes. Notes: do not use `2 ^ log2_cap_size`, which cannot be folded (D-94).
type cap_size : Int = if xlen == 32 then 4 else 8
let  cap_size = sizeof(cap_size)

type CapBits     = bits(8 * cap_size)
type CapAddrBits = bits(truisa_address_width)
type CapTagBits  = bits(truisa_tag_width)

type CapMetaBits = bits(truisa_meta_width)

// VA + PAC_W - 1 .. VA -- never literal bit numbers, the slice moves with the profile.
type CapPacBits  = bits(truisa_pac_width)

// Entry salt, or all zeros on the aligned path (ADR-0005 rev 11 c3). Warning: The zero segment
// is NOT omitted -- it is what fixes the MAC input length.
type CapSaltBits = bits(truisa_salt_width)

// 1a-1. Two views, different widths (ADR-0029 decision 1):
//   memory    mode(1) | N/C(6) | PAC(9) | address(48)   <- CapBits; what SCEQ compares
//   register  mode+NC(7) | PAC(9) | address(64)        <- this struct
// address[63:48] is redundant (dropped on encode, sign-extended back; I1/I2).
// why: doc/truisa-deltas.md#layout
struct Capability = {
  mode    : bits(truisa_mode_width),
  nc      : bits(truisa_nc_width),
  pac     : bits(truisa_pac_width),
  address : bits(truisa_ptr_width),
}

// The poison value WITH A ZERO ADDRESS: mode 0, N/C all ones, PAC 0, address 0
// (docs/isa/03 3.6) -- not CHERI's tag-clearing. This is the `addr(x) = 0` special case of
// `0x7E00 << 48 | addr(x)` (ADR-0003 r25). Real poisoning goes through poisonIf, which
// keeps the caller's address.
let truisa_poison_cap : Capability = struct {
  mode    = 0b0,
  // `ones(...)` not a 6-bit literal: the field is truisa_nc_width wide, not always 6.
  nc      = ones(truisa_nc_width),
  pac     = zeros(),
  address = zeros(),
}

// Notes: There is no `capToBits` any more (ADR-0029 decision 3): with `address` at 64 bits the
// blueprint's own shape applies too (cheri_insts.sail:211). Notes: Do not rescue it.
val  capToMetadataBits : Capability -> CapMetaBits
function capToMetadataBits(cap : Capability) -> CapMetaBits =
  cap.mode @ cap.nc @ cap.pac

// encode . decode = id, ONLY on canonical capabilities (ADR-0029 invariant I1): a bare
// integer written by wX is not canonical and does not round-trip. Notes: Never rename this to
// `_tag` -- TruISA has no tag bit (ADR-0003 decision 4).
val  bitsToCap : (bool, CapBits) -> Capability
function bitsToCap(tag : bool, ptr : CapBits) -> Capability =
  struct {
    mode    = ptr[truisa_ptr_width - 1 .. truisa_ptr_width - truisa_mode_width],
    nc      = ptr[truisa_ptr_width - truisa_mode_width - 1
                  .. truisa_address_width + truisa_pac_width],
    pac     = ptr[truisa_address_width + truisa_pac_width - 1 .. truisa_address_width],
    /* Sign extension, not zero extension: address[63:48] carries no information, so
     * without a rule the same pointer would have 2^16 representations. Copying bit
     * (VA-1) is the only choice that makes encode . decode = id and that matches the
     * RISC-V canonical address form (ADR-0029 decision 5). */
    address = sign_extend(ptr[truisa_address_width - 1 .. 0]),
  }

/* ------------------------------------------------------------------------------------
 * 1a-4. The 7-bit label (bits 63-57): mode plus N/C. Every form decision hangs off it.
 * The slice is derived from the constants, never written as 63..57 -- that is exactly
 * the hard-coding that made the D-94/D-96 line numbers drift.
 * ---------------------------------------------------------------------------------- */
val  getCapTagBits : Capability -> CapTagBits
function getCapTagBits(cap : Capability) -> CapTagBits =
  capToMetadataBits(cap)[truisa_meta_width - 1 .. truisa_pac_width]

// 1a-5. Which of the five forms the label denotes (docs/isa/03 section 3.3). The order is
// Order is not negotiable: both Bare codes first (a descriptor with C = 0 encodes as
// 0000000), then the poison code, then bit 63. why: doc/truisa-deltas.md#forms
val  getCapForm : Capability -> CapPtrForm
function getCapForm(cap : Capability) -> CapPtrForm = {
  let tag = getCapTagBits(cap);
  let n : int = unsigned(cap.nc);
  if tag == ones() then FormBare
  else if tag == zeros() then FormBare
  else if tag == truisa_poison_tag then FormPoisoned
  else if cap.mode == 0b1 then
    (if n <= truisa_address_width then FormAligned else FormInvalid)
  else
    (if n >= 1 & n <= truisa_address_width - 1 then FormDescriptor else FormInvalid)
}

// 1a-6. Slot base: S = p with the low N bits cleared, i.e. (p >> N) << N.
// Warning: Written as a shift PAIR, not `p & ~(2^N - 1)`: the mask form needs a negative-shaped
// literal in this width, which Sail will not take.
// why: doc/truisa-deltas.md#slotbase
val  getCapSlotBase : (CapAddrBits, bits(truisa_nc_width)) -> CapAddrBits
function getCapSlotBase(p : CapAddrBits, n : bits(truisa_nc_width)) -> CapAddrBits =
  (p >> unsigned(n)) << unsigned(n)

// 1a-7. CentroID canonical point m = S + 2^(N-1) (ADR-0004: the pair is (m-1, m), and m is
// the canonical one). Returns an ADDRESS, not a key -- the table is keyed by (C, S).
//   N = 0   -> m = S by definition, so m = 0 is reachable and legal (spec/ch04).
//   N = VA  -> m = 0 by ruling (ADR-0026). A different zero, hence D-108.
// Never call 0 "reserved" without naming which case. "1B not in table" (ADR-0006) is a
// matched pair with the N = 0 case: with m = S, an entry at m = 0 collides with address 0.
// why: doc/truisa-deltas.md#centroid
val  getCapCentroID : (CapAddrBits, bits(truisa_nc_width)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(truisa_nc_width)) -> CapAddrBits = {
  // Warning: k must be nat, not int. Written as int (unsigned(n) coerced) Sail cannot prove
  // `k >= 0` and rejects the shift with "Could not resolve quantifiers for shiftl".
  // getCapSlotBase gets away with it only because it inlines unsigned(n) at the shift,
  // where the non-negativity is still visible.
  let k : nat = unsigned(n);
  let base : CapAddrBits = getCapSlotBase(p, n);
  if k == 0 then base
  else if k == truisa_address_width then zeros()
  else {
    let twop : bits(64) = 0x0000_0000_0000_0001 << k;
    // Warning: truncate takes TWO arguments in Sail: the value and the target width
    // (bitvector('n), int('m)). One-argument form fails to resolve.
    let half : CapAddrBits = truncate(twop >> 1, truisa_address_width);
    base + half
  }
}

// 1a-8. poisonIf -- the single failure exit of every PTR-producing instruction, and the
// ADDRESS IS PRESERVED (ADR-0003 r25): it is the repair entry point, so it must not hold
// the address that failed to be written. Sail is NOT lazy (D-99 V-5).
// why: doc/truisa-deltas.md#poisonif
val  poisonIf : (Capability, bool) -> Capability
function poisonIf(cap : Capability, cond : bool) -> Capability =
  if cond then { truisa_poison_cap with address = cap.address } else cap


// 1b-1. The key stub. spec/ch04 line 312: xpkey is 128 bits (xpkey1 || xpkey0), and
// xpkey == 0 is a defined-but-empty key.
// Warning: Placeholder for the xpkey CSR, which does not exist yet -- delete this when it lands.
// why: doc/truisa-deltas.md#xpkey
let truisa_xpkey_stub : bits(128) =
  0x0123_4567_89AB_CDEF_0123_4567_89AB_CDEF

// 1b-2. foldXor -- the stub's mixing primitive. spec/ch04 line 314 pins the OUTPUT rule: the
// MAC yields >= PAC_W bits and the PAC slice takes the low ones.
// why: doc/truisa-deltas.md#foldxor
// XOR `x` with itself shifted by w, 2w, ... and keep the low w bits: exactly "split into
// w-bit blocks, XOR, zero-extend the last block".
// Warning: `sail_shiftright` is a lib-internal symbol, used deliberately -- `slice` cannot
// express a variable-width chunk. why: doc/truisa-deltas.md#foldxor
val  foldXorShifted : (bits(128), int, int, bits(128)) -> bits(128)
function foldXorShifted(x : bits(128), w : int, i : int, acc : bits(128)) -> bits(128) =
  if i * w >= 128 then acc
  else foldXorShifted(x, w, i + 1, acc ^ sail_shiftright(x, i * w))

// Warning: STUB (as is truisa_xpkey_stub). Never quote its output as a strength figure --
// w = 2 leaves ~1/4 for ANY stub. Real implementations meet ADR-0005 decision 10.
val  foldXor : (bits(128), int) -> bits(truisa_pac_width)
function foldXor(x : bits(128), w : int) -> bits(truisa_pac_width) = {
  // Notes: not `w == 2 | w == 9` (that re-enumerates PAC_W). w = 0 cannot arise from any
  // legal configuration; this rejects an undefined domain, not the old Sv57 tier.
  assert(w > 0);
  assert(w == truisa_pac_width);
  truncate(foldXorShifted(x, w, 0, zeros()), truisa_pac_width)
}

// 1b-3. truisaMac -- the interface the architecture fixes. spec/ch04 line 313: the input is
// hi7 || m || salt, a FIXED-length concatenation, so no two distinct inputs share a shape.
// why: doc/truisa-deltas.md#mac
// MAC input = tag || CentroID || salt, FIXED length (spec/ch04). Spelled as a sum, never
// as 87 -- that number is only right at XLEN 64.
type truisa_mac_msg_width : Int =
  truisa_mode_width + truisa_nc_width + truisa_address_width + truisa_salt_width

val  truisaMac : (bits(128), bits(truisa_mac_msg_width)) -> bits(truisa_pac_width)
function truisaMac(key : bits(128), msg : bits(truisa_mac_msg_width)) -> bits(truisa_pac_width) =
  foldXor(key, truisa_pac_width)
  ^ foldXor(zero_extend(msg), truisa_pac_width)


val  getCapPac : Capability -> CapPacBits
function getCapPac(cap : Capability) -> CapPacBits =
  capToMetadataBits(cap)[truisa_pac_width - 1 .. 0]


// 1b-5. signPtr -- the single signing operator (spec/ch04 line 233-242), called ONLY at PTR
// production points. The m = 0 cases are resolved by D-108 ruling A: for a one-byte slot at
// address 0 it is reachable and legal, while N = VA returning 0 is an ADR-0026 ruling.
// why: doc/truisa-deltas.md#signptr
val  signPtr : (Capability, CapSaltBits) -> Capability
function signPtr(cap : Capability, salt : CapSaltBits) -> Capability = {
  let hi7 = getCapTagBits(cap);
  /* Slices [VA-1..0]: getCapCentroID's first parameter is CapAddrBits (48), not the
   * 64-bit struct field. The redundant high bits are not part of the address. */
  let m   = getCapCentroID(cap.address[truisa_address_width - 1 .. 0], cap.nc);
  let msg : bits(truisa_mac_msg_width) = hi7 @ m @ salt;
  struct {
    mode    = cap.mode,
    nc      = cap.nc,
    pac     = truisaMac(truisa_xpkey_stub, msg),
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
val  makeCapAligned : (Capability, bits(truisa_nc_width), bool) -> Capability
function makeCapAligned(parent : Capability, n : bits(truisa_nc_width), fail : bool)
    -> Capability =
  // Notes: `parent.address`, not the slot base and not 0 (D-224) -- the slot base is a
  // derived position that can fall outside `parent` as n grows, and 0 carries no information.
  if fail then { truisa_poison_cap with address = parent.address }
  else {
    let q : Capability = struct {
      mode    = 0b1,
      nc      = n,
      pac     = zeros(),
      /* getCapSlotBase takes and returns CapAddrBits (48); the struct field is 64 bits,
       * so the result is sign-extended back into canonical form (ADR-0029 decision 5). */
      address = sign_extend(getCapSlotBase(parent.address[truisa_address_width - 1 .. 0], n)),
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
val  setCapBounds : (Capability, CapAddrBits, bits(truisa_nc_width))
                    -> (bool, Capability)
function setCapBounds(parent : Capability, base : CapAddrBits,
                      n : bits(truisa_nc_width)) -> (bool, Capability) = {
  // `base` is the address the child slot must start at. Both current call sites pass
  // cs1_val.address, so it always equals parent.address today; it is kept as a separate
  // parameter because a future instruction may derive base from somewhere else, and
  // makeCapAligned's signature (fixed by CR-MAC-01 Rev.1) has no place for it.
  let form      = getCapForm(parent);
  let k         = unsigned(n);
  let kp        = unsigned(parent.nc);
  let form_ok   = form == FormAligned | form == FormBare;
  let n_ok      = k <= truisa_address_width;
  let in_parent = if form == FormBare then true else k >= kp;
  /* `base` is CapAddrBits (48) and the struct field is 64: slice the right-hand side so
   * the comparison is between addresses, not between an address and 16 redundant bits
   * (ADR-0029 invariant I2 -- those bits are not part of the value). */
  let base_ok   = base == parent.address[truisa_address_width - 1 .. 0];
  if form_ok & n_ok & in_parent & base_ok then
    (true, makeCapAligned(parent, n, false))
  else
    (false, parent)
}

// 1c. The bounds projection, and the checked pointer increment. Both requested by the
// architecture group's CADD notification (D-117): CADD is the first instruction that moves a
// pointer within its slot.

// 1c-1. The bounds projection used by GCBASE / GCBOUND. spec/insns/gcbase.adoc states the
// three forms as ONE formula, SlotBase(addr, K); the body does NOT fold bare into it,
// deliberately. Notes: None() has three sources and they are NOT the same thing (gcbase.adoc).
// why: doc/truisa-deltas.md#gcbase
val  getCapBoundsBits : Capability -> option((CapAddrBits, CapAddrBits))
function getCapBoundsBits(cap : Capability) -> option((CapAddrBits, CapAddrBits)) = {
  let form = getCapForm(cap);
  if form == FormPoisoned | form == FormInvalid | form == FormDescriptor then None()
  else if form == FormBare then
    /* Whole address space: first byte 0, last byte 2^VA - 1. */
    Some((zeros(), ones()))
  else {
    /* Aligned: [S, S + 2^N - 1]. S is already N-aligned, so the addition cannot leave
     * the field. N = VA is legal (ADR-0026) and lands on the same all-ones value. */
    let a : CapAddrBits = cap.address[truisa_address_width - 1 .. 0];
    let k : nat = unsigned(cap.nc);
    let base : CapAddrBits = getCapSlotBase(a, cap.nc);
    let span64 : bits(64) = ((0x0000_0000_0000_0001 : bits(64)) << k) - 1;
    let span : CapAddrBits = truncate(span64, truisa_address_width);
    Some((base, base + span))
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
val  sameSlot : (CapAddrBits, bits(truisa_nc_width), CapPtrForm, CapAddrBits) -> bool
function sameSlot(a : CapAddrBits, nc : bits(truisa_nc_width), form : CapPtrForm,
                  b : CapAddrBits) -> bool =
  if form == FormBare then
    a[truisa_address_width - 1] == b[truisa_address_width - 1]
  else
    getCapSlotBase(a, nc) == getCapSlotBase(b, nc)

// (2) intact: bare is SKIPPED -- bare is never signed (ADR-0005 decision 3), so its PAC
// stays zero and any comparison would be trivially false (ADR-0029 decision 11.2).
val  ptrIntact : (Capability, CapPtrForm) -> bool
function ptrIntact(cap : Capability, form : CapPtrForm) -> bool =
  if form == FormBare then true else verifyPtr(cap, keySalt(cap))

// (3) a carry out of the address field, judged ON THE FIELD. Notes: never judge it as
// `sign_extend(new48) == sum`, which is identically false whenever bit(VA-1) is set, so it
// would poison the whole upper half. why: doc/truisa-deltas.md#carry
val  carryOutOfAddrField : (CapAddrBits, xlenbits) -> bool
function carryOutOfAddrField(a : CapAddrBits, delta : xlenbits) -> bool = {
  let sum : bits(truisa_ptr_width + 1) = zero_extend(a) + sign_extend(delta);
  (sum[truisa_ptr_width] == 0b0)
  & (sum[truisa_ptr_width - 1 .. truisa_address_width] != zeros())
}

// 1c-2. The checked pointer increment used by CADD / CADDI.
// Arithmetic + delegate: criteria (1) and (2) are applied by setCapAddrChecked, (3) here.
// `delta` is XLEN bits, NOT VA bits (ADR-0029 decision 10.1). `pac` is copied because the
// MAC covers the slot, not the address (ADR-0004). (3) is a FIELD test -- never
// `sign_extend(new) == sum`, which is identically false for the whole upper half. Downward
// overflow is ALLOWED (mod 2^VA). why: doc/truisa-deltas.md#incaddr
/* Warning: Declared ahead of its use, and that is deliberate: incCapAddrChecked delegates to
 * it, and source order is load-bearing WITHIN a file as well as across files
 * (CODE_STYLE rule 7). The definition stays in 1c-3 below -- this `val` is the whole
 * point, so do not "tidy" it away by moving the definition up. */
val  setCapAddrChecked : (Capability, CapAddrBits) -> Capability

val  incCapAddrChecked : (Capability, xlenbits) -> Capability
function incCapAddrChecked(cap : Capability, delta : xlenbits) -> Capability = {
  let form = getCapForm(cap);
  let a : CapAddrBits = cap.address[truisa_address_width - 1 .. 0];
  let sum : bits(truisa_ptr_width + 1) = zero_extend(a) + sign_extend(delta);
  // Warning: THE FORM GATE IS LOAD-BEARING: `poisonIf` runs AFTER the delegation, so without it
  // an illegal input that happens to overflow would be poisoned by the outer call even
  // though criteria (1)/(2) never ran -- FormInvalid laundered into FormPoisoned.
  let carries : bool =
    (form != FormPoisoned) & (form != FormInvalid) & carryOutOfAddrField(a, delta);
  /* Poisoned / invalid inputs come back untouched from setCapAddrChecked's own form
   * dispatch, and `carries` is false for them, so they are returned exactly as given. */
  /* Notes: the OUTER poison must pass `cap` too, not the inner result -- the inner call
   * already returns `addr = new48` on success, so poisoning that value would put the
   * carried-into-nowhere address into the repair entry point (D-224). Fixing only the
   * inner one changes nothing here. */
  poisonIf(if carries then cap else setCapAddrChecked(cap, truncate(sum, truisa_address_width)),
           carries)
}

// Not "setCapAddr plus a sealed check" -- TruISA has no seal (ADR-0001). Two criteria, in
// spec order: (1) representable = same slot (bare: the same bit(VA-1) half), (2) intact --
// SCADDR does have an integrity criterion (ADR-0029 decision 11.5 corrected an earlier
// reading that dropped it). `pac` is copied: the MAC covers the CentroID, and (1) just
// proved the slot held. The blueprint's unchecked `setCapAddr` is not defined here -- no
// caller would exist. why: doc/truisa-deltas.md#scaddr
function setCapAddrChecked(cap : Capability, addr : CapAddrBits) -> Capability = {
  let form = getCapForm(cap);
  /* Illegal inputs are copied as they are, never laundered into something usable. This is
   * the ONE place the form is dispatched for the address setter. */
  if form == FormPoisoned | form == FormInvalid then cap
  else {
    let a : CapAddrBits = cap.address[truisa_address_width - 1 .. 0];
    let newCap : Capability = struct {
      mode    = cap.mode,
      nc      = cap.nc,
      pac     = cap.pac,
      address = sign_extend(addr),
    };
    /* Criteria (1) then (2), in the spec's order, so a future xtval can say which failed
     * first. One call each -- the definitions are in 1c-2a, not here.
     * Notes: the poisoned result carries the CALLER's address, not `addr` (D-224). The
     * poison address is a REPAIR ENTRY POINT: software re-binds from it (SCBNDS/DIDW), so
     * handing back the address that failed to be written would rebuild the pointer in
     * somebody else's object -- fail-then-repair must not become a privilege escalation. */
    poisonIf(cap, not(sameSlot(a, cap.nc, form, addr)) | not(ptrIntact(cap, form)))
  }
}
