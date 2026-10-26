/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// Width of capability in bytes (excluding tag).
// TODO: Rename to clen_bytes and clen?
// TODO: Change root xlen to be in terms of the log2 bytes.
type cap_size : Int = xlen_bytes          // TruISA: pointer is 64-bit (CHERI used xlen_bytes * 2)
let  cap_size = sizeof(cap_size)

/* ===== TruISA width switch: the ONLY place to change the VA profile ===== */
type truisa_va        : Int = 48               // Sv48; Sv39 -> 39, Sv57 -> 57
let  truisa_va        = sizeof(truisa_va)
type truisa_pac_width : Int = 57 - truisa_va   // Sv39 -> 18 | Sv48 -> 9 | Sv57 -> 0
let  truisa_pac_width = sizeof(truisa_pac_width)

type cap_addr_width : Int = truisa_va          // was xlen (CHERI); TruISA uses the VA width
let  cap_addr_width = sizeof(cap_addr_width)
type cap_len_width : Int = cap_addr_width + 1
let  cap_len_width = sizeof(cap_len_width)
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
// Tag = the top bits left after address and PAC. Substituting PAC = 57 - VA
// gives 64 - VA - (57 - VA) = 7 for EVERY profile, which is exactly ADR-0003
// rev 12: the tag is bits 63-57 and its width does not vary across profiles.
type CapTagBits   = bits(64 - truisa_va - truisa_pac_width)

// XLEN+1 (33 or 65).
type CapLenBits   = bits(cap_len_width)
type CapLenInt    = range(0, cap_max_len)

// Width of TE and BE fields.
type cap_xe_width : Int = div(cap_E_width, 2)
let  cap_xe_width = sizeof(cap_xe_width)

// Maximum exponent (24 or 52).
// The final exponent is calculated by subtracting a 5 or 6 bit value from
// this, giving a range of 24 .. 0, or 52 .. 0. If the exponent becomes
// negative then it is ignored.
type cap_max_E : Int = cap_addr_width - cap_mantissa_width + 2
let  cap_max_E = sizeof(cap_max_E)

// Negative exponents can be encoded, though these are malformed. We must
// store all of the possible values (even malformed ones) so that CSetHigh works.
type cap_min_E : Int = cap_max_E - (2 ^ cap_E_width - 1)
let  cap_min_E = sizeof(cap_min_E)

type CapExponent = range(cap_min_E, cap_max_E)

// Capability level bits (> 1 is experimental)
type lvlbits : Int = 1
let lvlbits = sizeof(lvlbits)

// Encoding of the EF bit to whether or not it's an internal exponent.
mapping internal_exponent_encdec : bool <-> bits(1) = {
  // Exponent is zero.
  false <-> 0b1,
  // Exponent is internal (stored in L8, TE, BE).
  true <-> 0b0,
}

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
  mode    : bits(1),
  nc      : bits(6),
  pac     : CapPacBits,
  address : CapAddrBits,
}

