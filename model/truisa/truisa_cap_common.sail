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

/* ------------------------------------------------------------------------------------
 * Width block. Everything below derives from TWO target constants; nothing else is
 * written down twice.
 *
 * // TRUISA DELTA vs cheri_cap_common.sail:10-26: the blueprint writes cap_size from
 * // xlen_bytes and cap_addr_width from xlen, so its widths are functions of the config
 * // variable. TruISA cannot do that. Two reasons, both measured on this model:
 * //
 * //   1. `xlen` is a CONFIG variable. Any constant that reaches it cannot be folded at
 * //      type-check time, and bits() then rejects it. (D-96; the evidence is the
 * //      correction in D-94 -- `bits(xlen - 55)` reports "recursive types are
 * //      forbidden", which is Sail's generic wording for "I could not evaluate this
 * //      width".)
 * //   2. Sail folds multiplication and 2^ well but NOT division and log2 --
 * //      riscv_xlen.sail:11-12 says so in as many words. That is the real reason the
 * //      blueprint detours through log2_cap_size instead of computing a width directly.
 * //
 * // So the parameterising base is truisa_ptr_width, a literal, and a constraint ties it
 * // to xlen. Writing 64 here while configuring an RV32 build is then a compile error
 * // rather than a silent mismatch of the kind two independent constants allow.
 * ---------------------------------------------------------------------------------- */

/* Target constant 1: the pointer width. Change this ONE line for RV32. */
type truisa_ptr_width : Int = 64
let  truisa_ptr_width = sizeof(truisa_ptr_width)

/* ⭐ The seam that makes the constant above safe. It turns "this file says 64 but the
 * build is rv32" into a type error at configure time. Without it the literal would be
 * an unchecked duplicate of the config value.
 * TRUISA DELTA: the blueprint has no such constraint; it never writes a width down. */
constraint truisa_ptr_width == xlen

/* Bits 63-57: one mode bit plus six bits of N/C. */
type truisa_mode_width : Int = 1
let  truisa_mode_width = sizeof(truisa_mode_width)

/* N/C must be able to name any bit position of the pointer, so its width is log2 of the
 * pointer width: 6 for 64 bits, 5 for 32. Written as a conditional on a LITERAL rather
 * than as log2(truisa_ptr_width) because Sail does not fold log2 (see above).
 * TRUISA DELTA: the blueprint hard-codes 6 with no explanation of where it comes from. */
type truisa_nc_width : Int = if truisa_ptr_width == 64 then 6 else 5
let  truisa_nc_width = sizeof(truisa_nc_width)

/* Target constant 2: the address field width, set by the VA profile (ADR-0003):
 * Sv39 -> 39, Sv48 -> 48, Sv57 -> 57. Change this ONE line to switch profile. */
type truisa_address_width : Int = 48
let  truisa_address_width = sizeof(truisa_address_width)

/* Everything left between the label and the address. Sv48 -> 64-48-1-6 = 9. */
type truisa_pac_width : Int =
  truisa_ptr_width - truisa_address_width - truisa_mode_width - truisa_nc_width
let  truisa_pac_width = sizeof(truisa_pac_width)

/* Size of the capability in bytes: 8 for a 64-bit pointer, 4 for a 32-bit one.
 *
 * // TRUISA DELTA: `if truisa_ptr_width == 64 then 8 else 4`, not `2 ^ log2_cap_size`
 * // as D-94 first proposed. That form had to be corrected (D-96) because
 * // log2_cap_size is selected with `if xlen ...` in truisa_prelude_xlen.sail, so it
 * // reaches the config variable and cannot be folded here. The parameterisation
 * // survives -- it now depends on truisa_ptr_width, which is a literal -- but the
 * // single-source-of-truth route through log2_cap_size is closed on this path.
 * // ⛔ Do not add a second constant alongside this expression.
 * ---------------------------------------------------------------------------------- */
type cap_size : Int = if truisa_ptr_width == 64 then 8 else 4
let  cap_size = sizeof(cap_size)


/*=======================================================================================*/
/*  1a -- the capability itself, and the operators that only READ it.                     */
/*                                                                                       */
/*  CR-MAC-01 Rev.1 items 1a-1 .. 1a-8. No MAC, no signing, no table: 1b owns those.      */
/*=======================================================================================*/

/* ------------------------------------------------------------------------------------
 * Type names. Kept at the blueprint's spelling (cheri_cap_common.sail:26/29) so the two
 * files can be read side by side; the WIDTHS are TruISA's, which is the whole point.
 *
 * // TRUISA DELTA: CapBits is bits(8 * cap_size) = 64, not bits(8 * cap_size) = 128.
 * // Same expression, different cap_size (truisa_prelude_64.sail). cap_size finally has
 * // a consumer here -- D-96 recorded it as defined-but-unused, which was only true
 * // while nothing read it.
 * ---------------------------------------------------------------------------------- */
type CapBits    = bits(8 * cap_size)
type CapAddrBits = bits(truisa_address_width)
type CapTagBits  = bits(truisa_mode_width + truisa_nc_width)

