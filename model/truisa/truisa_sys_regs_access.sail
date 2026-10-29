/*=======================================================================================*
 *  TruISA: the base CSR accessors, minus the xTVT block.
 *
 *  Counterpart: model/riscv_sys_regs_access.sail. This file replaces it in the chain
 *  (CMakeLists.txt, truisa_sys_srcs) rather than editing it, because ADR-0024 section
 *  11.4b forbids changing an original riscv_* file except to delete CHERI code -- and the
 *  xTVT block is not CHERI code, it is an upstream hole (see below).
 *
 *  ⭐ CONTENT: lines 1-59 of the base file, verbatim -- xTVEC[C] / xSCRATCH[C] / xEPC[C] /
 *  xenvcfg / mseccfg. ⛔ The base file's line 60 onward is the xTVT[C] block, which is
 *  NOT copied: it needs `legalize_tvt` (defined nowhere in the vendored tree) and
 *  `register mtvt`/`stvt` (also absent), i.e. the Smtvt extension, which TruISA does not
 *  enable. Nothing references get_mtvt/get_stvt/set_mtvt/set_stvt on this chain, so
 *  dropping them changes nothing that is reachable.
 *
 *  ⚠️ ORDER INSIDE THIS FILE: read_stvec_utvec must come BEFORE get_stvec, which calls it
 *  at what is line 7 of the base copy below. Sail resolves names in file order (see
 *  CODE_STYLE.md fork rule 7), so this is required, not merely defensive.
 *=======================================================================================*/

//  ⚠️ Order matters: read_stvec_utvec is called by get_stvec below.
//
//  The base file calls this but nothing in the vendored tree defines it -- it belongs to
//  an extension that is not in this tree (the same is true of the upstream baseline, so
//  stripping CHERI does not remove the hole).
//
//  This is NOT a stub added to make the checker quiet: the identity IS the architecture
//  here. There is no separate U-mode trap vector in TruISA -- stvec is a single register
//  with base semantics (ADR-0011 decision 2) -- so reading it back is reading the value
//  itself. Contrast with PCC, which was pure scaffolding and was deleted outright.
function read_stvec_utvec(v : xlenbits) -> xlenbits = v

//  ── vvv 以下是 model/riscv_sys_regs_access.sail 第 1-59 行的逐字副本 ──
//  (xTVEC[C] / xSCRATCH[C] / xEPC[C] / xenvcfg / mseccfg)

// This file contains functions for accessing some CSRs. They
// are in a separate file because they are overridden by CHERI.

/******************************* xTVEC[C] *******************************/

function get_mtvec() -> xlenbits = mtvec.bits
function get_stvec() -> xlenbits = read_stvec_utvec(stvec.bits)

function set_mtvec(value : xlenbits) -> unit = {
  mtvec = legalize_tvec(mtvec, convertInvalidAddr(value));
}

function set_stvec(value : xlenbits) -> unit = {
  stvec = legalize_tvec(stvec, convertInvalidAddr(value));
}

/******************************* xSCRATCH[C] *******************************/

function get_mscratch() -> xlenbits = mscratch

function set_mscratch(value : xlenbits) -> unit = {
  mscratch = value;
}

function get_sscratch() -> xlenbits = sscratch

function set_sscratch(value : xlenbits) -> unit = {
  sscratch = value;
}

/******************************* xEPC[C] *******************************/

function get_mepc() -> xlenbits = align_pc(mepc)

function set_mepc(value : xlenbits) -> unit = {
  mepc = legalize_xepc(convertInvalidAddr(value));
}

function get_sepc() -> xlenbits = align_pc(sepc)

function set_sepc(value : xlenbits) -> unit = {
  sepc = legalize_xepc(convertInvalidAddr(value));
}

/******************************* xenvcfg *******************************/

function set_menvcfg(v : bits(64)) -> unit = {
  menvcfg = legalize_menvcfg(menvcfg, mseccfg, v);
}

function set_senvcfg(v : xlenbits) -> unit = {
  senvcfg = legalize_senvcfg(senvcfg, menvcfg, v);
}

/******************************* mseccfg *******************************/

function set_mseccfg(v : bits(64)) -> unit = {
  mseccfg = legalize_mseccfg(mseccfg, v);
}
