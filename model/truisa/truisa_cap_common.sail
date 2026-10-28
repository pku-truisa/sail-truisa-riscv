/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

/* ===== TruISA width switch: the ONLY place to change the VA profile ===== */
// Pointer layout (ADR-0003 rev 12), from the top bit down:
//   bit 63        mode    truisa_mode_width = 1
//   bits 62-57    N/C     truisa_nc_width   = 6
//   bits 56-48    PAC     truisa_pac_width  = ptr - VA - mode - N/C (computed)
//   bits 47-0     address truisa_va
// Every width below is derived from these four; no bit position is hard-coded.
type truisa_ptr_width   : Int = xlen           // 64 on RV64 (TruISA targets RV64)
let  truisa_ptr_width   = sizeof(truisa_ptr_width)
type truisa_va          : Int = 48              // Sv48; Sv39 -> 39, Sv57 -> 57
let  truisa_va          = sizeof(truisa_va)
type truisa_mode_width  : Int = 1
let  truisa_mode_width  = sizeof(truisa_mode_width)
type truisa_nc_width    : Int = 6
let  truisa_nc_width    = sizeof(truisa_nc_width)
// PAC takes whatever is left between the tag and the address:
//   Sv39 -> 64-39-7 = 18 | Sv48 -> 64-48-7 = 9 | Sv57 -> 64-57-7 = 0
type truisa_pac_width   : Int = truisa_ptr_width - truisa_va - truisa_mode_width - truisa_nc_width
let  truisa_pac_width   = sizeof(truisa_pac_width)

// ---- CHERI-compatibility aliases: keep the blueprint's field/type names so
// ---- that the rest of the model needs no renaming. The truisa_* names above
// ---- remain the ONLY place to change a width.

// Width of capability in bytes (excluding tag).
// TODO: Rename to clen_bytes and clen?
// TODO: Change root xlen to be in terms of the log2 bytes.
type cap_size : Int = xlen_bytes          // TruISA: pointer is 64-bit (CHERI used xlen_bytes * 2)
let  cap_size = sizeof(cap_size)

type cap_addr_width : Int = truisa_va          // was xlen (CHERI); TruISA uses the VA width
let  cap_addr_width = sizeof(cap_addr_width)
type cap_len_width : Int = cap_addr_width + 1
let  cap_len_width = sizeof(cap_len_width)
type cap_mode_width : Int = truisa_mode_width
let  cap_mode_width = sizeof(cap_mode_width)
type cap_nc_width : Int = truisa_nc_width
let  cap_nc_width = sizeof(cap_nc_width)
type cap_pac_width : Int = truisa_pac_width
let  cap_pac_width = sizeof(cap_pac_width)

type cap_max_len : Int = (2 ^ cap_len_width) - 1
let  cap_max_len = sizeof(cap_max_len)

let cap_max_addr = pow2(cap_addr_width) - 1

// 64 bits (TruISA: single-width pointer; no 128-bit capability encoding).
type CapBits = bits(8 * cap_size)

// XLEN (32 or 64).
type CapAddrBits  = bits(cap_addr_width)
type CapAddrInt   = range(0, (2 ^ cap_addr_width) - 1)
// TruISA: PAC width follows the VA profile (57 - VA). Sv57 -> 0 (no PAC).
type CapPacBits   = bits(cap_pac_width)
// Tag = mode + N/C = the top bits left after address and PAC. Substituting
// PAC = 57 - VA gives 1 + 6 = 7 for EVERY profile, which is exactly ADR-0003
// rev 12: the tag is bits 63-57 and its width does not vary across profiles.
type CapTagBits   = bits(cap_mode_width + cap_nc_width)
// Metadata = everything that is NOT the address: mode | N/C | PAC (16 bits on
// Sv48). Same role as CHERI's 64-bit metadata word, only narrower -- TruISA
// keeps it in the pointer's high bits instead of a separate word.
type CapMetaBits  = bits(cap_mode_width + cap_nc_width + cap_pac_width)

// XLEN+1 (33 or 65).
type CapLenBits   = bits(cap_len_width)
type CapLenInt    = range(0, cap_max_len)

// Capability level bits (> 1 is experimental)
type lvlbits : Int = 1
let lvlbits = sizeof(lvlbits)

// A partially decompressed version of a capability. Note that this is a
// losslessly decompressed version. All of the original metadata bits are
// preserved, including reserved ones. This is necessary so that CSetHigh works.
struct Capability = {
  // TruISA: 64-bit in-band tagged pointer (ADR-0003; docs/isa/03)
  //   bit 63      mode(1)
  //   bits 62-57  N/C(6)
  //   bits 56-48  PAC(9)     -- Sv48; PAC width = 57 - VA
  //   bits 47-0   address(48)
  // NOTE: differs from CHERI -- no tag/perms/seal, no E-B-T compression,
  //       and the bounds are NOT stored in the pointer.
  // 2026-10-26: the `bit 56` reserved bit is REMOVED; PAC width = 57 - VA
  //             (Sv39 -> 18, Sv48 -> 9, Sv57 -> 0, i.e. no PAC at all).
  //             Sv57 (pac width 0) is NOT validated: this model instantiates Sv48.
  mode    : bits(cap_mode_width),
  nc      : bits(cap_nc_width),
  pac     : CapPacBits,
  address : CapAddrBits,
}