/* ------------------------------------------------------------------------------------
 * ADR-0029 decision 1. The REGISTER representation is now wider than the memory
 * encoding: `address` is a full machine word (truisa_ptr_width = 64), so the struct is
 * 80 bits while CapBits above stays 64. Three derived widths, none of them a new
 * decision:
 *
 *   truisa_meta_width      = 64 - 48 = 16    mode + nc + pac, i.e. everything but address
 *   truisa_cap_repr_width  = 64 + 16 = 80    bookkeeping only (never enters a bits())
 *   CapMetaBits            = bits(16)        return type of capToMetadataBits
 *
 * // TRUISA DELTA: the blueprint needs no such split -- its 128-bit capability is one
 * // contiguous encoding, so capToBits is a function there. At 80 -> 64 it is not (no
 * // injection), which is exactly why capToMetadataBits replaces it below.
 * //
 * // ⛔ Do NOT restate truisa_pac_width (:61) in terms of truisa_meta_width. That one
 * // means "everything left over after mode+nc+address" (9); this one means "everything
 * // except address" (16). Same-looking subtractions, different meanings.
 * ---------------------------------------------------------------------------------- */
type truisa_meta_width : Int = truisa_ptr_width - truisa_address_width
let  truisa_meta_width = sizeof(truisa_meta_width)

/* Bookkeeping only: 80. ⛔ Never used inside bits() -- CapBits stays bits(64). */
type truisa_cap_repr_width : Int = truisa_ptr_width + truisa_meta_width
let  truisa_cap_repr_width = sizeof(truisa_cap_repr_width)

type CapMetaBits = bits(truisa_meta_width)

/* ------------------------------------------------------------------------------------
 * 1a-1. The capability.
 *
 * Two views, and they are NOT the same width (ADR-0029 decision 1). Keep both in mind:
 *
 * MEMORY ENCODING -- CapBits, 64 bits, unchanged (this is what SCEQ compares and what
 * the load/store path moves):
 *
 * 63            62      57 56        48 47                                    0
 * +---------------+--------+-----------+---------------------------------------+
 * | mode (1)      | N/C (6)| PAC (9)   | address (48)                          |
 * +---------------+--------+-----------+---------------------------------------+
 *
 * REGISTER REPRESENTATION -- the struct, 80 bits (truisa_cap_repr_width):
 *
 * 79      73 72      64 63                                                 0
 * +---------+----------+----------------------------------------------------+
 * | mode+NC | PAC (9)  | address (64)                                       |
 * +---------+----------+----------------------------------------------------+
 *
 * ⚠️ `address[63:48]` is REDUNDANT in the register: it is dropped when encoding, so two
 * structs differing only there are the same pointer (ADR-0029 invariant I2). bitsToCap
 * therefore fills it by sign extension, which makes encode . decode = id on canonical
 * values; a value written by wX need not be canonical (invariant I1).
 *
 * // TRUISA DELTA vs cheri_cap_common.sail:69: the blueprint has twelve fields (tag,
 * // sd_perms, ap_m, cl, sealed, internal_exponent, E, B, T, reserved_0/1, address)
 * // because a CHERI capability carries its own bounds and permissions. TruISA's does
 * // not -- bounds live in the descriptor table, there are no permission bits, nothing
 * // is sealed (ADR-0001, ADR-0011) -- so four fields are the whole struct.
 * //
 * // Every field width is a NAMED CONSTANT, never a literal: an RV32 target changes two
 * // constants and this layout follows (D-96).
 * ---------------------------------------------------------------------------------- */
struct Capability = {
  mode    : bits(truisa_mode_width),
  nc      : bits(truisa_nc_width),
  pac     : bits(truisa_pac_width),
  address : bits(truisa_ptr_width),
}

/* The canonical poison value: tag = 0111111 (mode 0, N/C 63), everything else zero.
 * docs/isa/03 section 3.6: writing this code IS what poisoning means; it is not the
 * CHERI behaviour of clearing a tag bit. */
let truisa_poison_cap : Capability = struct {
  mode    = 0b0,
  nc      = 0b111111,
  pac     = zeros(),
  address = zeros(),
}

/* ------------------------------------------------------------------------------------
 * 1a-2 / 1a-3. Disassemble and assemble the memory encoding.
 *
 * ⛔ There is no `capToBits` any more (ADR-0029 decision 3). With `address` at 64 bits,
 * `mode @ nc @ pac @ address` is 80 bits and cannot return CapBits (64): 80 -> 64 has
 * no injection, so `capToBits` is not a function. Encoding is assembled AT THE USE SITE
 * instead -- `capToMetadataBits(cap) @ cap.address[truisa_address_width - 1 .. 0]` --
 * which is the shape the blueprint uses too (cheri_insts.sail:211). ⛔ Do not rescue it
 * with `truncate`: that breaks encode . decode = id.
 *
 * What survives is the metadata half. Every instruction that reads a field still goes
 * through one of these two rather than slicing the struct twice (bit-position drift is
 * the failure mode this prevents -- the same reason getCapTagBits exists).
 * ---------------------------------------------------------------------------------- */
val  capToMetadataBits : Capability -> CapMetaBits
function capToMetadataBits(cap : Capability) -> CapMetaBits =
  cap.mode @ cap.nc @ cap.pac

/* encode . decode = id, **only on canonical capabilities** (address[63:VA] == bit(VA-1),
 * ADR-0029 invariant I1). A bare integer written by wX is not canonical and does not
 * satisfy it; that is by design, not a defect (decision 6).
 *
 * `tag` is a DEAD parameter, kept for signature parity with cheri_cap_common.sail:99
 * (ADR-0029 decision 4). TruISA has no tag bit (ADR-0003). ⛔ Do not rename it `_tag`. */
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

