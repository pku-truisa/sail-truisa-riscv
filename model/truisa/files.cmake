# =====================================================================================
#  TruISA file chain -- data only, no targets.
#
#  Included by model/CMakeLists.txt when -DTRUISA=ON. It must NOT contain
#  project(), cmake_minimum_required(), add_custom_target() or anything that
#  defines a target: model/CMakeLists.txt owns the targets (generated_sail_riscv_model
#  etc.) so that c_emulator/ keeps working unchanged.
#
#  Why a separate file instead of inlining the list in model/CMakeLists.txt:
#    - the list stays diffable on its own (which files moved in/out);
#    - model/CMakeLists.txt is already 688 lines and the list is ~140 more;
#    - reverting the fork means deleting this one file, not unpicking a patch.
#
#  Paths are relative to model/ (where model/CMakeLists.txt sets its
#  WORKING_DIRECTORY), NOT to this directory: upstream files have no prefix,
#  the fork's own files carry the truisa/ prefix.
#
#  Order matters. Sail resolves names as it reads, so a definition must precede
#  every use. Two known constraints are marked inline where the fork files sit.
#
#  ⛔ No cheri/* entry may appear here (see "Fork rule" in CODE_STYLE.md).
# =====================================================================================

set(truisa_upstream_srcs
    prelude.sail
    riscv_errors.sail
    range_util.sail
    riscv_xlen.sail
    riscv_flen.sail
    riscv_vlen.sail
    prelude_mem_addrtype.sail
    prelude_mem_metadata.sail
    prelude_mem.sail
    arithmetic.sail
    rvfi_dii.sail
    rvfi_dii_v1.sail
    rvfi_dii_v2.sail
    riscv_types_common.sail
    riscv_types_ext.sail
    riscv_types.sail
    # TruISA core vocabulary must exist before any upstream file references
    # Capability / setCapAddrChecked (riscv_pc_access.sail does).
    truisa/truisa_types.sail
    truisa/truisa_cap_common.sail
    riscv_extensions.sail
    riscv_csr_begin.sail
    riscv_convert_invalid_addr.sail
    riscv_callbacks.sail
    riscv_reg_type.sail
    riscv_freg_type.sail
    riscv_vmem_types.sail
    riscv_regs.sail
    riscv_sys_regs_xstatus.sail
    # sits here, not at the end, because it must precede riscv_sys_regs.sail
    truisa/truisa_sys_regs_types.sail
    riscv_sys_regs.sail
    riscv_sys_regs_envcfg.sail
    riscv_pmp_regs.sail
    riscv_pmp_control.sail
    riscv_pc_access.sail
    riscv_vreg_type.sail
    riscv_vext_regs.sail
    riscv_vext_control.sail
    riscv_sys_regs_access.sail
    riscv_sys_regs_access_common.sail
    riscv_sys_exceptions.sail
    riscv_sync_exception.sail
    riscv_zihpm.sail
    riscv_sscofpmf.sail
    riscv_zkr_control.sail
    riscv_zicntr_control.sail
    riscv_softfloat_interface.sail
    riscv_fdext_regs.sail
    riscv_fdext_control.sail
    riscv_smcntrpmf.sail
    riscv_pma.sail
    riscv_svpbmt.sail
    riscv_sys_reservation.sail
    riscv_sys_control.sail
    riscv_platform.sail
    riscv_addr_checks_common.sail
    riscv_addr_checks.sail
    riscv_sstc.sail
    riscv_mem.sail
    riscv_inst_retire.sail
    riscv_vmem_ptw.sail
    riscv_vmem_pte_types.sail
    riscv_vmem_pte_types_ext.sail
    riscv_vmem_pte_validity_ext.sail
    riscv_vmem_pte.sail
    riscv_vmem_pte_ext.sail
    riscv_vmem_tlb.sail
    riscv_vmem.sail
    riscv_vmem_utils.sail
    riscv_vmem_access.sail
    riscv_types_kext.sail
    riscv_zvk_utils.sail
    riscv_insts_begin.sail
    riscv_insts_base.sail
    riscv_insts_zifencei.sail
    riscv_insts_zaamo.sail
    riscv_insts_zalrsc.sail
    riscv_insts_zca.sail
    riscv_insts_mext.sail
    riscv_insts_zicsr.sail
    riscv_insts_hext.sail
    riscv_insts_reserved_fence.sail
    riscv_csr_op.sail
    riscv_insts_fext.sail
    riscv_insts_zcf.sail
    riscv_insts_dext.sail
    riscv_insts_zcd.sail
    riscv_insts_svinval.sail
    riscv_insts_zba.sail
    riscv_insts_zbb.sail
    riscv_insts_zbc.sail
    riscv_insts_zbs.sail
    riscv_insts_zcb.sail
    riscv_insts_zfh.sail
    riscv_insts_zfa.sail
    riscv_insts_zkn.sail
    riscv_insts_zks.sail
    riscv_insts_zbkb.sail
    riscv_insts_zbkx.sail
    riscv_insts_zicond.sail
    riscv_insts_vext_utils.sail
    riscv_insts_vext_fp_utils.sail
    riscv_insts_vext_vset.sail
    riscv_insts_vext_arith.sail
    riscv_insts_vext_fp.sail
    riscv_insts_vext_mem.sail
    riscv_insts_vext_mask.sail
    riscv_insts_vext_vm.sail
    riscv_insts_vext_fp_vm.sail
    riscv_insts_vext_red.sail
    riscv_insts_vext_fp_red.sail
    riscv_insts_zicbom.sail
    riscv_insts_zicboz.sail
    riscv_insts_zawrs.sail
    riscv_insts_zvbb.sail
    riscv_insts_zvbc.sail
    riscv_insts_zvkg.sail
    riscv_insts_zvkned.sail
    riscv_insts_zvknhab.sail
    riscv_insts_zvksed.sail
    riscv_insts_zvksh.sail
    riscv_insts_end.sail
    riscv_insts_zimop.sail
    riscv_insts_zcmop.sail
    riscv_jalr_seq.sail
    riscv_csr_end.sail
    riscv_step_common.sail
    riscv_step_ext.sail
    riscv_decode_ext.sail
    riscv_fetch_rvfi.sail
    riscv_fetch.sail
    riscv_step.sail
    riscv_validate_config.sail
    riscv_device_tree.sail
    riscv_model.sail
    main.sail
)


# The fork's own sources. Order matters here too:
#   types  -> cap_common -> regs -> addr_checks -> inst
set(truisa_own_srcs
    truisa/truisa_regs.sail
    truisa/truisa_addr_checks.sail
    truisa/truisa_inst.sail
)

set(truisa_srcs ${truisa_upstream_srcs} ${truisa_own_srcs})
