/*=======================================================================================*
 *  TruISA copy of model/riscv_vmem_pte_ext.sail -- WITH ONE CHARACTER PAIR REMOVED.
 *
 *  (1) This copy exists for exactly one reason: base riscv_vmem_pte_ext.sail:45 writes
 *      `if not(plat_enable_dirty_update()) then`, and `plat_enable_dirty_update` is a
 *      `let ... : bool` value (riscv_platform.sail:120), not a function. Applying it to
 *      `()` is a type error. The fix is to delete the empty argument list -- nothing else
 *      in the file is touched.
 *
 *      Measured, not inferred (minimal repro, Sail 0.20.3):
 *          let plat_enable_dirty_update : bool = true
 *          function f() -> bool = if not(plat_enable_dirty_update()) then ...   -> ERROR
 *              "checking function argument has type bool; Function
 *               plat_enable_dirty_update not found"
 *          function f() -> bool = if not(plat_enable_dirty_update) then ...     -> OK
 *      The base file has never been compiled, which is why this survived: at the fork
 *      point (de92797) CMakeLists.txt listed it 0 times -- it is a dormant extension
 *      hook. CHERI enabled this position with its own cheri_vmem_pte_ext.sail, which
 *      writes the call without the parens (:28 / :99).
 *
 *  (2) Do NOT generalise from this file. It is not evidence that "copying the base and
 *      editing it" is the preferred repair -- rule 8 in CODE_STYLE.md still says a base
 *      file with no unresolved reference and no name collision is used AS-IS (改链).
 *      One character, one file, one reason.
 *
 *  (3) When upstream fixes that line, DELETE this file and point the chain back at
 *      `riscv_vmem_pte_ext.sail`. Nothing else depends on this copy.
 *
 *  ⚠️ base 不可改：model/ 根目录下的文件一律不动（ADR-0024 section 11.4b），所以
 *  只能"用 model/truisa/ 一份顶替"，不能改 base 那一个字符。
 *=======================================================================================*/

/*=======================================================================================*/
/*  This Sail RISC-V architecture model, comprising all files and                        */
/*  directories except where otherwise noted is subject the BSD                          */
/*  two-clause license in the LICENSE file.                                              */
/*                                                                                       */
/*  SPDX-License-Identifier: BSD-2-Clause                                                */
/*=======================================================================================*/

// ----------------
// Check access permissions in PTE

// For (non-standard) extensions: this function gets the extension-available bits
// of the PTE in pte_ext_bits, and the accumulated information of the page-table-walk
// in ext_ptw. It should return the updated ext_ptw in both success and failure cases.

// This appears to be redundant but it is here so CHERI
// can override it without reimplementing pte_rwxu_permission_ok().
function pte_permission_ok(
  ac      : AccessType(ext_access_type),
  priv    : Privilege,
  mxr     : bool,
  do_sum  : bool,
  pte     : PTE_Flags,
  ext     : option(PTE_Ext), // None() for Sv32.
  ext_ptw : ext_ptw,
) -> (bool, ext_ptw) =
  (pte_rwxu_permission_ok(ac, priv, mxr, do_sum, pte), ext_ptw)

// Update a PTE's A/D bits and write it to memory. This returns
//
// * Ok(Some(pte)) if a write was needed and was successful. pte is the new value.
// * Ok(None()) if no write was needed.
// * Err(e) if a write was needed but there was an error.
//
function update_pte forall 'pte_width, 'pte_width in {4, 8} . (
  pte_width : int('pte_width),
  pteAddr   : physaddr,
  pte       : bits('pte_width * 8),
  ac        : AccessType(ext_access_type),
  ext_ptw   : ext_ptw,
) -> (result(option(bits('pte_width * 8)), PTW_Error), ext_ptw) =
  (match updated_pte_bits(pte, ac) {
    None() => Ok(None()),
    Some(pte) =>
      if not(plat_enable_dirty_update) then {
        // PTE needs dirty/accessed update but that is not enabled.
        Err(PTW_PTE_Update())
      } else {
        // Writeback the PTE (which has new A/D bits).
        match write_pte(pteAddr, 'pte_width, pte) {
          Ok(_) => Ok(Some(pte)),
          Err(_) => Err(PTW_Access()),
        }
      },
  }, ext_ptw)