/* ------------------------------------------------------------------------------------
 * 1a-5. Which of the five forms the label denotes.
 *
 * docs/isa/03 section 3.3 gives a TWO-STEP test, and the order is not negotiable:
 *
 *   1. label 0000000 -> Bare (the bit(VA-1)=0 side)
 *      label 1111111 -> Bare (the bit(VA-1)=1 side)
 *   2. label 0111111 -> the ONLY poison code          (ADR-0003)
 *   3. otherwise look at bit 63: 1 = Aligned, 0 = Descriptor
 *
 * Why 0000000 must be tested BEFORE the descriptor branch: a descriptor with C = 0
 * encodes to 0000000, so testing bit 63 first would report a bare pointer as a
 * descriptor. (Descriptor C is 1..VA-1 for exactly this reason.)
 *
 * Why 1111111 is Bare and not poison: N/C = 63 with mode = 1 is the canonic address on
 * the high side of bit(VA-1), which is a legal bare pointer under the Sv39/Sv48 sign
 * extension rule. Only 0111111 was set aside as the poison code, and that choice is
 * what makes "poisoned" distinguishable from "bare" at all.
 *
 * ⚠️ FORM IS NECESSARY, NOT SUFFICIENT, FOR BARE. A full bare test also requires
 * bits 63..VA to match the sign of bit(VA-1) (docs/isa/03 section 3.5). This function
 * classifies the label only; the per-instruction criteria still have to run.
 *
 * Code points N/C in VA+1..62 are reported Invalid rather than given their own form --
 * docs/isa/03 line 286 states the two kinds of "illegal" have per-instruction
 * consequences, so classifying is all this function may do.
 *
 * // TRUISA DELTA vs the blueprint: CHERI's getCapMode splits on the tag bit and then
 * // checks reserved encodings; there is no five-way form there, because a CHERI
 * // capability has one shape. The five-way split is TruISA's (ADR-0003).
 * ---------------------------------------------------------------------------------- */
val  getCapForm : Capability -> CapPtrForm
function getCapForm(cap : Capability) -> CapPtrForm = {
  let tag = getCapTagBits(cap);
  let n : int = unsigned(cap.nc);
  if tag == ones() then FormBare
  else if tag == zeros() then FormBare
  else if tag == 0b0111111 then FormPoisoned
  else if cap.mode == 0b1 then
    (if n <= truisa_address_width then FormAligned else FormInvalid)
  else
    (if n >= 1 & n <= truisa_address_width - 1 then FormDescriptor else FormInvalid)
}

/* ------------------------------------------------------------------------------------
 * 1a-6. Slot base: S = p with the low N bits cleared, i.e. (p >> N) << N.
 *
 * ⚠️ Written as a shift PAIR, not as p & ~(2^N - 1). The mask form needs
 * zero_extend(ones(unsigned(n))) narrowed to CapAddrBits, and Sail has no width for the
 * complement until ~ resolves -- '~' is boolean negation in Sail, not bitwise. The
 * shift pair keeps the operand at CapAddrBits and takes an int shift amount, which is
 * the same shape the blueprint uses for a_mid. (This was hit for real at cc44e63.)
 * ---------------------------------------------------------------------------------- */
val  getCapSlotBase : (CapAddrBits, bits(truisa_nc_width)) -> CapAddrBits
function getCapSlotBase(p : CapAddrBits, n : bits(truisa_nc_width)) -> CapAddrBits =
  (p >> unsigned(n)) << unsigned(n)

/* ------------------------------------------------------------------------------------
 * 1a-7. CentroID canonical representative point: m = S + 2^(N-1).
 *
 * CentroID is formally a PAIR (left = m - 1, right = m) per ADR-0004; the right point is
 * canonical, so one address carries all of (N, S). NOTE: this returns an ADDRESS, not a
 * key -- the descriptor table is keyed by (C, S), never by m (ADR-0004).
 *
 * The two ends of the range, and they are NOT the same kind of thing (D-108):
 *
 *   - N = 0: ONE-BYTE slot. spec/ch04:239-244 defines m = S + (K == 0 ? 0 : 2^(K-1)),
 *     i.e. m = S -- "the slot's midline is its only address". This is a DEFINITION,
 *     not a fallback. ⚠️ So m = 0 is reachable here: a one-byte slot at address 0
 *     returns 0, and that is a legal value, not a reserved one.
 *   - N = VA: whole-space slot. ADR-0026 RULES m = 0 (S = 0 and no object can own the
 *     midline of the entire space). This one really is "ruled to be 0".
 *
 * ⛔ Do NOT call 0 a "reserved value" without naming which case. The earlier text said
 * "both return the reserved value 0" and that word hid a gap inside a definition: the
 * N = VA zero is a RULING (ADR-0026), the N = 0 zero was the model saying "cannot
 * compute a midline". D-108 withdrew the shared term for exactly this reason.
 *
 * ⚠️ ⛔ This is why "1B does not enter the table" (ADR-0006) must stay a HARD
 * precondition, not a convenience: with m = S here, an entry keyed on m = 0 would
 * collide with address 0. The two conclusions are a matched pair -- relax either and
 * the other breaks. (ADR-0006 is a TABLE-side statement; it does not define m.)
 *
 * ⚠️ 2^(N-1) is computed as (1 << N) >> 1 in a 64-bit intermediate: (1 << (N-1)) would
 * need a proof that N >= 1, which Sail cannot get out of the compared-equal branch, and
 * shift amounts must not be negative anyway. Same trick as getCapSlotBase.
 * ---------------------------------------------------------------------------------- */