// Decode compressed capability to a more convenient struct.
function bitsToCap(tag : bool, cap_bits : CapBits) -> Capability = {
  // TruISA has NO compressed encoding: the pointer word IS the capability, so
  // decoding is a plain field split.
  // Bit positions are DERIVED from the width constants above -- switching the
  // VA profile needs no edit here.
  // `tag` is CHERI's out-of-band validity bit; TruISA carries it in-band, so
  // this argument is IGNORED BY DESIGN (D-44 ruling 丙).
  struct {
    mode    = cap_bits[truisa_ptr_width - 1],
    nc      = cap_bits[truisa_ptr_width - 2 .. truisa_ptr_width - 1 - truisa_nc_width],
    // PAC can be zero-width (Sv57), where the slice would be ill-formed.
    pac     = if truisa_pac_width == 0 then zeros()
              else cap_bits[truisa_ptr_width - 2 - truisa_nc_width .. truisa_va],
    address = cap_bits[truisa_va - 1 .. 0],
  }
}

// The metadata half of a pointer: everything that is not the address, i.e.
// mode | N/C | PAC (16 bits on Sv48). This is the TruISA counterpart of CHERI's
// capToMetadataBits, which returns the high 64-bit word of a 128-bit
// capability (what GCHI calls "the metadata, bits [CLEN-1:MXLEN]").
//
// TruISA has NO separate metadata word -- the metadata lives in the pointer's
// high bits -- so this returns 16 bits, not a whole register. To get the full
// pointer word use capToBits; to get only the form-deciding tag use
// getCapTagBits (7 bits).
val  capToMetadataBits : Capability -> CapMetaBits
function capToMetadataBits(cap : Capability) -> CapMetaBits =
  cap.mode @ cap.nc @ cap.pac

// Zero permission capability.
// TODO: We should be able to use bitsToCap(false, zeros()) but there
// seems to be a bug: https://github.com/rems-project/sail/issues/424
let null_cap : Capability = struct {
  mode    = 0b0,
  nc      = zeros(),
  pac     = zeros(),
  address = zeros(),
}

// Get the full cap bounds (base and top) as bit vectors.
/* ===== TruISA helpers: pointer form decoding (ADR-0003 rev 8) ===== */

// Assemble the 64-bit pointer from its fields: mode | N/C | PAC | address.
// This is the inverse of bitsToCap and the ONLY way to get the raw 64-bit
// value out of a Capability. Needed wherever a function takes `xlenbits`
// (e.g. getCapBoundsBits) but the caller holds a Capability (from C()).
val  capToBits : Capability -> xlenbits
function capToBits(cap : Capability) -> xlenbits =
  cap.mode @ cap.nc @ cap.pac @ cap.address

/* ===== The "C() view": pointers live in the integer register file =====
 * ADR-0017: TruISA has NO separate capability register file. So C() is nothing
 * more than bitsToCap/capToBits over X, exposed through the same four-way
 * overload that the blueprint uses (model/cheri/cheri_regs.sail:26). That is
 * what lets every instruction be written as C(cs1) / C(cd) = v exactly as
 * in the blueprint, without any of them knowing where the bits are kept.
 *
 * rX(r) already returns 0 for x0, so rC(0) is the all-zero capability
 * (null_cap) for free -- no special case needed here.
 *
 * ⚠️ This overload is mutually exclusive with the CHERI model's `overload C`.
 * A single Sail invocation must include model/truisa OR model/cheri, never both.
 */
function rC(r : regno) -> Capability = bitsToCap(false, X(r))

function wC (Regno(r) : regno, v : Capability) -> unit =
  X(Regno(r)) = capToBits(v)

function rC_bits(Regidx(i) : regidx) -> Capability = rC(Regno(unsigned(i)))

function wC_bits(Regidx(i) : regidx, v : Capability) -> unit =
  wC(Regno(unsigned(i)), v)

overload C = {rC_bits, wC_bits, rC, wC}

// The tag: the top (mode + N/C) bits of a pointer. Every form decision hangs
// off this value. Named "Bits" to match the blueprint's getCapBoundsBits.
// Bit positions are derived, never hard-coded: the tag ends at
// ptr_width-1 and spans (mode + N/C) bits downwards.
val  getCapTagBits : xlenbits -> CapTagBits
function getCapTagBits(ptr : xlenbits) -> CapTagBits =
  ptr[truisa_ptr_width - 1 .. truisa_ptr_width - cap_mode_width - cap_nc_width]

