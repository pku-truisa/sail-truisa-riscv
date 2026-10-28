# =====================================================================================
#  TruISA model build.
#
#  This file REPLACES model/CMakeLists.txt for the TruISA fork. It is a separate
#  build on purpose: see "Fork rule" in ../../CODE_STYLE.md -- a model/truisa build
#  must never link a cheri_* file.
#
#  Layout note: the upstream .sail files are referenced as ../<name>.sail because
#  this CMakeLists.txt sits one level down. Everything that TruISA defines itself
#  lives next to this file without a prefix.
#
#  Two targets:
#    truisa_check -- sail --just-check, i.e. type-check only. Fast, no C generated.
#    truisa_c     -- sail -c, i.e. generate the C emulator model.
# =====================================================================================

# SAIL_BIN comes from the top-level CMakeLists.txt when this directory is added via
# add_subdirectory(). When configured stand-alone, fall back to the tool on PATH so
# the fork can be checked without touching the upstream build files.
if(NOT DEFINED SAIL_BIN)
    find_program(SAIL_BIN sail)
    if(NOT SAIL_BIN)
        message(FATAL_ERROR "sail not found: pass -DSAIL_BIN=/path/to/sail")
    endif()
endif()

cmake_minimum_required(VERSION 3.16)
project(truisa_model LANGUAGES NONE)

# Upstream RISC-V sources, same set (and same order) as model/CMakeLists.txt, minus
# every cheri/ entry. The order matters: Sail has no automatic dependency resolution,
# so the prelude must come first and the instruction files last.
set(truisa_upstream_srcs
    ../prelude.sail
    ../riscv_errors.sail
    ../range_util.sail
    ../riscv_xlen.sail
    ../riscv_flen.sail
    ../riscv_vlen.sail
    ../prelude_mem_addrtype.sail
    ../prelude_mem_metadata.sail
    ../prelude_mem.sail
    ../arithmetic.sail
    ../rvfi_dii.sail
    ../rvfi_dii_v1.sail
    ../rvfi_dii_v2.sail
    ../riscv_types_common.sail
    ../riscv_types_ext.sail
    ../riscv_types.sail
    # TruISA core vocabulary must exist before any upstream file references
    # Capability / setCapAddrChecked (riscv_pc_access.sail does).
    truisa_types.sail
    truisa_cap_common.sail
    ../riscv_extensions.sail
    ../riscv_csr_begin.sail
    ../riscv_convert_invalid_addr.sail
    ../riscv_callbacks.sail
    ../riscv_reg_type.sail
    ../riscv_freg_type.sail
    ../riscv_vmem_types.sail
    ../riscv_regs.sail
    ../riscv_sys_regs_xstatus.sail
    # sits here, not at the end, because it must precede riscv_sys_regs.sail
    truisa_sys_regs_types.sail
    ../riscv_sys_regs.sail
    ../riscv_sys_regs_envcfg.sail
    ../riscv_pmp_regs.sail
    ../riscv_pmp_control.sail
    ../riscv_pc_access.sail
    ../riscv_vreg_type.sail
    ../riscv_vext_regs.sail
    ../riscv_vext_control.sail
    ../riscv_sys_regs_access.sail
    ../riscv_sys_regs_access_common.sail
    ../riscv_sys_exceptions.sail
    ../riscv_sync_exception.sail
    ../riscv_zihpm.sail
    ../riscv_sscofpmf.sail
    ../riscv_zkr_control.sail
    ../riscv_zicntr_control.sail
    ../riscv_softfloat_interface.sail
    ../riscv_fdext_regs.sail
    ../riscv_fdext_control.sail
    ../riscv_smcntrpmf.sail
    ../riscv_pma.sail
    ../riscv_svpbmt.sail
    ../riscv_sys_reservation.sail
    ../riscv_sys_control.sail
    ../riscv_platform.sail
    ../riscv_addr_checks_common.sail
    ../riscv_addr_checks.sail
    ../riscv_sstc.sail
    ../riscv_mem.sail
    ../riscv_inst_retire.sail
    ../riscv_vmem_ptw.sail
    ../riscv_vmem_pte_types.sail
    ../riscv_vmem_pte_types_ext.sail
    ../riscv_vmem_pte_validity_ext.sail
    ../riscv_vmem_pte.sail
    ../riscv_vmem_pte_ext.sail
    ../riscv_vmem_tlb.sail
    ../riscv_vmem.sail
    ../riscv_vmem_utils.sail
    ../riscv_vmem_access.sail
    ../riscv_types_kext.sail
    ../riscv_zvk_utils.sail
    ../riscv_insts_begin.sail
    ../riscv_insts_base.sail
    ../riscv_insts_zifencei.sail
    ../riscv_insts_zaamo.sail
    ../riscv_insts_zalrsc.sail
    ../riscv_insts_zca.sail
    ../riscv_insts_mext.sail
    ../riscv_insts_zicsr.sail
    ../riscv_insts_hext.sail
    ../riscv_insts_reserved_fence.sail
    ../riscv_csr_op.sail
    ../riscv_insts_fext.sail
    ../riscv_insts_zcf.sail
    ../riscv_insts_dext.sail
    ../riscv_insts_zcd.sail
    ../riscv_insts_svinval.sail
    ../riscv_insts_zba.sail
    ../riscv_insts_zbb.sail
    ../riscv_insts_zbc.sail
    ../riscv_insts_zbs.sail
    ../riscv_insts_zcb.sail
    ../riscv_insts_zfh.sail
    ../riscv_insts_zfa.sail
    ../riscv_insts_zkn.sail
    ../riscv_insts_zks.sail
    ../riscv_insts_zbkb.sail
    ../riscv_insts_zbkx.sail
    ../riscv_insts_zicond.sail
    ../riscv_insts_vext_utils.sail
    ../riscv_insts_vext_fp_utils.sail
    ../riscv_insts_vext_vset.sail
    ../riscv_insts_vext_arith.sail
    ../riscv_insts_vext_fp.sail
    ../riscv_insts_vext_mem.sail
    ../riscv_insts_vext_mask.sail
    ../riscv_insts_vext_vm.sail
    ../riscv_insts_vext_fp_vm.sail
    ../riscv_insts_vext_red.sail
    ../riscv_insts_vext_fp_red.sail
    ../riscv_insts_zicbom.sail
    ../riscv_insts_zicboz.sail
    ../riscv_insts_zawrs.sail
    ../riscv_insts_zvbb.sail
    ../riscv_insts_zvbc.sail
    ../riscv_insts_zvkg.sail
    ../riscv_insts_zvkned.sail
    ../riscv_insts_zvknhab.sail
    ../riscv_insts_zvksed.sail
    ../riscv_insts_zvksh.sail
    ../riscv_insts_end.sail
    ../riscv_insts_zimop.sail
    ../riscv_insts_zcmop.sail
    ../riscv_jalr_seq.sail
    ../riscv_csr_end.sail
    ../riscv_step_common.sail
    ../riscv_step_ext.sail
    ../riscv_decode_ext.sail
    ../riscv_fetch_rvfi.sail
    ../riscv_fetch.sail
    ../riscv_step.sail
    ../riscv_validate_config.sail
    ../riscv_device_tree.sail
    ../riscv_model.sail
    ../main.sail
)