val  getCapCentroID : (CapAddrBits, bits(truisa_nc_width)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(truisa_nc_width)) -> CapAddrBits = {
  // ⚠️ k must be nat, not int. Written as int (unsigned(n) coerced) Sail cannot prove
  // `k >= 0` and rejects the shift with "Could not resolve quantifiers for shiftl".
  // getCapSlotBase gets away with it only because it inlines unsigned(n) at the shift,
  // where the non-negativity is still visible.
  let k : nat = unsigned(n);
  let base : CapAddrBits = getCapSlotBase(p, n);
  if k == 0 then base
  else if k == truisa_address_width then zeros()
  else {
    let twop : bits(64) = 0x0000_0000_0000_0001 << k;
    // ⚠️ truncate takes TWO arguments in Sail: the value and the target width
    // (bitvector('n), int('m)). One-argument form fails to resolve.
    let half : CapAddrBits = truncate(twop >> 1, truisa_address_width);
    base + half
  }
}

/* ------------------------------------------------------------------------------------
 * 1a-8. poisonIf -- the single failure exit of every PTR-producing instruction.
 *
 * Sail is NOT lazy: `poisonIf(sign(cap), fail)` evaluates sign() even on the failure
 * path and pays for a MAC that is then thrown away. Callers must write
 * `if fail then poison else sign` instead (D-99 V-5).
 *
 * // TRUISA DELTA vs cheri_cap_common.sail:537 clearTagIf: CHERI clears one tag bit and
 * // the value stays otherwise intact; TruISA overwrites the whole label with the poison
 * // code. Copying the blueprint's body would compile and be semantically wrong -- and
 * // the shape tests cannot catch it, because the poison path is tested by call COUNT,
 * // not by value.
 * ---------------------------------------------------------------------------------- */
val  poisonIf : (Capability, bool) -> Capability
function poisonIf(cap : Capability, cond : bool) -> Capability =
  if cond then truisa_poison_cap else cap

/* ====================================================================================
 * 1b. The authentication segment: stub key, folding XOR, sign/verify, and the two
 * producers that need a signature (makeCapAligned, setCapBounds).
 *
 * Everything below is new in this model (CR-MAC-01 Rev.1 section 1b). Nothing above is
 * modified: the 1a operators are CALLED, never re-sliced -- that is what keeps the bit
 * positions in one place.
 * ==================================================================================== */

/* ------------------------------------------------------------------------------------
 * 1b-1. The key stub.
 *
 * spec/ch04 line 312: xpkey is 128 bits (xpkey1 || xpkey0), and xpkey == 0 is a
 * RESERVED value meaning "uninitialised" -- with it every tagged-pointer verification
 * fails. So the stub must be NON-ZERO, otherwise the model would behave like a machine
 * that has just been reset and rejects everything.
 *
 * ⚠️ Placeholder for the xpkey CSR, which does not exist yet. When it lands, delete this
 * constant and read the CSR instead: the key is already a parameter of truisaMac, so
 * only the two call sites below change.
 * ---------------------------------------------------------------------------------- */
let truisa_xpkey_stub : bits(128) =
  0x0123_4567_89AB_CDEF_0123_4567_89AB_CDEF

/* ------------------------------------------------------------------------------------
 * 1b-2. foldXor -- the stub's mixing primitive.
 *
 * spec/ch04 line 314 pins the OUTPUT rule: the MAC produces >= PAC_W bits and the
 * hardware takes the LOW PAC_W. "Low" and "high" are different functions, so this is
 * spelled out rather than left to an implicit truncate().
 *
 * // TRUISA DELTA vs a real MAC: spec/ch04 line 337 forbids a non-cryptographic hash
 * // (plain XOR, additive mixing, unkeyed-hash-then-XOR-key) as the ARCHITECTURE's MAC.
 * // This is plain XOR and it is a STUB -- D-99 V-2 accepted it precisely on condition
 * // that truisaMac keeps its `val` line, so the body can be replaced without touching a
 * // caller. It must never be cited as the strength argument of spec/ch04 line 327-337.
 *
 * Fold shape for Sv48 (PAC_W = 9) over 128 bits: fourteen full 9-bit slices covering
 * bits 125..0, plus a 2-bit tail at bits 127..126 zero-extended to 9. The tail is an
 * explicit concatenation because zero_extend takes its width from context, and the
 * context is exactly what this function is establishing.
 * ---------------------------------------------------------------------------------- */
