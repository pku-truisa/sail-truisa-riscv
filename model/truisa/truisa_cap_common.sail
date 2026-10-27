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

// Full permission capability.

// Get the full cap bounds (base and top) as bit vectors.
/* ===== TruISA helpers: pointer form decoding (ADR-0003 rev 8) ===== */

// Assemble the 64-bit pointer from its fields: mode | N/C | PAC | address.
// This is the inverse of bitsToCap and the ONLY way to get the raw 64-bit
// value out of a Capability. Needed wherever a function takes `xlenbits`
// (e.g. getCapBoundsBits) but the caller holds a Capability (from C()).
val  capToBits : Capability -> xlenbits
function capToBits(c : Capability) -> xlenbits =
  c.mode @ c.nc @ c.pac @ c.address

// The tag: the top (mode + N/C) bits of a pointer. Every form decision hangs
// off this value. Named "Bits" to match the blueprint's getCapBoundsBits.
// Bit positions are derived, never hard-coded: the tag ends at
// ptr_width-1 and spans (mode + N/C) bits downwards.
val  getCapTagBits : xlenbits -> CapTagBits
function getCapTagBits(p : xlenbits) -> CapTagBits =
  p[truisa_ptr_width - 1 .. truisa_ptr_width - cap_mode_width - cap_nc_width]

// The N/C field: the bits just below mode. Split out because both formOf and
// getCapBoundsBits need it, and duplicating the slice invites bit-position drift.
val  getCapN : xlenbits -> bits(cap_nc_width)
function getCapN(p : xlenbits) -> bits(cap_nc_width) =
  p[truisa_ptr_width - 2 .. truisa_ptr_width - 1 - cap_nc_width]

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
//       by the caller (see getCapBoundsBits for the valid range 0..VA-1).
// TODO(N = 0): a slot of length 1 has NO midline -- S + 2^(-1) is not an
//   integer, so CentroID is undefined. The current code returns S as a
//   placeholder; callers must NOT rely on it. Whether this should instead
//   return None() (i.e. option) is an open spec question.
val  getCapCentroID : (CapAddrBits, bits(cap_nc_width)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(cap_nc_width)) -> CapAddrBits = {
  let base : CapAddrBits = getCapSlotBase(p, n);
  if n == 0b000000 then base
  else base + zero_extend(0b1 @ zeros(unsigned(n) - 1))
}

/* TODO (descriptor phase) -- `getCapCentroID` gives the CentroID representative.
   It is deliberately NOT used by GCBASE / GCBOUND: those return SlotBase and
   SlotBase | (2^N - 1) respectively. It is factored out because the descriptor
   phase (DSTR / DIDW / DGU / DFENCE) needs the CentroID in several places --
   keep this single definition, do not inline it. Its validity domain must
   follow the same N range as getCapSlotBase (0..VA-1). */

/* ===== Bounds of a TruISA pointer =====
   Returns (base, bound) as XLEN integers. `bound` is the INCLUSIVE last byte
   (ADR-0018 rev 7), so bound = base + 2^N - 1 = base | (2^N - 1).

   Forms (ADR-0003 rev 8, three-step test):
     0000000  Bare low   -> (0, 2^(VA-1) - 1)
     1111111  Bare high  -> (-2^(VA-1), -1)              [sign-extended]
     0111111  poisoned   -> None()
     1xxxxxx  Aligned    -> (SlotBase(p, N), SlotBase | (2^N - 1))
     0xxxxxx  CentroID   -> None()   (descriptor form not supported in phase 1)

   U1: addresses/bounds are sign-extended to XLEN, matching GCADDR
       (ADR-0023: sign_extend(rs1[47:0])) -- so the high half is negative.
   U2: poisoned pointer -> None(), NOT a fabricated value.
   U3 (GC-3): an illegal code point yields None(), and None() is NOT a trap.
       Two layers: the data path raises (TYPE, CAUSE = 3); the projection
       instructions (GCBASE/GCBOUND/GCADDR/CSUB/SCEQ) never trap. spec/ch07
       rewords "no failure track" to "does not raise a trap".
   U4 (GC-4): N must be in 0..VA-1 (ADR-0005 dec 6). N = VA is ILLEGAL: an
       N=48 aligned pointer covers exactly the whole Bare region, so signing
       it would mint a legitimate, signable full-range pointer.
       (ADR-0019 rev 5 dropping the "Len = 2^48 special case" concerns the
       Bare form, NOT N=48.)
*/
/* ===== TruISA pointer form: the ONE place that decides what a pointer is =====
 * ADR-0003 rev 12. Every caller that needs to know "what kind of pointer is
 * this / is it usable" must ask formOf() rather than re-deriving it, otherwise
 * the checks drift apart (that is exactly how the CHERI boundsMalformed /
 * getCapBoundsBits pair ended up disagreeing).
 *
 * Decision order is forced by the bit patterns:
 *   bits 63-57 = 0111111  -> poisoned        (checked FIRST: 0111111 would
 *                                             otherwise look like N/C = 63)
 *   bits 63-57 = 0000000  -> bare (low half)
 *   bits 63-57 = 1111111  -> bare (high half)  (1111111 would otherwise look
 *                                             like mode=1, N/C=63)
 *   bit 63 = 0            -> CentroID form (unsupported in phase 1)
 *   N/C >= VA             -> invalid code point
 *   otherwise             -> aligned slot
 */