# The fork's own sources. Order matters here too:
#   types  -> cap_common -> regs -> addr_checks -> inst
set(truisa_own_srcs
    truisa_regs.sail
    truisa_addr_checks.sail
    truisa_inst.sail
)

set(truisa_srcs ${truisa_upstream_srcs} ${truisa_own_srcs})

set(truisa_common_flags
    --strict-var
    --strict-bitvector
)

# -------------------------------------------------------------------------------------
# Type check
# -------------------------------------------------------------------------------------
add_custom_target(truisa_check
    COMMENT "Type-checking the TruISA model (via -c: --just-check does not bind xlen)"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    # ⚠️ NOT --just-check. That mode never binds xlen (it ignores --config), so
    # every bits(<expr depending on xlen>) such as CapPacBits fails the
    # well-formedness check with a misleading "recursive types are forbidden".
    # Generating C with -c to /dev/null is the cheapest mode that does bind it.
    COMMAND ${SAIL_BIN} ${truisa_common_flags}
            --config ${CMAKE_CURRENT_SOURCE_DIR}/../../config/rv64d.json
            -c --c-no-main -o /dev/null
            ${truisa_srcs}
    VERBATIM
)

# -------------------------------------------------------------------------------------
# Generate C
# -------------------------------------------------------------------------------------
set(truisa_c_model "${CMAKE_CURRENT_BINARY_DIR}/truisa_model")

add_custom_target(truisa_c
    COMMENT "Building C code from the TruISA model"
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMAND ${SAIL_BIN} ${truisa_common_flags}
            -o ${truisa_c_model}
            -O --Oconstant-fold
            -c
            --c-generate-header
            --c-no-main
            --c-include riscv_prelude.h
            --c-include riscv_platform.h
            --c-include riscv_callbacks.h
            --c-preserve init_model
            --c-preserve try_step
            --c-preserve tick_clock
            --c-preserve force_pc
            --c-preserve generate_dts
            ${truisa_srcs}
    VERBATIM
)
