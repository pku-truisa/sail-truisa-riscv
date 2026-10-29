/*=======================================================================================*
 *  TruISA: counterpart of model/cheri/cheri_reg_type.sail
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. This position replaces riscv_reg_type.sail (which is NOT in
 *  truisa_regs_srcs), so there is exactly one `regtype` definition per chain -- the
 *  upstream riscv_reg_type.sail:10 setting `regtype = xlenbits` is not compiled here.
 *
 *  What the blueprint file does (25 lines): regtype / zero_reg / RegStr /
 *  regval_from_reg / regval_into_reg -- the register value type and its conversions.
 *
 *  Status: DONE (ADR-0029 decision 2). It became possible only once `address` grew to
 *  bits(truisa_ptr_width): `{... with address = v}` needs address and xlenbits to be
 *  the same width, which they were not while address was 48 bits (D-113 recorded that
 *  as the hard reason these two files stayed empty).
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* register type */
type regtype = Capability

/* null cap.
 *
 * ⚠️ Spelled field by field rather than `null_cap`: TruISA has no `null_cap` symbol
 * (grep -rn "null_cap" model/truisa/ => 0). The value is unambiguous -- all-zero
 * metadata gives label 0000000, which getCapForm maps to FormBare at address 0
 * (docs/isa/03 section 3.3) -- so nothing is invented here, but the blueprint's
 * spelling cannot be reused either.
 *
 * `zeros()` rather than 0b000000 for nc: an RV32 target has a 5-bit N/C field
 * (truisa_nc_width), so a literal would not follow the profile (D-96). */
let zero_reg : regtype = struct {
  mode    = zeros(),
  nc      = zeros(),
  pac     = zeros(),
  address = zeros(),
}

/* register printer.
 *
 * TODO(truisa): the blueprint calls capToString (cheri_cap_common.sail:634), which
 * does not exist on the TruISA side (grep -rn "capToString" model/truisa/ => 0).
 * Printing is not what this file is for, so it returns a constant for now rather than
 * growing a printer here (architecture group, ADR-0029 CR section 13 item 2). */
val RegStr : Capability -> string
function RegStr(r) = "Capability"

/* conversions */

val regval_from_reg : regtype -> xlenbits
function regval_from_reg(r) = r.address

/* ⛔ Do NOT normalise here (no sign_extend(v[VA-1..0])). Normalising on write would
 * distort every integer write -- `li a0, 0x0000_8000_0000_0000` would read back as
 * 0xFFFF_8000_0000_0000 and LP64 would break (ADR-0029 decision 6). The price is that
 * a bare integer round-tripped through a register keeps only its low VA bits in
 * signed form; that is registered as an ABI-chapter item, not a defect. */
val regval_into_reg : xlenbits -> regtype
function regval_into_reg(v) = struct {
  mode    = zeros(),
  nc      = zeros(),
  pac     = zeros(),
  address = v,
}
