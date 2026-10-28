/*=======================================================================================*/
/*  TruISA: capability register accessors.                                               */
/*                                                                                       */
/*  Copy-and-adapt of model/cheri/cheri_regs.sail. Same file role -- it is the ONLY      */
/*  place that knows how a capability is read from / written to the register file --     */
/*  but the storage is different: CHERI has a separate capability register file, TruISA  */
/*  keeps the pointer in the integer register (ADR-0017).                               */
/*                                                                                       */
/*  TRUISA DELTA vs cheri_regs.sail:                                                     */
/*    - rC/wC read and write X() through bitsToCap/capToBits instead of                */
/*      rX_full/wX_full, and there is no xreg_write_callback (that callback exists so     */
/*      RVFI can observe CHERI's separate cap registers; TruISA's pointers are ordinary   */
/*      integer registers and RVFI already sees them)                                    */
/*    - regtype becomes Capability (TruISA has no second register type)                  */
/*    - ext_rvfi_reset seeds null_cap instead of infinite_cap (TruISA has no             */
/*      infinite-bound capability: the whole-space slot N = VA is the equivalent, but it  */
/*      is still an ordinary aligned pointer)                                            */
/*    - DROPPED: cap_creg_name (no cregidx -- no separate cap register file),             */
/*      sys_cheri_accurate_tag_clearing (CHERI config knob, no tag to clear),            */
/*      convertInvalidAddrCap + overload convertInvalidAddr (need sealed/tag/infinite     */
/*      bounds), setCapCSRAddr (TruISA has no capability-valued CSRs)                    */
/*=======================================================================================*/

/* accessors for capability representation */

/* Reads a given capability register. X(0) is always zero, so rC(0) is the null
   capability for free -- no special case is needed here. */
// ⚠️ The cast is the single xlenbits <-> CapBits boundary in the whole model.
// CapBits is bits(8 * cap_size) = bits(64) (a computable literal), while
// xlenbits is bits(xlen) (symbolic), so Sail needs the conversion spelled out
// even though both are 64 bits wide on RV64.
function rC(r : regno) -> Capability = bitsToCap(false, truncate(X(r)))

/* Writes a register with a capability value. */
function wC (Regno(r) : regno, v : Capability) -> unit = {
  X(Regno(r)) = zero_extend(capToBits(v))
}

function rC_bits(Regidx(i): regidx) -> Capability = rC(Regno(unsigned(i)))

function wC_bits(Regidx(i): regidx, v: Capability) -> unit = {
  wC(Regno(unsigned(i))) = v
}

overload C = {rC_bits, wC_bits, rC, wC}

/*!
 * Called after the ordinary reset when running rvfi, to initialise the pointer
 * registers differently. CHERI seeds infinite capabilities; TruISA seeds null
 * ones (an all-zero word is a Bare pointer covering nothing interesting).
 */
val ext_rvfi_reset : unit -> unit
function ext_rvfi_reset () = {
  foreach (i from 1 to 31) wC(Regno(i), null_cap);
}

/* mappings for assembly */

mapping cap_reg_name : regidx <-> string = {
    Regidx(0b00000) <-> "cnull",
    r               <-> "c" ^ reg_name(r)
}