// Decode compressed capability to a more convenient struct.
function bitsToCap(tag : bool, cap_bits : CapBits) -> Capability = {
  // Decode metadata to fields.
  let meta = dec_EncMetadata(cap_bits[xlen * 2 - 1 .. xlen]);

  let internal_exponent = internal_exponent_encdec(meta.EF);

  // For brevity and to match the spec.
  let 'MW = cap_mantissa_width;

  let E : CapExponent = if internal_exponent then cap_max_E - unsigned(getMetadataInternalExponent(meta)) else 0;

  // When the exponent is non-zero (internal_exponent is true) we implicitly
  // store the leading 1, just as with normal floating point numbers.
  // The case when the exponent is zero is equivalent to subnormals.
  let LMSB = if internal_exponent then 0b01 else 0b0 @ getMetadataL8(meta);

  // `not()` so type infererence for zeros() works.
  let T_low = if not(internal_exponent) then meta.TE else zeros();
  let B_low = if not(internal_exponent) then meta.BE else zeros();

  // Concatenate all the bits. Type annotations are not require but here for sanity checking.
  let T : bits('MW - 2) = meta.Tm @ T_low;
  let B : bits('MW)     = meta.Bm @ B_low;

  let LCout = if T <_u B[MW - 3 .. 0] then 0b01 else 0b00;

  // Prepend the reconstructed top two bits of T.
  let T = (B[MW - 1 .. MW - 2] + LCout + LMSB) @ T;

  struct {
    tag               = tag,
    sd_perms          = meta.SDP,
    ap_m              = meta.AP_M,
    cl                = meta.CL,
    sealed            = bool_bits(meta.CT),
    internal_exponent = internal_exponent,
    E                 = E,
    B                 = B,
    T                 = T,
    reserved_0        = meta.reserved_0,
    reserved_1        = meta.reserved_1,
    address           = cap_bits[xlen - 1 .. 0],
  }
}

// Encode a capability to compressed form. Only the metadata is returned since
// the tag and address are directly available in `cap`.
function capToMetadataBits(cap : Capability) -> bits(xlen) = {
  // Convert the exponent back to encoded form.
  let E = to_bits(cap_E_width, cap_max_E - cap.E);

  // The L8 value here is ignored on RV64.
  let (L8, TE, BE) = if cap.internal_exponent then {
    (
      E[cap_E_width - 1],
      E[cap_xe_width * 2 - 1 .. cap_xe_width],
      E[cap_xe_width - 1 .. 0]
    )
  } else {
    (
      (cap.T - cap.B)[8],
      cap.T[cap_xe_width - 1 .. 0],
      cap.B[cap_xe_width - 1 .. 0]
    )
  };

  let MW = cap_mantissa_width;

  let meta : EncMetadata = struct {
    SDP = cap.sd_perms,
    AP_M = cap.ap_m,
    CL = cap.cl,
    CT = bool_bits(cap.sealed),
    EF = internal_exponent_encdec(cap.internal_exponent),
    Tm = cap.T[MW - 3 .. cap_xe_width],
    Bm = cap.B[MW - 1 .. cap_xe_width],
    TE = TE,
    BE = BE,
    reserved_1 = cap.reserved_1,
    reserved_0 = cap.reserved_0,
    L8 = zeros()
  };
  // Set L8 on RV32. Does nothing on RV64.
  let meta = setMetadataL8(meta, [L8]);
  enc_EncMetadata(meta)
}

// Zero permission capability.
// TODO: We should be able to use bitsToCap(false, zeros()) but there
// seems to be a bug: https://github.com/rems-project/sail/issues/424
let null_cap : Capability = struct {
  tag               = false,
  sd_perms          = zeros(),
  ap_m              = null_ap_m,
  cl                = zeros(),
  sealed            = false,
  internal_exponent = true, // Encodes to 0.
  E                 = cap_max_E, // Encodes to 0.
  B                 = zeros(),
  T                 = 0b01 @ zeros(cap_mantissa_width - 2), // Encodes to 0.
  reserved_0        = zeros(),
  reserved_1        = zeros(),
  address           = zeros(),
}

// Full permission capability.
let infinite_cap : Capability = {
  null_cap with
  tag      = true,
  sd_perms = ones(),
  cl       = ones(),
  ap_m     = infinite_ap_m,
}

// A capability is malformed if its encoding does not describe a valid capability
// because its bounds cannot be correctly decoded.
function boundsMalformed(cap : Capability) -> bool = {
  cap.internal_exponent & ({
    let MW = cap_mantissa_width;

    let malformedMSB = (cap.E == cap_max_E     & cap.B         != zeros(MW)) |
                       (cap.E == cap_max_E - 1 & cap.B[MW - 1] != bitzero);
    let malformedLSB = cap.E < 0 | (cap_use_L8 & cap.E == 0);
    malformedMSB | malformedLSB
  })
}

// Get the full cap bounds (base and top) as bit vectors.
/* ===== TruISA helpers: pointer form decoding (ADR-0003 rev 8) ===== */

// The tag: the top CapTagBits (63-57) of a pointer. Every form decision hangs
// off this value. Named "Bits" to match the blueprint's getCapBoundsBits.
val  getCapTagBits : xlenbits -> CapTagBits
function getCapTagBits(p : xlenbits) -> CapTagBits =
  p[63 .. truisa_pac_width + truisa_va]

// Slot base of an aligned-slot pointer: SlotBase = p & ~(2^N - 1)
// (docs/isa/04; ADR-0010 decision 4). Operates inside the address field only.
val  getCapSlotBase : (CapAddrBits, bits(6)) -> CapAddrBits
function getCapSlotBase(p : CapAddrBits, n : bits(6)) -> CapAddrBits =
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
val  getCapCentroID : (CapAddrBits, bits(6)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(6)) -> CapAddrBits = {
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
val  getCapBoundsBits : xlenbits -> option((xlenbits, xlenbits))
function getCapBoundsBits(p : xlenbits) -> option((xlenbits, xlenbits)) = {
  let tag7 : CapTagBits = getCapTagBits(p);
  let low_mask : xlenbits = zero_extend(ones(truisa_va - 1));   // 2^(VA-1) - 1

  if      tag7 == 0b0000000 then Some(zeros(), low_mask)              // Bare, low half
  else if tag7 == 0b1111111 then Some(~low_mask, ones(64))            // Bare, high half
  else if tag7 == 0b0111111 then None()                               // poisoned
  else if p[63] == 0b1 then {                                         // Aligned
    let n : bits(6) = p[62 .. 57];
    if unsigned(n) >= truisa_va then None()                           // N must be in 0..VA-1 (ADR-0005 dec 6)
    else {
      let base : CapAddrBits = getCapSlotBase(p[47 .. 0], n);
      let mask : CapAddrBits = zero_extend(ones(unsigned(n)));
      Some(sign_extend(base), sign_extend(base | mask))
    }
  }
  else None()                                                         // CentroID
}

// Utility to get the cap bounds (base and top) as integers.
function getCapBounds(cap : Capability) -> option((CapAddrInt, CapLenInt)) =
  match getCapBoundsBits(cap) {
    None()          => None(),
    Some(base, top) => Some(unsigned(base), unsigned(top))
  }

/* An 'ideal' version of setCapBounds as described in paper. */
function setCapBounds(cap : Capability, base : CapAddrBits, top : CapLenBits) -> (bool, Capability) = {
  /* {cap with base=base; length=(bits(64)) length; offset=0} */
  let ext_base = 0b0 @ base;
  let length = top - ext_base;
  /* Find an exponent that will put the most significant bit of length
   * second from the top as assumed during decoding. We ignore the bottom
   * MW bits because those are handled by the ie = 0 format.
   */
  let e = cap_max_E - count_leading_zeros(length[cap_addr_width..cap_mantissa_width - 1]);
  // Use use internal exponent if e is non-zero or if e is zero but
  // the implied bit of length is not zero (denormal vs. normal case)
  let ie = (e != 0) | (not(cap_use_L8) & length[cap_mantissa_width - 2] == bitone);

  /* The non-ie e == 0 case is easy. It is exact so just extract relevant bits. */
  var Bbits = truncate(base, cap_mantissa_width);
  var Tbits = truncate(top, cap_mantissa_width);
  var lostSignificantTop : bool = false;
  var lostSignificantBase : bool = false;
  var incE : bool = false;

  if ie then {
    /* the internal exponent case is trickier */

    /* Extract B and T bits (we lose 2 or 3 bits of each to store the exponent) */
    var B_ie = truncate(base >> (e + cap_xe_width), cap_mantissa_width - cap_xe_width);
    var T_ie = truncate(top >> (e + cap_xe_width), cap_mantissa_width - cap_xe_width);

    /* Find out whether we have lost significant bits of base and top using a
     * mask of bits that we will lose (including 2 or 3 extra for exp).
     */
    let maskLo : CapLenBits = zero_extend(ones(e + cap_xe_width));
    lostSignificantBase = (ext_base & maskLo) != zeros();
    lostSignificantTop  = (top & maskLo) != zeros();

    if lostSignificantTop then {
      /* we must increment T to make sure it is still above top even with lost bits.
         It might wrap around but if that makes B<T then decoding will compensate. */
      T_ie = T_ie + 1;
    };

    /* Has the length overflowed? We chose e so that the top two bits of len would be 0b01,
       but either because of incrementing T or losing bits of base it might have grown. */
    let len_ie = T_ie - B_ie;
    if len_ie[cap_mantissa_width - (cap_xe_width + 1)] == bitone then {
      /* length overflow -- increment E by one and then recalculate
         T, B etc accordingly */
      incE = true;

      lostSignificantBase = lostSignificantBase | B_ie[0] == bitone;
      lostSignificantTop  = lostSignificantTop  | T_ie[0] == bitone;

      B_ie = truncate(base >> (e + cap_xe_width + 1), cap_mantissa_width - cap_xe_width);
      let incT : range(0,1) = if lostSignificantTop then 1 else 0;
      T_ie = truncate(top >> (e + cap_xe_width + 1), cap_mantissa_width - cap_xe_width) + incT;
    };

    Bbits = B_ie @ zeros(cap_xe_width);
    Tbits = T_ie @ zeros(cap_xe_width);
  };

  let newCap = {
    cap with
    address=base,
    E=if incE then {
      // TODO: E can overflow here. The previous code silently wrapped so I've
      // copied that but I'm not sure it's correct.
      if e + 1 <= cap_max_E then e + 1 else cap_min_E
    } else e,
    B=Bbits,
    T=Tbits,
    internal_exponent=ie
  };
  let exact = not(lostSignificantBase | lostSignificantTop);
  (exact, newCap)
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

function getCapLength(c : Capability) -> CapLenInt =
  match getCapBounds(c) {
    None() => 0,
    Some(base, top) => {assert(top >= base); top - base},
  }

// Return true if the given decoded bounds cover the entire address space.
// Microarchitecturally, this should be the same as checking if the exponent
// is max_exp.
function decodedBoundsInfinite(base : CapAddrInt, top : CapLenInt) -> bool =
  (base == 0) & (top >= 2 ^ xlen)

// Return true if the given capability has infinite bounds, meaning
// it can access any byte of the address space.
function capBoundsInfinite(c: Capability) -> bool =
  match getCapBounds(c) {
    None() => false,
    Some(base, top) => decodedBoundsInfinite(base, top),
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
  // size > 2^VA  : `addr + size - 1` wraps in 64 bits (addr = 0 with
  //                size = 2^48 + 1 yields 2^48); an unsigned comparison would
  //                wrongly pass.
  // TODO(G3): the signature still takes Capability / CapLenInt and the body is
  //           still CHERI's top-based half-open test. Rewrite together with
  //           setCapBounds / getCapBounds / inCapBoundsNoWrap.
  if size == 0 then return false;
  if size > (2 ^ truisa_va) then return false;

  let a = unsigned(addr);
  let max_top = 2 ^ xlen;
  match getCapBounds(cap) {
    None() => false,
    Some(base, top) => ((a >= base) & ((a + size) <= min(top,max_top))) | decodedBoundsInfinite(base, top)
  }
}

// Return true if any byte of the access is within the cap bounds
// Used for certain CBO instructions
function anyByteInCapBounds(cap : Capability, addr : CapAddrBits, size : CapLenInt) -> bool = {
  let a = unsigned(addr);
  match getCapBounds(cap) {
    None() => false,
    Some(base, top) => ((a < top) & ((a + size) > base)) | decodedBoundsInfinite(base, top)
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
    " raw:" ^ bits_str(capToMetadataBits(cap))
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

function getRepresentableAlignmentMask(len : xlenbits) -> xlenbits = {
  let (_exact, c) = setCapBounds(infinite_cap, zeros(), 0b0 @ len);
  if c.internal_exponent then {
    // setCapBounds will never make a malformed cap with E < 0.
    let e = c.E;
    assert(e >= 0);
    ~(zero_extend(ones(e + cap_xe_width)))
  } else ones()
}

function getRepresentableLength(len : xlenbits) -> xlenbits = {
  let m = getRepresentableAlignmentMask(len);
  (len + ~(m)) & m
}
