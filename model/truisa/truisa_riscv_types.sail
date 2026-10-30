/*=======================================================================================*
 *  TruISA: counterpart of model/cheri/cheri_riscv_types.sail
 *
 *  Why this file exists: the fork mirrors the CHERI tree one file for one, so that
 *  the two models can be read side by side and every position in model/CMakeLists.txt
 *  has a counterpart. An empty placeholder is still meaningful: it marks a position
 *  where the answer is "TruISA has nothing here", and that answer has to be justified
 *  like any other.
 *
 *  What the blueprint file does (94 lines, four blocks, in this order):
 *     1. :21  enum TaggedLoadBehaviour
 *     2. :31  enum CheriPageFault
 *     3. :52  CHERI exception extensions -- ext_exc_type + its four conversions
 *     4. :93  CHERI fetch address checks -- type ext_fetch_addr_error = CapEx
 *
 *  Status: BLOCK 3 DONE (D-110). Blocks 1, 2 and 4 are still NOT ANALYSED, so this
 *  file remains incomplete and the fork still does not type-check. Files are analysed
 *  in dependency order, from the top of model/CMakeLists.txt down; a missing
 *  definition is a question for spec, not something to paper over with a stub that
 *  compiles.
 *
 *  Rules for filling this in (see CODE_STYLE.md, "Fork rule"):
 *    1. Copy the blueprint block order, then edit; do not rewrite from scratch.
 *    2. Mark every deviation with a TRUISA DELTA comment naming the ADR that forces it.
 *    3. If the answer is "the upstream riscv_*.sail already does this", say so here and
 *       leave the file empty instead of duplicating it.
 *    4. If nobody knows what the definition should be, stop and raise a CR -- do not
 *       invent a definition that merely satisfies the type checker (D-69 section 5).
 *=======================================================================================*/

/* --- Block 3 of 4: exception extensions (D-110) ------------------------------------
 *
 * TRUISA DELTA: blueprint names this EXC_CHERI (cheri_riscv_types.sail:61).
 * Renamed only for grep-ability in the fork; the value 28 is unchanged and is
 * mandated by ADR-0010 revision 8 (single mcause for all pointer failures).
 *
 * The 28 is INHERITED, not independently chosen: ADR-0010 r8 records the blueprint
 * basis (ADR-0024 -> CHERI-RISC-V 0.9.3 sections 4.7.8 / 4.7.11), and
 * spec/ch06-exceptions.adoc:6 calls the same value "CHERI fault".
 *
 * Do NOT copy riscv_types_ext.sail's 24 / 0x18. That number is the base model's
 * "first code for a custom extension" (riscv_types_ext.sail:41) -- i.e. simply the
 * wrong number here, not a competing claim. That file is in neither source list
 * (grep -c riscv_types_ext.sail model/CMakeLists.txt => 0), so each chain supplies
 * its own ext_exc_type.
 *
 * 28 appears twice ON PURPOSE: 0x1c for the CSR field, 28 for the delegatee index.
 * They are two different hardware positions, both fixed by spec:
 *   - mcause[Cause]      <- exceptionType_to_bits
 *       riscv_types.sail:179 (E_Extension) -> riscv_sys_control.sail:222
 *   - medeleg bit index  <- num_of_ExceptionType
 *       riscv_types.sail:227 (E_Extension) -> riscv_sys_control.sail:93
 * Collapsing them into one constant would need a truncate/to_bits conversion
 * between bits(8) and range(0, xlen-1) -- one more place to get wrong.
 *
 * $[no_enum_number_conversions] is required: without it Sail generates implicit
 * numbering conversions that would clash with the hand-written to_bits below.
 * ---------------------------------------------------------------------------------- */

$[no_enum_number_conversions]
enum ext_exc_type = {
  EXC_TRUISA,
}

/* Convert exception code to extended exception type. */
val ext_exc_type_to_bits : ext_exc_type -> exc_code
function ext_exc_type_to_bits(e) =
  match e {
    EXC_TRUISA => 0x1c,
  }

/* Convert from the exception code to the extended exception type.
 *
 * Reverse-decodable, matching the blueprint (cheri_riscv_types.sail:68-78). NOT
 * load-bearing for ADR-0010: the TYPE x CAUSE split lives in mtval2 (TYPE =
 * bits 19-16, CAUSE = low 4), and mcause = 28 only says "extension exception".
 * It is kept because it costs one match branch and doubles as a value-uniqueness
 * assertion: adding a second TruISA extension exception later would make this
 * function non-total and force the author to decide.
 */
val ext_exc_type_of_bits : exc_code -> ext_exc_type
function ext_exc_type_of_bits(e) =
  match e {
    0x1c => EXC_TRUISA,
    _ => internal_error(__FILE__, __LINE__, "unknown exception type")
  }

/* TruISA conversion of extension exceptions to integers. */
val num_of_ext_exc_type : ext_exc_type -> range(0, xlen - 1)
function num_of_ext_exc_type(e) =
  match e {
    EXC_TRUISA => 28,
  }

/* TruISA conversion of extension exceptions to strings. */
val ext_exc_type_to_str : ext_exc_type -> string
function ext_exc_type_to_str(e) =
  match e {
    EXC_TRUISA => "truisa",
  }

/*=======================================================================================*
 * The three extension-stub types that model/riscv_types_ext.sail provides upstream.
 *
 * ⚠️ That base file cannot be added to the chain as a whole: it also defines
 * `ext_exc_type` plus its four conversions, and this file defines those already (the enum
 * above replaced CHERI's `= unit` placeholder). Adding it whole fails with
 *
 *     Cannot define type synonym ext_exc_type, as a type or synonym with that name
 *     already exists                    -- riscv_types_ext.sail:39
 *
 * so the rule "no unresolved dependency, therefore use the base file" is not sufficient
 * on its own -- it also has to define nothing this chain already defines.
 *
 * These three are byte-for-byte the upstream values (`riscv_types_ext.sail:35/57/60`),
 * and each has a real user on this chain:
 *   ext_ptw              riscv_sync_exception.sail:14, riscv_vmem_access.sail
 *   ext_csr_exc_type     riscv_ext_regs.sail:17/24, riscv_inst_retire.sail:26
 *   ext_fetch_addr_error riscv_step_common.sail:51, riscv_step.sail:15, riscv_addr_checks.sail
 *=======================================================================================*/

type ext_ptw = unit
type ext_csr_exc_type = unit
type ext_fetch_addr_error = unit

/* D-162 (裁甲): the fourth atom of the same family, byte-for-byte upstream
 * (riscv_types_ext.sail:36). It is a `let`, not a type, which is exactly why the
 * 2026-10-30 patch that took the three types above missed it -- the rule was "take the
 * missing names", and `init_ext_ptw` is a missing *value*.
 *   user: riscv_vmem.sail:346 / :359 / :373 -- the PTW accumulator's initial value.
 * Cost of not having it: `Identifier init_ext_ptw is unbound` at riscv_vmem.sail:346. */
let init_ext_ptw : ext_ptw = ()
