/*=======================================================================================*
 *  TruISA: the step / model hooks. Eight definitions, and the two that read memory are
 *  REAL semantics -- not stubs.
 *
 *  Why this file is not empty any more: model/riscv_step_ext.sail defines nine hooks, but
 *  every one of them delegates to a `track_*` function that does not exist anywhere in
 *  this fork -- `git grep track_fetch_mem_read_hook de92797 80a9e65` hits only the two
 *  call sites inside that file. So the base file cannot be used as-is (question 1 of the
 *  three: an unresolved reference), and this position supplies the hooks instead.
 *
 *  ⛔ base files untouched: riscv_fetch.sail / riscv_step_ext.sail / riscv_step.sail /
 *  riscv_model.sail are all byte-identical (D-164 section 3.4).
 *
 *  ⛔ Nine hooks exist upstream, EIGHT are written here. `ext_vector_fetch_hook` has zero
 *  callers in this chain (no vector table fetch), so defining it would be inventing an
 *  API nobody uses (D-69 section 5). It stays out until something calls it.
 *=======================================================================================*/

/*=======================================================================================*
 *  TRUISA DELTA (D-164 / D-9) -- where each body comes from.
 *
 *  | hook                  | body                                                       |
 *  |-----------------------|------------------------------------------------------------|
 *  | ext_fetch_mem_read_lo | REAL READ -- see the provenance note below                 |
 *  | ext_fetch_mem_read_hi | REAL READ -- same                                          |
 *  | ext_fetch_hook        | identity (`= f`) -- base body is `track_fetch_hook(f)` and  |
 *  |                       |   TruISA has no tracing layer at all                       |
 *  | ext_pre_step_hook     | `()` -- pure trace position                                |
 *  | ext_post_step_hook    | `()` -- same                                               |
 *  | ext_print_instr       | copied verbatim -- its base body does NOT touch track_*    |
 *  | ext_reset             | `()` -- base body is `()`                                  |
 *  | ext_reset_misa        | `()` -- base body is `()`                                  |
 *
 *  ⭐ PROVENANCE of the two reads (D-164 section 3.2) -- this is copied, not invented.
 *  In upstream 72a56e9 the fetch step is written WITHOUT these hooks, inline:
 *
 *      model/riscv_fetch.sail:35 (72a56e9)
 *      match mem_read(InstructionFetch(), ppclo, 2, false, false, false) {
 *
 *  This fork moved that line into a hook and passes one extra argument, `pbmt`, because
 *  translateAddr now returns the triple `Ok(ppclo, pbmt, _)`. So the body here is that
 *  upstream line with `pbmt` inserted where the current mem_read signature wants it
 *  (riscv_mem.sail:236):
 *
 *      mem_read : (AccessType(ext_access_type), PBMT, physaddr, int('n), bool, bool, bool)
 *                 -> MemoryOpResult(bits(8 * 'n))
 *
 *  ⛔ No freedom of choice is being exercised: 2 bytes, InstructionFetch(), no ordering,
 *  no reservation -- exactly what the upstream line asked for.
 *
 *  ⚠️ Boundary (D-164 section 3.4): this file implements THESE EIGHT HOOKS ONLY. It is not
 *  a licence to touch mem_read / translateAddr or the fetch path they belong to.
 *=======================================================================================*/

/* ---- the two real reads: one 16-bit granule of the instruction stream ---- */

function ext_fetch_mem_read_lo(paddr : physaddr, pbmt : PBMT) -> MemoryOpResult(half) =
  mem_read(InstructionFetch(), pbmt, paddr, 2, false, false, false)

function ext_fetch_mem_read_hi(paddr : physaddr, pbmt : PBMT) -> MemoryOpResult(half) =
  mem_read(InstructionFetch(), pbmt, paddr, 2, false, false, false)

/* ---- tracing layer: TruISA has none (riscv_callbacks.sail is all no-ops) ---- */

function ext_fetch_hook(f : FetchResult) -> FetchResult = f

function ext_pre_step_hook()  -> unit = ()
function ext_post_step_hook() -> unit = ()

/* ---- copied verbatim from riscv_step_ext.sail:21-29 (no track_* in its body) ---- */

function ext_print_instr forall 'n, 'n in {16, 32} . (
  step_no : int, instruction : instruction, opcode : bits('n)
) -> unit = {
  if get_config_print_instr()
  then print_instr(
    "[" ^ dec_str(step_no) ^ "] [" ^ to_str(cur_privilege()) ^ "]: " ^
    BitStr(PC) ^ " (" ^ BitStr(opcode) ^ ") " ^ to_str(instruction)
  );
}

function ext_reset()      -> unit = ()
function ext_reset_misa() -> unit = ()