val  foldXor : (bits(128), int) -> bits(truisa_pac_width)
function foldXor(x : bits(128), w : int) -> bits(truisa_pac_width) = {
  assert(w == truisa_pac_width);
  // The slice list below assumes PAC_W == 9 over 128 bits. Sv39 (17) and Sv57 (0) need a
  // different list, so fail loudly here rather than fold the wrong bits silently.
  assert(truisa_pac_width == 9);
  x[8 .. 0]       ^ x[17 .. 9]     ^ x[26 .. 18]   ^ x[35 .. 27]
  ^ x[44 .. 36]   ^ x[53 .. 45]    ^ x[62 .. 54]   ^ x[71 .. 63]
  ^ x[80 .. 72]   ^ x[89 .. 81]    ^ x[98 .. 90]   ^ x[107 .. 99]
  ^ x[116 .. 108] ^ x[125 .. 117]
  ^ (0b0000000 @ x[127 .. 126])
}

/* ------------------------------------------------------------------------------------
 * 1b-3. truisaMac -- the interface the architecture fixes.
 *
 * spec/ch04 line 313: the input is hi7 || m || salt = 7 + 48 + 32 = 87 bits, FIXED
 * length, no separators. The fixed length is the point of the section -- a
 * variable-length encoding would let two different inputs share one encoding.
 *
 * The `val` line stays even though a body follows it. D-99 V-2: that declaration is
 * what allows a future C-side implementation to replace the body without editing any
 * call site.
 *
 * // TRUISA DELTA vs cheri_cap_common.sail: the blueprint has no MAC at all. CHERI's
 * // tag bit is STORED, not signed. TruISA has no tag bit to store -- the label lives
 * // inside the pointer value -- so authenticity has to be computed and checked. This
 * // function is that computation; there is no counterpart to port.
 * ---------------------------------------------------------------------------------- */
val  truisaMac : (bits(128), bits(87)) -> bits(truisa_pac_width)
function truisaMac(key : bits(128), msg : bits(87)) -> bits(truisa_pac_width) =
  foldXor(key, truisa_pac_width)
  ^ foldXor((zeros() : bits(41)) @ msg, truisa_pac_width)

/* ------------------------------------------------------------------------------------
 * 1b-4. The PAC slice, and the salt type it is signed over.
 *
 * The PAC sits at bits 56..48 for Sv48. Written as VA + PAC_W - 1 .. VA, never as
 * 56..48: the slice has to follow the profile (ADR-0003), and hard-coded bit positions
 * are exactly what made the D-94/D-96 line numbers drift twice.
 * ---------------------------------------------------------------------------------- */
type CapPacBits = bits(truisa_pac_width)

val  getCapPac : Capability -> CapPacBits
function getCapPac(cap : Capability) -> CapPacBits =
  capToMetadataBits(cap)[truisa_pac_width - 1 .. 0]

/* salt is 32 bits (spec/ch04 line 183). Descriptor mode reads it from the table entry;
 * aligned-slot mode uses all zeros (ADR-0005 rev 11 item 3). ⚠️ The segment is NOT
 * omitted in the aligned case even though it is zero -- omitting it would change the
 * 87-bit length that makes the encoding unambiguous (spec/ch04 line 313). */
type cap_salt = bits(32)

/* ------------------------------------------------------------------------------------
 * 1b-5. signPtr -- the single signing operator (spec/ch04 line 233-242).
 *
 * spec/ch04 line 242: sign() is called ONLY at PTR production points. Instructions
 * never inline the formula; they call this or makeCapAligned.
 *
 * S and m come from 1a-6 and 1a-7. They are NOT recomputed here: the whole reason those
 * two exist is that the slice arithmetic has to live in one place.
 *
 * ⚠️ N = 0 (one-byte slot) -- RESOLVED by D-108, ruling 甲:
 *     spec/ch04:239 writes m = S + (K == 0 ? 0 : 2^(K-1)), i.e. m = S for a one-byte
 *     slot, and :244 says so in words ("the slot's midline is its only address").
 *     This model used to return 0 there (1a-7 as first written); it now returns S, so
 *     the MAC input matches what spec-derived hardware computes.
 *   ⚠️ Consequence to keep in view: m = 0 is now REACHABLE (a one-byte slot at address
 *   0). "1B does not enter the table" (ADR-0006) is what keeps that harmless -- it is a
 *   hard precondition, not an optimisation (see 1a-7).
 *   ⚠️ N = VA still returns 0, but that one is an ADR-0026 RULING, not a gap.
 * ---------------------------------------------------------------------------------- */
val  signPtr : (Capability, cap_salt) -> Capability
function signPtr(cap : Capability, salt : cap_salt) -> Capability = {
  let hi7 = getCapTagBits(cap);
  /* Slices [VA-1..0]: getCapCentroID's first parameter is CapAddrBits (48), not the
   * 64-bit struct field. The redundant high bits are not part of the address. */
  let m   = getCapCentroID(cap.address[truisa_address_width - 1 .. 0], cap.nc);
  let msg : bits(87) = hi7 @ m @ salt;
  struct {
    mode    = cap.mode,
    nc      = cap.nc,
    pac     = truisaMac(truisa_xpkey_stub, msg),
    address = cap.address,
  }
}

/* ------------------------------------------------------------------------------------
 * 1b-6. verifyPtr -- recompute and compare (D-99).
 *
 * Signing is idempotent on the fields that matter (mode, nc, address are copied
 * through), so signing a signed pointer reproduces its own PAC. That is what makes
 * "compare against signPtr(cap)" a valid test rather than a tautology: flipping any bit
 * of nc, or of the address, changes the MAC input and the comparison fails.
 * ---------------------------------------------------------------------------------- */
