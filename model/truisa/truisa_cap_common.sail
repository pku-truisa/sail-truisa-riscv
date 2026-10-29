/*=======================================================================================*/
/*  TruISA: the capability itself -- widths, slices, encode/decode, bounds.              */
/*                                                                                       */
/*  Counterpart: model/cheri/cheri_cap_common.sail (700 lines).                          */
/*                                                                                       */
/*  Status: 1a DONE (CR-MAC-01 Rev.1): widths + the Capability struct + the eight         */
/*  read-only operators. 1b (the MAC stub, sign/verify, makeCapAligned, setCapBounds)     */
/*  is still open, so SCBNDS cannot sign yet. capToMetadataBits and the bounds decode     */
/*  stay out: TruISA has no metadata and no in-pointer bounds.                            */
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
 * 1a-1. The capability.
 *
 * 63            62      57 56        48 47                                    0
 * +---------------+--------+-----------+---------------------------------------+
 * | mode (1)      | N/C (6)| PAC (9)   | address (48)                          |
 * +---------------+--------+-----------+---------------------------------------+
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
  address : CapAddrBits,
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
 * 1a-2 / 1a-3. Assemble and disassemble the 64-bit pointer.
 *
 * These two are inverses and must stay that way: every instruction that reads a field
 * goes through one of them rather than slicing the struct twice (bit-position drift is
 * the failure mode this prevents -- the same reason getCapTagBits exists).
 * ---------------------------------------------------------------------------------- */
val  capToBits : Capability -> CapBits
function capToBits(cap : Capability) -> CapBits =
  cap.mode @ cap.nc @ cap.pac @ cap.address

val  bitsToCap : CapBits -> Capability
function bitsToCap(ptr : CapBits) -> Capability =
  struct {
    mode    = ptr[truisa_ptr_width - 1 .. truisa_ptr_width - truisa_mode_width],
    nc      = ptr[truisa_ptr_width - truisa_mode_width - 1
                  .. truisa_address_width + truisa_pac_width],
    pac     = ptr[truisa_address_width + truisa_pac_width - 1 .. truisa_address_width],
    address = ptr[truisa_address_width - 1 .. 0],
  }

/* ------------------------------------------------------------------------------------
 * 1a-4. The 7-bit label (bits 63-57): mode plus N/C. Every form decision hangs off it.
 * The slice is derived from the constants, never written as 63..57 -- that is exactly
 * the hard-coding that made the D-94/D-96 line numbers drift.
 * ---------------------------------------------------------------------------------- */
val  getCapTagBits : Capability -> CapTagBits
function getCapTagBits(cap : Capability) -> CapTagBits =
  capToBits(cap)[truisa_ptr_width - 1 .. truisa_address_width + truisa_pac_width]

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
 * Two inputs return the reserved value 0 rather than a number:
 *   - N = 0: 1-byte slot, S + 2^(-1) is not an integer; there is no midline.
 *   - N = VA: whole-space slot (ADR-0026), S = 0 and 2^(VA-1) is the midline of the
 *     entire space, which no object can own; ADR-0026 makes it 0.
 * Both must be INDEXED as a miss by the table path, never as "the entry at address 0".
 *
 * ⚠️ 2^(N-1) is computed as (1 << N) >> 1 in a 64-bit intermediate: (1 << (N-1)) would
 * need a proof that N >= 1, which Sail cannot get out of the compared-equal branch, and
 * shift amounts must not be negative anyway. Same trick as getCapSlotBase.
 * ---------------------------------------------------------------------------------- */
val  getCapCentroID : (CapAddrBits, bits(truisa_nc_width)) -> CapAddrBits
function getCapCentroID(p : CapAddrBits, n : bits(truisa_nc_width)) -> CapAddrBits = {
  let k : int = unsigned(n);
  let base : CapAddrBits = getCapSlotBase(p, n);
  if k == 0 | k == truisa_address_width then zeros()
  else {
    let twop : bits(64) = 0x0000_0000_0000_0001 << k;
    base + truncate(twop >> 1)
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