enum CapPtrForm = {
  FormPoisoned,
  FormBare,
  FormAligned,
  FormInvalid,
  FormCentroID,
}

val  formOf : xlenbits -> CapPtrForm
function formOf(p : xlenbits) -> CapPtrForm = {
  let tag7 : CapTagBits = getCapTagBits(p);
  if      tag7 == 0b0111111 then FormPoisoned
  else if tag7 == 0b0000000 then FormBare
  else if tag7 == 0b1111111 then FormBare
  else if p[truisa_ptr_width - 1] == 0b0 then FormCentroID
  else if unsigned(getCapN(p)) >= truisa_va then FormInvalid
  else FormAligned
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
function getCapBoundsBits(c : Capability) -> option((CapAddrBits, CapAddrBits)) = {
  // Returns the endpoints in the ADDRESS domain (48 bits); the instruction
  // sign-extends them to XLEN itself (spec/insns/gcbase.adoc and gcbound.adoc
  // both wrap the result in sign_extend_48).
  //
  // Bare and Aligned are UNIFIED into one formula, following the spec:
  //   let K = (form == bare) ? VA - 1 : N(cs1);
  // so a bare pointer is simply a slot with K = VA-1 (one half-space).
  //
  // The form decision itself lives in formOf(); this function only maps a
  // usable form to endpoints.
  let p : xlenbits = capToBits(c);
  let addr : CapAddrBits = p[47 .. 0];
  match formOf(p) {
    FormBare    => { let (b, e) = slotBounds(addr, truisa_va - 1); Some(b, e) },
    FormAligned => { let (b, e) = slotBounds(addr, unsigned(getCapN(p))); Some(b, e) },
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

// Smallest slot exponent N (0 .. VA-1) whose slot covers [addr, top).
// `top` is the EXCLUSIVE upper bound (i.e. addr + L), matching CHERI's
// setCapBounds(cap, base, top) convention.
//   N_c = min{ N : SlotBase(addr,N) + 2^N >= top }
// None() if no such N exists (L too large, or the request crosses the half).
val  minSlotCovering : (CapAddrBits, CapLenBits) -> option(bits(cap_nc_width))
function minSlotCovering(addr : CapAddrBits, top : CapLenBits) -> option(bits(cap_nc_width)) = {
  var found : bool = false;
  var n : Int = 0;
  while (n < truisa_va) & not(found) do {
    let base : CapAddrBits = getCapSlotBase(addr, to_bits(cap_nc_width, n));
    // slot end (exclusive) = base + 2^n = base + (2^n - 1) + 1
    let end : CapLenBits = zero_extend(base) + zero_extend(ones(n)) + 1;
    if end >=_u top then found = true else n = n + 1;
  };
  if found then Some(to_bits(cap_nc_width, n)) else None()
}

// Utility to get the cap bounds (base and top) as integers.
function getCapBounds(cap : Capability) -> option((CapAddrInt, CapLenInt)) =
  match getCapBoundsBits(cap) {
    None()          => None(),
    Some(base, top) => Some(unsigned(base), unsigned(top))
  }

/* An 'ideal' version of setCapBounds as described in paper. */
function setCapBounds(cap : Capability, base : CapAddrBits, top : CapLenBits) -> (bool, Capability) = {
  // TruISA has NO compressed bounds (no E/B/T). Setting bounds means:
  //   address = base, mode = 1 (aligned slot), nc = N_c,
  // where N_c is the smallest exponent whose slot covers [base, top).
  // `top` is the exclusive upper bound, so callers pass base + L.
  //
  // The returned `exact` keeps CHERI's signature meaning "the request was
  // representable" -- in TruISA any request covered by some slot is
  // representable (over-coverage is normal, not an error; see
  // spec/insns/scbnds.adoc "判据 ④ 判的是存在覆盖槽，不是槽刚好等于对象").
  //
  // TODO(PAC): this leaves `pac` zero. Signing is done by the instruction
  // (ADR-0005), whose operator is not implemented yet.
  match minSlotCovering(base, top) {
    None()  => (false, cap),
    Some(n) => (true, struct {
      mode    = 0b1,
      nc      = n,
      pac     = zeros(),
      address = base,
    })
  }
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

// Length of the pointed-to region. `bound` is the CLOSED-interval last byte,
// so the length is bound - base + 1 (not bound - base). The old name `top`
// came from CHERI, where it meant the EXCLUSIVE upper bound -- opposite
// semantics, which is exactly how the missing +1 slipped in.
function getCapLength(c : Capability) -> CapLenInt =
  match getCapBounds(c) {
    None() => 0,
    Some(base, bound) => {assert(bound >= base); bound - base + 1},
  }

// NOTE(ADR-0019 rev 5): the "infinite bounds" concept is GONE. Bare pointers
// now cover only their own half-space (N_p = VA-1), so there is no pointer
// whose bounds span the whole address space. The former helpers
// decodedBoundsInfinite / capBoundsInfinite were dead predicates anyway
// (`top >= 2^xlen` can never hold when top comes from a 48-bit field) and have
// been removed rather than fixed.

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
  // size > 2^VA  : `addr + size - 1` wraps in 64 bits (addr = 0 with
  //                size = 2^48 + 1 yields 2^48); an unsigned comparison would
  //                wrongly pass.
  // TODO(G3): the signature still takes Capability / CapLenInt and the body is
  //           still CHERI's top-based half-open test. Rewrite together with
  //           setCapBounds / getCapBounds / inCapBoundsNoWrap.
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

  let a = unsigned(addr);
  let max_top = 2 ^ xlen;
  match getCapBounds(cap) {
    None() => false,
    Some(base, top) => ((a >= base) & ((a + size) <= min(top,max_top)))
  }
}

// Return true if any byte of the access is within the cap bounds
// Used for certain CBO instructions
function anyByteInCapBounds(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  let a = unsigned(addr);
  match getCapBounds(cap) {
    None() => false,
    Some(base, top) => ((a < top) & ((a + size) > base))
  }
}

// Return true if the range [addr, addr+size) is in the cap bounds.
// The upper bound arithmetic is full-width and isn't wrapped.
function inCapBoundsNoWrap(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  let a = unsigned(addr);
  match getCapBounds(cap) {
    None() => false,
    Some(base, top) => (a >= base) & ((a + size) <= top),
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

function clearTagIf(cap : Capability, cond : bool) -> Capability =
  {cap with tag = cap.tag & not(cond)}

function clearTag(cap : Capability) -> Capability =
  {cap with tag = false}

function legalizeLoadedArchPerms(loaded_cap : Capability, auth_cap : Capability) -> Capability = {
  // If a capability grants R-permission and C-permission, but no LM-permission, then
  // a capability loaded via this authorizing capability will have W-permission and
  // LM-permission removed provided that the loaded capability has its tag set and
  // is not sealed; loaded capabilities that are sealed or untagged do not have
  // their permissions changed.

  // Any unsealed capability with its tag set to 1 that is loaded from memory has
  // its EL-permission cleared ... if the authorizing capability does not grant EL-permission.

  let tagged_and_unsealed = loaded_cap.tag & not(capIsSealed(loaded_cap));
  let clearWLM = tagged_and_unsealed & not(canLM(auth_cap));
  let clearEL = tagged_and_unsealed & not(canEL(auth_cap));

  if clearWLM | clearEL then {
    let perms = getArchPermsLegalized(loaded_cap);
    let perms = { perms with
      W = perms.W & not(clearWLM),
      LM = perms.LM & not(clearWLM),
      EL = perms.EL & not(clearEL),
    };
    setArchPerms(loaded_cap, perms)
  } else loaded_cap
}

function restrictLoadedCL(loaded_cap : Capability, auth_cap : Capability) -> Capability = {
  // Any unsealed capability with its tag set to 1 that is loaded from memory has
  // ... its Capability Level (CL) restricted to the
  // authorizing capability’s Capability Level (CL) if the authorizing capability
  // does not grant EL-permission. If sealed, then only CL is modified ...

  let restrictCL = loaded_cap.tag & not(canEL(auth_cap));
  if restrictCL then {loaded_cap with cl = auth_cap.cl & loaded_cap.cl} else loaded_cap
}

function legalizeSL(stored_cap : Capability, auth_cap : Capability) -> Capability = {
  // When storing a capability, if the authorizing capability does not grant SL-perm
  // and the stored cap has CL == 0 clear the tag of the stored capability,
  // otherwise store the cap data unmodified.
  let cond = not(canSL(auth_cap)) & stored_cap.cl == zeros();
  clearTagIf(stored_cap, cond)
}

// Implementations are allowed to retain invalid capability permissions loaded from memory
// instead of following the ACPERM behaviour of reducing them to no permissions.
let sys_legalize_malformed_permission_on_load = false

function legalizeLoadedPermissions(loaded_cap : Capability, auth_cap : Capability) -> Capability = {
  // CL is not a permission so it is always legalized.
  let loaded_cap = restrictLoadedCL(loaded_cap, auth_cap);

  // Malformed permissions are optionally legalized.
  if not(permsMalformed(loaded_cap)) | sys_legalize_malformed_permission_on_load then {
    legalizeLoadedArchPerms(loaded_cap, auth_cap)
  } else {
    loaded_cap
  }
}

function legalizeStoredPermissions(stored_cap : Capability, auth_cap : Capability) -> Capability = {
  legalizeSL(stored_cap, auth_cap)
}

function capBoundsEqual (c1 : Capability, c2 : Capability) -> bool =
  match (getCapBounds(c1), getCapBounds(c2)) {
    (None(), _) => false,
    (_, None()) => false,
    (Some(base1, top1), Some(base2, top2)) => (base1 == base2) & (top1 == top2)
  }

function setCapAddr(c : Capability, addr : CapAddrBits) -> (bool, Capability) = {
  let newCap = { c with address = addr };
  // capBoundsEqual returns false if either input has malformed bounds, so the
  // representability check will fail if the old or new bounds were malformed.
  let representable = capBoundsEqual(c, newCap);
  (representable, newCap)
}

function setCapAddrChecked(c : Capability, addr : CapAddrBits) -> Capability = {
  let (representable, newCap) = setCapAddr(c, addr);
  clearTagIf(newCap, not(representable) | capIsSealed(c) | not(capReservedValid(c)))
}

infix 1 >>_s
overload operator >> = {sail_shiftright}
overload operator << = {sail_shiftleft}
overload operator >>_s = {sail_arith_shiftright}

function incCapAddrChecked(c : Capability, delta : CapAddrBits) -> Capability =
  setCapAddrChecked(c, c.address + delta)

function capToString(cap : Capability) -> string = {
  let (base_str, top_str, bounds_malformed) : (string, string, bool) = match getCapBoundsBits(cap) {
    None() => ("0 (malformed)", "0 (malformed)", true),
    Some(base, top) => (bits_str(base), bits_str(zero_extend(cap_len_width + 3, top)), false)
  };

  let len_str = bits_str(to_bits_unsafe(cap_len_width + 3, getCapLength(cap)));

  let (arch_perms_str, perms_malformed) : (string, bool) = match getArchPerms(cap) {
    None() => ("(malformed)", true),
    Some(perms) => (
      (if perms.R then "R" else "") ^
      (if perms.W then "W" else "") ^
      (if perms.C then "C" else "") ^
      (if perms.X then "X" else "") ^
      (if perms.LM then "Lm" else "") ^
      (if perms.ASR then "Asr" else "") ^
      (if perms.SL then "Sl" else "") ^
      (if perms.EL then "El" else ""),
      false
    )
  };

  // Warn if non-zero reserved bits encountered
  let (res_str, reserved_malformed) : (string, bool) = if not(capReservedValid(cap)) then
    (" (has non-zero reserved bits)", true)
  else
    ("", false);

  // Print the raw metadata bits if they didn't decode to help debugging
  let raw_str = if bounds_malformed | perms_malformed | reserved_malformed then
    " raw:" ^ bits_str(capToBits(cap))
  else
    "";

  let cheri_mode : string = match getCapMode(cap) {
    CapPtrMode => "CapPtrMode",
    IntPtrMode  => "Integer",
  };

  "t:" ^ (if cap.tag then "1" else "0") ^
  " address:" ^ bits_str(cap.address) ^
  " base:" ^ base_str ^
  " top:" ^ top_str ^
  " length:" ^ len_str ^
  " sealed:" ^ (if cap.sealed then "1" else "0") ^
  " perms:" ^ arch_perms_str ^
  " sdperms:" ^ bits_str(cap.sd_perms) ^
  " level:" ^ bits_str(cap.cl) ^
  " mode:" ^ cheri_mode ^
  raw_str ^ res_str
}