val  verifyPtr : (Capability, cap_salt) -> bool
function verifyPtr(cap : Capability, salt : cap_salt) -> bool =
  getCapPac(cap) == getCapPac(signPtr(cap, salt))

/* ------------------------------------------------------------------------------------
 * 1b-6b. keySalt -- THE ONLY place a salt is obtained (D-220).
 *
 * ⛔ No call site passes a salt literal. Every `signPtr` / `verifyPtr` second argument
 * must be `keySalt(...)`, and this is enforced by reading the call sites, not by trust:
 * while the literal sat in a shared `else` branch, that branch carried no form
 * information, so "is the descriptor side wired up?" could not be grepped at all (D-220
 * section 4.2 -- an ungrepable criterion is not a criterion).
 *
 * ⭐ Two paths, one exit (spec/ch04 "authentication code", ADR-0005 revision 11 item 3):
 *   - aligned: the salt is all-zero BY SPEC and permanently so -- an aligned slot has no
 *     table entry, hence no salt and no refresh moment. It does NOT become non-zero when
 *     the descriptor table lands.
 *   - descriptor: the salt carried by the table entry. ⚠️ Deliberately not written yet:
 *     nothing in phase A produces that form (CapPtrForm in truisa_types.sail), so the arm
 *     is unreachable, and writing it now would need either a second zeros() or a stub
 *     that lies about having an entry. Phase B rewrites THIS function only, and must
 *     leave the aligned arm byte-for-byte unchanged (D-220 section 4.2 criterion 3).
 *
 * ⛔ Do not change cap_salt's type or width as part of wiring this up: this function
 * swaps where the value comes from, not what it is (D-220 section 4.3).
 * ---------------------------------------------------------------------------------- */
val  keySalt : Capability -> cap_salt
function keySalt(cap : Capability) -> cap_salt = zeros()

/* ------------------------------------------------------------------------------------
 * 1b-7. makeCapAligned -- build an aligned-slot pointer and sign it.
 *
 * ⭐⭐ The body MUST be `if fail then poison else sign`. Sail evaluates arguments before
 * a call, so `poisonIf(signPtr(q, keySalt(q)), fail)` -- which type-checks and looks
 * equivalent -- computes a MAC on the failure path and throws it away. D-99 V-5 made
 * this a call-COUNT test (CR-TEST-01 T-10) precisely because the value is identical
 * either way and no shape test can see the difference.
 *
 * Aligned-slot salt is zeros (ADR-0005 rev 11 item 3): there is no table entry, so
 * there is no salt and no refresh moment.
 * ---------------------------------------------------------------------------------- */
val  makeCapAligned : (Capability, bits(truisa_nc_width), bool) -> Capability
function makeCapAligned(parent : Capability, n : bits(truisa_nc_width), fail : bool)
    -> Capability =
  if fail then truisa_poison_cap
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

/* ------------------------------------------------------------------------------------
 * 1b-8. setCapBounds -- the operator SCBNDS/SCBNDSI call (ADR-0028: it takes the slot
 * exponent N, NOT a length).
 *
 * Four criteria, in the order the instruction pages state them:
 *   (1) form: the parent must be Aligned or Bare. Poisoned and Descriptor parents fail.
 *       Descriptor failing is a real limitation, not an oversight: its interval lives in
 *       the table, and the table path is not built yet, so there is nothing to check
 *       against.
 *   (2) N <= VA.
 *   (3) monotonicity -- "the slot lies inside the parent". TruISA carries NO bounds in
 *       the pointer, so this cannot be an interval test. It is a SLOT test: both slots
 *       start at the parent's own base, so a child slot is inside the parent slot iff
 *       its exponent is no smaller (N >= Np). A Bare parent has no slot and constrains
 *       nothing.
 *   (4) ⚠️ CR-MAC-01 Rev.1 lists "L = 0 fails". Under ADR-0028 the operand is N, not a
 *       length, and N = 0 is a legal one-byte slot -- so there is no L here to be zero.
 *       The criterion is therefore ABSENT by design, not forgotten. Reported to the
 *       architecture group rather than papered over with a `N != 0` test that would
 *       reject legal one-byte objects.
 *
 * ⭐ Failure returns the parent UNSIGNED, and the caller poisons it:
 *     truisa_inst.sail:175  C(cd) = poisonIf(newCap, not(hi_ok) | not(inParent))
 * That shape is only free if this function signs nothing on the failure path. Return
 * `parent` itself -- do not call makeCapAligned with fail=true, which is fine but would
 * still be a second trip through the same logic.
 * ---------------------------------------------------------------------------------- */
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

/* ====================================================================================
 * 1c. The bounds projection, and the checked pointer increment.
 *
 * Both requested by the architecture group's CADD notification (D-117). CADD is the first
 * instruction whose entire job lives inside the pointer -- no table, no DGU, no salt
 * (ADR-0013) -- so it is the first one that can actually run once the type checker
 * reaches truisa_inst.sail, and the first chance to prove the pointer layer end to end.
 * ==================================================================================== */