// The N/C field: the bits just below mode. Split out because both getCapForm and
// getCapBoundsBits need it, and duplicating the slice invites bit-position drift.
val  getCapN : xlenbits -> bits(cap_nc_width)
function getCapN(ptr : xlenbits) -> bits(cap_nc_width) =
  ptr[truisa_ptr_width - 2 .. truisa_ptr_width - 1 - cap_nc_width]

// Slot base of an aligned-slot pointer: SlotBase = p & ~(2^N - 1)
// (docs/isa/04; ADR-0010 decision 4). Operates inside the address field only.
val  getCapSlotBase : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapSlotBase(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits =
  p & ~(zero_extend(ones(unsigned(n))))

// CentroID canonical representative point: m = SlotBase + 2^(N-1)  (ADR-0004)
// CentroID is formally a PAIR -- left = S + 2^(N-1) - 1, right = S + 2^(N-1) --
// but a single 48-bit point already carries all (N, S) information, and the
// RIGHT point m is the canonical representative (ADR-0004 rev 4: the left
// point degenerates when l = 0). This function returns that canonical point.
// NOTE: computes the address only; `N` is taken from the pointer's N/C field
//       by the caller (see getCapBoundsBits for the valid range 0..VA).
//
// ⛔ The 48-bit point m MUST NOT be used to index the descriptor table. Keys
//    are always (C, S): a lone point m also names the slot (ctz(m)+1, ...), so
//    point-keying silently aliases another object's entry -- DCLR would clear
//    an unrelated entry and a lookup would return someone else's bounds.
//    `cid == 0` means "none" (see below).  (ADR-0004 rev 4; isa/05; spec/ch05)
//
// N = 0 (1-byte slot) has NO CentroID: S + 2^(-1) is not an integer, so the
// midline does not exist. This is SETTLED, NOT AN OPEN QUESTION --
//   ADR-0004 corollary + rev 5; isa/03 §3.4.4 item 1; isa/05 §5.5; spec/ch03.
// It returns 0, the RESERVED value / NULL of this domain, for three reasons:
//   - every legal CentroID is >= 1 (Aligned C in [1,47] gives S + 2^(C-1) >= 1;
//     bare gives 2^(VA-1)) and ADR-0004 theorem 6 has codomain m > 0, so 0 is
//     structurally unreachable -- the only free code point in the domain;
//   - it depends on NOTHING about p, so it cannot alias a real slot: a lookup
//     with cid = 0 misses even if the caller forgets to test for it;
//   - it matches the table-side empty-entry convention (base,bound)==(0,0)
//     (ADR-0006 decision 3) rather than inventing a second notion of "empty".
// ⛔ Do NOT make this value depend on p; ⛔ do NOT treat 0 as a legal CentroID.
val  getCapCentroID : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits = {
  let base : CapAddrBits = getCapSlotBase(p, n);
  // N = 0 (no midline) and N = VA (whole-space slot, midline collides with the
  // bare pointer's) both yield the reserved value 0 -- ADR-0004 rev 7.
  if (n == 0b000000) | (unsigned(n) == truisa_va) then zeros()
  else base + zero_extend(0b1 @ zeros(unsigned(n) - 1))
}

/* TODO (descriptor phase) -- `getCapCentroID` gives the CentroID representative.
   It is deliberately NOT used by GCBASE / GCBOUND: those return SlotBase and
   SlotBase | (2^N - 1) respectively. It is factored out because the descriptor
   phase (DSTR / DIDW / DGU / DFENCE) needs the CentroID in several places --
   keep this single definition, do not inline it. Its validity domain must
   follow the same N range as getCapSlotBase (0..VA).
   ⚠️ N = 0 is a VALID input but yields the reserved value 0, so the descriptor
   phase must treat cid == 0 as a MISS everywhere (DSTR / DCLR / DIDW) -- never
   as "the entry at address 0". */

/* ===== Bounds of a TruISA pointer =====
   Returns (base, bound) as XLEN integers. `bound` is the INCLUSIVE last byte
   (ADR-0018 rev 7), so bound = base + 2^N - 1 = base | (2^N - 1).

   Forms (ADR-0003 rev 8, three-step test):
     0000000  Bare low   -> (0, 2^VA - 1)        [whole address space, K = VA]
     1111111  Bare high  -> (0, 2^VA - 1)        [same: bit47 no longer matters]
     0111111  poisoned   -> None()
     1xxxxxx  Aligned    -> (SlotBase(p, N), SlotBase | (2^N - 1))
     0xxxxxx  CentroID   -> None()   (descriptor form not supported in phase 1)

   U1: the endpoints are the 48-bit FIELD values, ZERO-extended by the
       projection instructions (ADR-0019 rev 8; ADR-0023 decision 1). They are
       NOT canonical VA: a canonical address sign-extends bit VA-1 instead, so
       on the high side GC* gives 0x0000_8000_... while the canonical form is
       0xFFFF_8000_.... Never feed a GC* result to a load/store or to a CSR
       that needs a canonical address -- normalise in software (slli+srai).
   U2: poisoned pointer -> None(), NOT a fabricated value.
   U3 (GC-3): an illegal code point yields None(), and None() is NOT a trap.
       Two layers: the data path raises (TYPE, CAUSE = 3); the projection
       instructions (GCBASE/GCBOUND/GCADDR/CSUB/SCEQ) never trap. spec/ch07
       rewords "no failure track" to "does not raise a trap".
   U4 (GC-4): N must be in 0..VA (ADR-0026 decision 1; ADR-0003 rev 22).
       N = VA is LEGAL -- it is the whole-address-space slot. It is NOT
       excluded on purpose: excluding it would let user code mint a full-range
       pointer with a single `li`, so the gate is the OS issuing policy, not
       validNC (ADR-0026 decisions 5-6). The older argument ("signing an N=48
       slot would mint a signable full-range pointer") is WITHDRAWN.
*/
/* ===== TruISA pointer form: the ONE place that decides what a pointer is =====
 * ADR-0003 rev 12. Every caller that needs to know "what kind of pointer is
 * this / is it usable" must ask getCapForm() rather than re-deriving it, otherwise
 * the checks drift apart (that is exactly how the CHERI boundsMalformed /
 * getCapBoundsBits pair ended up disagreeing -- boundsMalformed itself is gone:
 * getCapForm already answers it with one enum compare).
 *
 * Decision order is forced by the bit patterns. The two all-ones/all-zeros
 * tags are peeled off FIRST, because 0111111 would otherwise look like
 * "mode = 0, N/C = 63" and 1111111 like "mode = 1, N/C = 63":
 *   bits 63-57 = 0111111  -> poisoned
 *   bits 63-57 = 0000000  -> bare
 *   bits 63-57 = 1111111  -> bare
 * The 7-bit tag is NOT enough on its own: spec/ch03 "合法性判据" splits "the
 * rest" by bit 63 AND constrains the block exponent for BOTH branches --
 *   aligned slot : N in 0 .. VA
 *   descriptor   : C in 1 .. VA
 * so the range test runs BEFORE the mode split, and it is the same test for
 * both forms (anything above VA is an illegal code point either way):
 *   N/C > VA              -> Invalid code point  (both forms)
 *   bit 63 = 1            -> Aligned slot
 *   otherwise (bit 63 = 0)-> Descriptor form (phase 2; unreachable in phase 1)
 * ⚠️ No lower-bound test is needed for the descriptor: N/C = 0 together with
 * bit 63 = 0 is the tag 0000000, which was already classified as Bare above.
 * So any tag reaching the descriptor branch has C >= 1, as spec requires.
 */
enum CapPtrForm = {
  FormPoisoned,
  FormBare,
  FormInvalid,
  FormDescriptor,      // reserved: no operator produces it in phase 1
  FormAligned,
}

val  getCapForm : xlenbits -> CapPtrForm
function getCapForm(ptr : xlenbits) -> CapPtrForm = {
  let tag7 : CapTagBits = getCapTagBits(ptr);
  let nc : Int = unsigned(tag7[5 .. 0]);
  if      tag7 == 0b0111111 then FormPoisoned
  else if tag7 == 0b0000000 then FormBare
  else if tag7 == 0b1111111 then FormBare
  else if nc > truisa_va then FormInvalid              // both forms: N/C in 0..VA
  else if tag7[6] == 0b1 then FormAligned
  else FormDescriptor                                  // phase 1 never gets here
}

// Slot endpoints for exponent K: [slot_base(addr,K), slot_base(addr,K)+2^K-1].
// The bound is an OR because the low K bits of the base are already zero.
val  slotBounds : (CapAddrBits, Int) -> (CapAddrBits, CapAddrBits)
function slotBounds(addr : CapAddrBits, k : Int) -> (CapAddrBits, CapAddrBits) = {
  let base  : CapAddrBits = getCapSlotBase(addr, to_bits(cap_nc_width, k));
  let bound : CapAddrBits = base | zero_extend(ones(k));
  (base, bound)
}

val  getCapBoundsBits : Capability -> option((CapAddrBits, CapAddrBits))
function getCapBoundsBits(cap : Capability) -> option((CapAddrBits, CapAddrBits)) = {
  // Returns the endpoints in the ADDRESS domain (48 bits); the instruction
  // sign-extends them to XLEN itself (spec/insns/gcbase.adoc and gcbound.adoc
  // both wrap the result in zero_extend_48).
  //
  // Bare and Aligned are UNIFIED into one formula, following the spec:
  //   let K = (form == bare) ? VA - 1 : N(cs1);
  // so a bare pointer is simply a slot with K = VA (the whole address space).
  //
  // The form decision itself lives in getCapForm(); this function only maps a
  // usable form to endpoints.
  let ptr : xlenbits = capToBits(cap);
  let addr : CapAddrBits = ptr[47 .. 0];
  match getCapForm(ptr) {
    FormBare    => { let (base, bound) = slotBounds(addr, truisa_va); Some(base, bound) },
    FormAligned => { let (base, bound) = slotBounds(addr, unsigned(getCapN(ptr))); Some(base, bound) },
    _           => None(),          // poisoned / invalid / CentroID (phase 1)
  }
}

/* ===== TruISA pointer construction helpers ===== */

// Poisoned pointer: tag bits 63-57 = 0111111, PAC cleared, address preserved.
// (ADR-0003 rev 21; the address stays so that GCADDR/GCBASE still return it.)
val  poisonIf : (Capability, bool) -> Capability
function poisonIf(cap, cond) =
  if cond then {
    struct {
      mode    = 0b0,
      nc      = 0b111111,
      pac     = zeros(),
      address = cap.address,
    }
  } else cap

// Smallest slot exponent C (0 .. VA) whose aligned slot covers [addr, bound].
// `bound` is the CLOSED-interval last byte of the REQUEST (same convention as
// getCapBoundsBits' second component), so callers that hold a length pass
// base + L - 1 -- no exclusive upper bound and no subtraction in here.
//
// ⭐ CLOSED FORM -- no loop, no search. A 2^C slot is aligned, so the request
// fits iff addr and bound fall in the SAME 2^C-aligned block:
//     addr >> C == bound >> C     <=>     addr ^ bound < 2^C
// so the smallest such C is exactly the bit length of the XOR:
//     C = bit_length(addr ^ bound)            bit_length(0) = 0
// One XOR plus one CLZ (XLEN - count_leading_zeros) -- single cycle in a DGU.
// Do NOT reintroduce an n = n + 1 search: the enumerative form is readable but
// not synthesizable at speed.
//
// Examples (VA = 48):
//   addr 0x1000, bound 0x100F -> xor 0x000F -> C = 4    (16B slot)
//   addr 0x1009, bound 0x1010 -> xor 0x0019 -> C = 5    (32B slot, unaligned start)
//   addr X,      bound X      -> xor 0      -> C = 0    (1B slot)
//   addr 0,      bound 2^VA-1 -> xor all 1s -> C = VA   (whole address space)
//
// Only ONE failure is possible here: bound < addr, i.e. the caller asked for an
// empty (or wrapped) request. An over-large bound cannot occur -- the type is
// CapAddrBits, so it is inside the address space by construction. (ADR-0026:
// C = VA is legal, so the whole space is a valid slot.)
val  minSlotExponent : (CapAddrBits, CapAddrBits) -> option(bits(cap_nc_width))
function minSlotExponent(addr : CapAddrBits, bound : CapAddrBits) -> option(bits(cap_nc_width)) = {
  if bound <_u addr then None()                      // empty request: no byte to cover
  else {
    let diff : xlenbits = zero_extend(addr) ^ zero_extend(bound);
    let slotExp : Int = if diff == zeros() then 0 else xlen - count_leading_zeros(diff);
    Some(to_bits(cap_nc_width, slotExp))
  }
}

// Utility to get the cap bounds (base and top) as integers.
// Same endpoints as getCapBoundsBits, converted to Int so callers can subtract
// and compare without bit-vector plumbing.
// ⚠️ Both components live in the ADDRESS domain: the second one is `bound`, the
// CLOSED-interval last byte, NOT an exclusive `top`. TruISA has no endpoint
// outside the address space, so nothing here needs CapLenInt's extra bit.
function getCapBounds(cap : Capability) -> option((CapAddrInt, CapAddrInt)) =
  match getCapBoundsBits(cap) {
    None()        => None(),
    Some(base, bound) => Some(unsigned(base), unsigned(bound))
  }

/* An 'ideal' version of setCapBounds as described in paper. */
// Build an aligned capability for the slot 2^N that contains `base`. The slot
// base is passed in already computed: turning N into an address has to be done
// in Int, because N is 6 bits and may exceed VA (where 2^N - 1 covers the whole
// address field and getCapSlotBase's ones(N) would not be expressible).
val  makeAlignedPtr : (CapAddrBits, bits(cap_nc_width)) -> Capability
function makeAlignedPtr(slotBase : CapAddrBits, n : bits(cap_nc_width)) -> Capability =
  struct {
    mode    = 0b1,
    nc      = n,
    pac     = zeros(),                 // TODO(PAC): signing is done by the instruction
    address = slotBase,
  }

// Derive a child capability: the slot 2^N containing `base`, returned together
// with whether that slot lies INSIDE the parent's checked interval -- the
// monotonicity condition of ADR-0013 (a derived capability may only narrow).
//
// ⭐ No top and no L (ADR-0028): the caller supplies N. Everything is computed
// in Int, which is exactly why an explicit "N <= VA" test is unnecessary: for
// N > VA the slot end exceeds any parent's hi, so the monotonicity check
// rejects it on its own. A parent that is poisoned / invalid answers None()
// from getCapBoundsBits, so it rejects too.
val  setCapBounds : (Capability, CapAddrBits, bits(cap_nc_width)) -> (bool, Capability)
function setCapBounds(parent : Capability, base : CapAddrBits, n : bits(cap_nc_width)) -> (bool, Capability) = {
  let slotExp : Int = unsigned(n);
  let baseInt : Int = unsigned(base);
  // SlotBase = base & ~(2^N - 1); for N >= VA the mask covers the whole field.
  let slotBaseInt : Int = if slotExp >= truisa_va then 0
                          else baseInt & ~(pow2(slotExp) - 1);
  let slotEndInt  : Int = slotBaseInt + pow2(slotExp) - 1;
  let newCap : Capability = makeAlignedPtr(to_bits(truisa_va, slotBaseInt), n);
  let inParent : bool = match getCapBoundsBits(parent) {
    None()             => false,
    Some(lo, hi)       => (slotBaseInt >= unsigned(lo)) & (slotEndInt <= unsigned(hi)),
  };
  (inParent, newCap)
}

function capIsSealed(cap : Capability) -> bool = cap.sealed

function sealCap(cap : Capability) -> Capability =
  {cap with sealed=true}

function unsealCap(cap : Capability) -> Capability =
  {cap with sealed=false}

// A capability is malformed if it has a reserved permission encoding.
function permsMalformed(cap : Capability) -> bool =
  not(ap_m_valid_bits(cap.ap_m))

// Utility field functions.

function getCapPermsAndMode(cap : Capability) -> option((ArchPerms, ExecutionMode)) =
  if permsMalformed(cap) then None() else Some(ap_m_decode(cap.ap_m))

function setCapPermsAndMode(cap : Capability, (perms, mode): (ArchPerms, ExecutionMode)) -> Capability =
  {cap with ap_m = ap_m_encode(legalizePermsAndMode(perms, mode))}

function getArchPerms(cap : Capability) -> option(ArchPerms) =
  match getCapPermsAndMode(cap) {
    None() => None(),
    Some(perms, _) => Some(perms)
  }

function getArchPermsLegalized(cap : Capability) -> ArchPerms =
  match getArchPerms(cap) {
    None() => null_perms,
    Some(perms) => perms
  }

// Extract capability mode bit, legalising to integer pointer mode if decoding goes wrong
function getCapMode(cap : Capability) -> ExecutionMode =
  match getCapPermsAndMode(cap) {
    None() => execution_mode_encdec(0b0),
    Some(_, mode) => mode,
  }

function setArchPerms(cap : Capability, perms : ArchPerms) -> Capability =
  setCapPermsAndMode(cap, (perms, getCapMode(cap)))

function setCapMode(cap : Capability, mode : ExecutionMode) -> Capability =
  setCapPermsAndMode(cap, (getArchPermsLegalized(cap), mode))

function canASR(cap : Capability) -> bool = getArchPermsLegalized(cap).ASR
function canX(cap : Capability) -> bool = getArchPermsLegalized(cap).X
function canR(cap : Capability) -> bool = getArchPermsLegalized(cap).R
function canW(cap : Capability) -> bool = getArchPermsLegalized(cap).W
function canC(cap : Capability) -> bool = getArchPermsLegalized(cap).C
function canLM(cap : Capability) -> bool = getArchPermsLegalized(cap).LM
function canEL(cap : Capability) -> bool = getArchPermsLegalized(cap).EL
function canSL(cap : Capability) -> bool = getArchPermsLegalized(cap).SL

// Format used by GCPERM and ACPERM.
bitfield BitPerms : xlenbits = {
  reserved_1  : xlen - 1                   .. 19,
  R           : 18,
  X           : 17,
  ASR         : 16,
  reserved_0  : 15                         .. 6 + cap_sd_perms_width,
  SDP         : 6 + cap_sd_perms_width - 1 .. 6,
  C           : 5,
  CL          : 4,
  SL          : 3,
  EL          : 2,
  LM          : 1,
  W           : 0,
}

// Convert the capability permissions into the format expected by GCPerm and ACPerm.
function packPerms(arch_perms : ArchPerms, cap_level : bits(lvlbits), sd_perms : bits(cap_sd_perms_width)) -> BitPerms =
  [
    Mk_BitPerms(zeros()) with
    SDP = sd_perms,
    ASR = bool_bits(arch_perms.ASR),
    X = bool_bits(arch_perms.X),
    R = bool_bits(arch_perms.R),
    W = bool_bits(arch_perms.W),
    C = bool_bits(arch_perms.C),
    LM = bool_bits(arch_perms.LM),
    SL = bool_bits(arch_perms.SL),
    EL = bool_bits(arch_perms.EL),
    CL = cap_level,
  ]

function unpackPerms(perms : BitPerms) -> (ArchPerms, bits(lvlbits), bits(cap_sd_perms_width)) = {
  let arch_perms : ArchPerms =
    struct {
      ASR = bool_bits(perms[ASR]),
      X = bool_bits(perms[X]),
      R = bool_bits(perms[R]),
      W = bool_bits(perms[W]),
      C = bool_bits(perms[C]),
      LM = bool_bits(perms[LM]),
      SL = bool_bits(perms[SL]),
      EL = bool_bits(perms[EL]),
    };
  (arch_perms, perms[CL], perms[SDP])
}

// Smallest representable length >= len: the slot size 2^N_c that would cover an
// object of this length starting at address 0. CHERI derived this from the
// compressed encoding; TruISA takes it straight from minSlotExponent.
val  getRepresentableLength : xlenbits -> xlenbits
function getRepresentableLength(len : xlenbits) -> xlenbits =
  if len == zeros() then zeros()                          // nothing to represent
  else match minSlotExponent(zeros(), (len - 1)[truisa_va - 1 .. 0]) {
    None()  => zeros(),                                   // no slot can cover it
    Some(n) => zero_extend(ones(unsigned(n))) + 1,         // 2^N_c
  }

// Alignment mask implied by getRepresentableLength: 2^N_c - 1.
val  getRepresentableAlignmentMask : xlenbits -> xlenbits
function getRepresentableAlignmentMask(len : xlenbits) -> xlenbits =
  getRepresentableLength(len) - 1

// NOTE(ADR-0019 rev 7 + ADR-0026): a bare pointer now covers the WHOLE
// address space (K = VA, SlotBase = 0, bound = 2^VA - 1), so Len = 2^VA for
// it. The formula below still needs no special case -- base = 0 and
// bound = 2^VA - 1 make it fall out. (The old premise "no pointer spans the
// whole space" is withdrawn.)
// Length of the pointed-to region. `bound` is the CLOSED-interval last byte,
// so the length is bound - base + 1 (not bound - base). The old name `top`
// came from CHERI, where it meant the EXCLUSIVE upper bound -- opposite
// semantics, which is exactly how the missing +1 slipped in.
function getCapLength(cap : Capability) -> CapLenInt =
  match getCapBounds(c) {
    None() => 0,
    Some(base, bound) => {assert(bound >= base); bound - base + 1},
  }

// Return true if the range [addr, addr+size) is in the cap bounds.
// The upper bound arithmetic is allowed to overflow, wrapping the address space.
// `top` can be >= 2^xlen, in which case the entire address space is in bounds
// provided `base == 0`. RISC-V allows accesses to wrap, so for example if
// `addr` is 2^xlen - 2 and `size` is 4 then it will access the two highest
// bytes and the two lowest bytes. The only situation in which a wrapped
// access is in bounds is if the highest and lowest bytes are in bounds of the
// unwrapped capability bounds, and that can only happen if `base` is 0 and
// `top` is >=2^xlen (in which case every access is in bounds so we don't need
// to check `addr` or `size` at all.
function inCapBounds(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  // --- TruISA guards (D-37). These MUST run before any interval comparison. ---
  // size = 0     : an empty interval contains no byte. If instead one computed
  //                `addr + size - 1 <= bound`, that is almost always TRUE
  //                (addr - 1 <= bound) -> zero-length objects would look valid
  //                everywhere.
  // size > 2^VA  : rejects requests longer than the address space outright.
  //                (Historically this guard also stopped `addr + size - 1`
  //                from wrapping in a 64-bit bit-vector. That reason is gone:
  //                the comparison below runs in Int, which cannot wrap. The
  //                guard stays because a request longer than the space is
  //                meaningless, not because of arithmetic.)
  // --- Zero-address veto (spec/ch04 "零地址判据"). Independent of the three
  // --- steps, and applies to EVERY form including Bare: address 0 is reserved
  // --- as NULL. The bounds interval is NOT shrunk (it still starts at 0), so
  // --- GCBASE(Bare) and Len = bound - base + 1 keep their formulas.
  // --- Exit for loads/stores is the exception (TYPE,CAUSE) = (1,3); here we
  // --- only answer the predicate, the caller raises it.
  // --- NOTE: this rejects the ACCESS, not the CONSTRUCTION -- SCBNDS/SCBNDSI
  // --- may still produce an addr==0 pointer; derived stores that would MOVE a
  // --- pointer to 0 must poison instead (not implemented yet, G2).
  if addr == zeros() then return false;
  if size == 0 then return false;
  if size > (2 ^ truisa_va) then return false;

  // CLOSED interval: the last byte touched is a + size - 1, which must be <= bound.
  // (size >= 1 was checked above, so size - 1 cannot underflow.) `a + size - 1`
  // is computed in Int, so it cannot wrap: an over-long request simply exceeds
  // bound and fails.
  let addrInt = unsigned(addr);
  match getCapBounds(cap) {
    None()          => false,
    Some(base, bound) => (addrInt >= base) & ((addrInt + size - 1) <= bound)
  }
}

// Return true if any byte of the access is within the cap bounds
// Used for certain CBO instructions
// "Does ANY byte of [addr, addr+size) lie inside the bounds?" -- the predicate
// used where over-approximation is the safe answer (it is a MAY, not a MUST).
// Guard size >= 1 locally: with size = 0 the second conjunct degenerates to
// `addrInt > base`, which is true for most addresses, so a zero-length request
// would claim to touch the object.
function anyByteInCapBounds(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  if size < 1 then false
  else {
    let addrInt = unsigned(addr);
    match getCapBounds(cap) {
      None()            => false,
      Some(base, bound) => ((addrInt <= bound) & ((addrInt + size) > base)),
    }
  }
}

// Return true if the range [addr, addr+size) is in the cap bounds.
// The upper bound arithmetic is full-width and isn't wrapped.
// Same test as inCapBounds but WITHOUT the wrapping allowance -- used by SCBNDS
// criterion (3) on the source interval. Closed interval, same reasoning.
// Guard size >= 1 locally: the callers currently reject L = 0 themselves, but a
// zero size here would make `size - 1` negative and pass almost everywhere.
function inCapBoundsNoWrap(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  if size < 1 then false
  else {
    let addrInt = unsigned(addr);
    match getCapBounds(cap) {
      None()          => false,
      Some(base, bound) => (addrInt >= base) & ((addrInt + size - 1) <= bound),
    }
  }
}

function capReservedValid(cap : Capability) -> bool =
  (cap.reserved_0 == zeros()) & (cap.reserved_1 == zeros())

function capTaggedAndReservedValid(cap : Capability) -> bool =
  cap.tag & capReservedValid(cap)

// Return true if c0's bounds and permissions are a subset of c1's.
function capIsSubset(c0 : Capability, c1 : Capability) -> bool = {
  let bounds_subset : bool = match (getCapBounds(c0), getCapBounds(c1)) {
    (None(), _) => false,
    (_, None()) => false,
    (Some(c0_base, c0_top), Some(c1_base, c1_top)) =>
      (c0_base >= c1_base) & (c0_top <= c1_top)
  };
  let perms_subset : bool = match (getArchPerms(c0), getArchPerms(c1)) {
      (None(), _) => false,
      (_, None()) => false,
      (Some(c0_arch_perms), Some(c1_arch_perms)) => {
        let c0_perms_packed = packPerms(c0_arch_perms, c0.cl, c0.sd_perms).bits;
        let c1_perms_packed = packPerms(c1_arch_perms, c1.cl, c1.sd_perms).bits;
        (c0_perms_packed & c1_perms_packed) == c0_perms_packed;
      }
  };
  let level_subset = c0.cl <=_u c1.cl;
  // Not a subset if reserved bits are set in either cap
  let reserved_valid = capReservedValid(c0) & capReservedValid(c1);
  bounds_subset & perms_subset & level_subset & reserved_valid;
}

function capBoundsEqual (c1 : Capability, c2 : Capability) -> bool =
  match (getCapBounds(c1), getCapBounds(c2)) {
    (None(), _) => false,
    (_, None()) => false,
    (Some(base1, bound1), Some(base2, bound2)) => (base1 == base2) & (bound1 == bound2)
  }

function setCapAddr(cap : Capability, addr : CapAddrBits) -> (bool, Capability) = {
  let newCap = { cap with address = addr };
  // capBoundsEqual returns false if either input has malformed bounds, so the
  // representability check will fail if the old or new bounds were malformed.
  let representable = capBoundsEqual(cap, newCap);
  (representable, newCap)
}

// Moving the address is allowed as long as the SLOT does not change; otherwise
// the result is poisoned. TruISA has no tag bit, no sealed state and no
// reserved bits, so CHERI's clearTagIf(newCap, not(rep) | sealed | !reserved)
// collapses to poisonIf(newCap, not(rep)).
// poisonIf keeps `address`, so a poisoned pointer still answers GCADDR
// (spec/ch03: the address field survives poisoning).
function setCapAddrChecked(cap : Capability, addr : CapAddrBits) -> Capability = {
  let (representable, newCap) = setCapAddr(cap, addr);
  poisonIf(newCap, not(representable))
}

infix 1 >>_s
overload operator >> = {sail_shiftright}
overload operator << = {sail_shiftleft}
overload operator >>_s = {sail_arith_shiftright}

function incCapAddrChecked(cap : Capability, delta : CapAddrBits) -> Capability =
  setCapAddrChecked(cap, cap.address + delta)

// Debug rendering of a capability. TruISA has only four fields plus the slot
// geometry, so there is nothing to "legalize" and nothing to warn about: the
// form already says whether the pointer is usable.
function capToString(cap : Capability) -> string = {
  let form_str : string = match getCapForm(capToBits(cap)) {
    FormPoisoned   => "poisoned",
    FormBare       => "bare",
    FormAligned    => "aligned",
    FormDescriptor => "descriptor",
    FormInvalid    => "invalid",
  };
  let (base_str, bound_str) : (string, string) = match getCapBoundsBits(cap) {
    None()            => ("-", "-"),
    Some(base, bound) => (bits_str(base), bits_str(bound)),
  };
  "form:" ^ form_str ^
  " mode:" ^ bits_str(cap.mode) ^
  " nc:" ^ bits_str(cap.nc) ^
  " pac:" ^ bits_str(cap.pac) ^
  " addr:" ^ bits_str(cap.address) ^
  " base:" ^ base_str ^
  " bound:" ^ bound_str
}