/* --- 1c-1. The bounds projection used by GCBASE / GCBOUND ---------------------------
 *
 * spec/insns/gcbase.adoc states the three forms as ONE formula, SlotBase(addr, K), with
 * K = the slot exponent N (aligned) / VA (bare) / the table entry's base (descriptor).
 *
 * ⚠️ The body below does NOT fold bare into that formula, deliberately. On a bare
 * pointer the `nc` FIELD IS NOT AN EXPONENT -- it is the low six bits of the seven-bit
 * label (ADR-0003), so 0000000 and 1111111 are both "bare" while their field values are
 * 0 and 63. Passing cap.nc to getCapSlotBase would return `addr` for one of them and 0
 * for the other: two different answers for one form. Bare therefore takes K = VA by
 * construction -- base 0, bound 2^VA - 1 (ADR-0019 rev 7).
 *
 * ⛔ None() has three sources and they are NOT the same thing (gcbase.adoc): poisoned
 * and invalid-N/C are real failures; descriptor form returns None() only because the
 * descriptor table is not implemented yet (phase A). Do not read that as "invalid".
 * ---------------------------------------------------------------------------------- */
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

/* --- 1c-2. The checked pointer increment used by CADD / CADDI ----------------------
 *
 * ⭐ `delta` is XLEN bits, NOT VA bits (ADR-0029 decision 10.1). Passing it truncated
 * silently maps `2^48 + 1` onto `+1`, which leaves criterion (3) permanently unreachable
 * -- the check would still be written and could never fire. The wrong signature was in
 * ADR-0029 decision 8, not in this file.
 *
 * Criteria, in spec/insns/cadd.adoc order (1 representable / 2 intact / 3 no carry):
 *
 * (1) representable -- the result stays inside the source pointer's slot. Bare pointers
 *     have no slot and constrain nothing (ADR-0019), so they short-circuit to true.
 * (2) intact -- on the ALIGNED path the salt is all-zero BY SPEC, not by placeholder:
 *     an aligned slot has no table entry, hence no salt and no re-keying moment, so the
 *     spec fixes that segment at zero and keeps it fixed in phase B too (spec/ch04:251,
 *     :256, ADR-0005 revision 11 item 3). So this is a real verify against the real
 *     (all-zero) salt, not a weakening. What is genuinely unimplemented is the DESCRIPTOR
 *     path: no operator produces that form in phase A (ADR-0029 decision 10.4).
 * (3) no carry -- computed on the FIELD, not on the 64-bit sum.
 *
 * ⭐ Why copying `pac` through is correct, and not a missing re-sign: the MAC input is
 * (label, CentroID, salt), and the CentroID is a function of the SLOT (C and S), not of
 * the address (ADR-0004). Criterion (1) has just proved the new address is in the same
 * slot, so the signature still covers it -- "no re-signing inside a slot" is the stated
 * rationale of cadd.adoc (ADR-0013 decision 2 / ADR-0005 decision 3 corollary 1). If (1)
 * is ever relaxed, this copy becomes unsound.
 *
 * ⛔ (3) must be the field-overflow test below, NOT `sign_extend(new[VA-1..0]) == new64`.
 * That self-check is not merely fragile, it is broken for the upper half of the address
 * space: whenever the result's bit (VA-1) is 1, sign_extend of the low VA bits is a
 * NEGATIVE 64-bit number while the sum is positive, so the two are never equal.
 *   counterexample: a = 2^47 - 1, delta = +1. The result 2^47 is inside the field, so the
 *   pointer must survive -- but the self-check compares 0x0000_8000_0000_0000 with
 *   sign_extend(0x8000_0000_0000) = 0xFFFF_8000_0000_0000 and poisons it.
 *   i.e. every increment that crosses into the high half would poison, which is where
 *   stacks and kernel mappings live.
 * The two facts are about different objects: the sum can wrap in 64 bits, the field
 * cannot, and neither implies the other. Testing the FIELD directly is the only form
 * that does not depend on a side condition.
 *
 * Downward overflow is ALLOWED: a negative delta wraps mod 2^VA, exactly like the
 * blueprint's `cap.address + delta`. ⛔ Do not "tighten" this to "result in [0, 2^VA)" --
 * that poisons every `p -= 1`.
 * ---------------------------------------------------------------------------------- */
val  incCapAddrChecked : (Capability, xlenbits) -> Capability
function incCapAddrChecked(cap : Capability, delta : xlenbits) -> Capability = {
  let form = getCapForm(cap);
  /* Poisoned and invalid are copied as they are, never laundered into something usable. */
  if form == FormPoisoned | form == FormInvalid then cap
  else {
    let a : CapAddrBits = cap.address[truisa_address_width - 1 .. 0];

    /* One bit wider than XLEN: `a` zero-extended and `delta` sign-extended, so the sum
     * cannot wrap inside ptr_width+1 bits.
     *   sum[ptr_width] = 1  => negative result, i.e. downward overflow -> allowed
     *   sum[ptr_width] = 0  => value in [0, 2^ptr_width); anything above the field is a
     *                          carry, and that is exactly criterion (3). */
    let sum : bits(truisa_ptr_width + 1) = zero_extend(a) + sign_extend(delta);
    let overflow : bool =
      (sum[truisa_ptr_width] == 0b0)
      & (sum[truisa_ptr_width - 1 .. truisa_address_width] != zeros());

    let new48 : CapAddrBits = truncate(sum, truisa_address_width);

    /* Criterion (1) -- representable. A bare pointer has no slot, so the requirement
     * degrades to staying in the same bit (VA-1) HALF, exactly as in setCapAddrChecked
     * below (ADR-0029 decision 11.4). ⚠️ It is NOT `true`: letting CADD cross the half
     * while SCADDR refuses to would mean relative moves and absolute writes disagree
     * about legality -- the very incoherence isa/07 section 7.7.10 uses to reject the
     * [base,bound] reading. Cost: a bare pointer cannot cross 2^(VA-1). */
    let same_slot : bool =
      if form == FormBare then a[truisa_address_width - 1] == new48[truisa_address_width - 1]
      else getCapSlotBase(a, cap.nc) == getCapSlotBase(new48, cap.nc);

    /* Criterion (2) -- intact. ⚠️⚠️ SKIPPED for bare, and that is load-bearing, not a
     * convenience: bare pointers are NEVER signed (ADR-0005 decision 3), so their PAC
     * field stays zero and any comparison against a signed value would be trivially
     * FALSE. Without the skip, every bare-pointer `p += 4` in S/M mode would poison,
     * which is the whole of ADR-0011's permissive tier (ADR-0029 decision 11.2).
     *
     * ⭐ The salt is NOT decided here. It comes from keySalt (D-220), the only producer in
     * the tree. On an aligned pointer that is the all-zero salt the spec fixes for that
     * form, so the check is genuinely performed and genuinely passes; its only
     * discriminating power in phase A is therefore "cs1 is not bare".
     *
     * ⛔ Do not "put a real salt here" when the descriptor table lands. The salt stopped
     * being this site's business, and a local change would reintroduce exactly the
     * ambiguity D-220 removed -- worse, if sign and verify were changed together it would
     * go green while silently violating the spec's all-zero rule for aligned slots.
     * Read keySalt's header ("two paths, one exit") before touching anything. */
    let intact : bool =
      if form == FormBare then true else verifyPtr(cap, keySalt(cap));

    let newCap : Capability = struct {
      mode    = cap.mode,
      nc      = cap.nc,
      pac     = cap.pac,
      address = sign_extend(new48),
    };
    poisonIf(newCap, overflow | not(same_slot) | not(intact))
  }
}

/* --- 1c-3. The checked address setter used by SCADDR -------------------------------
 *
 * ⛔ NOT "setCapAddr plus a sealed check": TruISA has no sealed (ADR-0001, ADR-0029
 * decision 8). The criterion is the one spec/insns/scaddr.adoc states -- the new address
 * must be REPRESENTABLE relative to the old one:
 *   - aligned / descriptor mode: same slot (same exponent, same slot base);
 *   - bare: no slot to stay inside, so the requirement degrades to the same
 *     bit (VA-1) half of the address space. Crossing halves changes the meaning of the
 *     sign-extended high bits, which is the closest a slotless pointer has to "moved".
 *
 * ⚠️ Only ONE criterion, not CADD's three: scaddr.adoc notes explicitly that the result's
 * bits 63-VA equal the source's BY CONSTRUCTION (the label is copied, not recomputed), so
 * that is not an independent check; and there is no delta, so there is no carry to test.
 * ⭐ CORRECTION (ADR-0029 decision 11.5): that reading dropped criterion (2) as well. The
 * "high 16 bits" sentence in scaddr.adoc explains why there is no THIRD criterion; it is
 * not criterion (2). SCADDR does have an integrity criterion, and isa/07 section 7.7.10
 * spells out both. Both are evaluated below, in the spec's order (1 representable, then
 * 2 intact), so that a future xtval can say which one failed first.
 *
 * ⚠️ `pac` is copied for the same reason as in 1c-2: the MAC covers the CentroID, and the
 * criterion just proved the address did not leave the slot.
 *
 * ℹ️ The unchecked blueprint primitive `setCapAddr(c, addr) -> (bool, Capability)` is NOT
 * defined here: nothing in the TruISA chain calls it, and an unused top-level symbol is
 * surface with no reader. One line to add if a future instruction needs it.
 * ---------------------------------------------------------------------------------- */
val  setCapAddrChecked : (Capability, CapAddrBits) -> Capability
function setCapAddrChecked(cap : Capability, addr : CapAddrBits) -> Capability = {
  let form = getCapForm(cap);
  if form == FormPoisoned | form == FormInvalid then cap
  else {
    let a : CapAddrBits = cap.address[truisa_address_width - 1 .. 0];
    /* (1) representable: same slot, or -- for bare, which has no slot -- the same
     * bit (VA-1) half. Same rule as incCapAddrChecked, deliberately (decision 11.4). */
    let representable : bool =
      if form == FormBare then addr[truisa_address_width - 1] == a[truisa_address_width - 1]
      else getCapSlotBase(a, cap.nc) == getCapSlotBase(addr, cap.nc);
    /* (2) intact: skipped for bare for the same reason as in 1c-2 (bare is never signed,
     * so the check would be trivially false and SCADDR would poison every bare address
     * write). The salt comes from keySalt, the only producer in the tree (D-220) -- this
     * site carries no salt knowledge at all. */
    let intact : bool =
      if form == FormBare then true else verifyPtr(cap, keySalt(cap));
    let newCap : Capability = struct {
      mode    = cap.mode,
      nc      = cap.nc,
      pac     = cap.pac,
      address = sign_extend(addr),
    };
    poisonIf(newCap, not(representable) | not(intact))
  }
}
