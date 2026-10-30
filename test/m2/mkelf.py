#!/usr/bin/env python3
"""mkelf.py -- build a minimal RV64 ELF from raw 32-bit words. No assembler, no linker.

Why this exists (D-169 section 3.2): this machine has no RISC-V toolchain (no gcc, no
clang, no llvm-mc, no binutils), and M2 needs to run `cadd` / `scbnds` / `scaddr` / `sc`.
An assembler was never required to be able to *recognise* those mnemonics -- but since we
would have to install one anyway, we skip it: the code section is a handful of `.word`s,
and this script lays out the ELF64 container around them.

What the Sail loader actually requires (measured against
~/.opam/5.1.1/share/sail/lib/elf.c, not guessed):
  * ELF64, little endian, e_type = ET_EXEC, e_machine = EM_RISCV (243)
  * loading walks PROGRAM headers and copies PT_LOAD by `p_paddr` (elf.c:348-357)
  * `lookup_sym` walks SECTION headers and needs one SHT_SYMTAB plus one SHT_STRTAB that
    is not the section-name table (elf.c:566-600) -- that is what makes `tohost` /
    `begin_signature` / `end_signature` visible; without it HTIF is disabled and the run
    can only be stopped by --inst-limit.

Memory map used here:
    0x8000_0000  .text      program (raw words), entry point
    0x8000_1000  .data      scratch -- pointer landing area for `sc` (16 bytes)
    0x8000_2000  .data      signature area, begin_signature .. end_signature
    0x8000_3000  .data      tohost (8 bytes) -- deliberately NOT 0x8000_1000

⚠️ `tohost` is placed at 0x8000_3000, not at the emulator's default 0x8000_1000: the
tests use 0x8000_1000 as the scratch address for `sc`, and a store there would be eaten
by HTIF instead of landing in memory.

Encodings are computed from the model, not copied from any document:
    truisa_inst.sail  encdec clause for SCBNDS / CADD / SCADDR / SC / LC
    base ISA          LUI / ADDI / SD / LD / JAL
`encode()` refuses to build an instruction whose field would overflow, so a wrong
register number is an error here rather than a mystery on the trace.
"""

import struct
import sys


# ---------------------------------------------------------------- instruction encoding

def _r(opcode, funct3, rd, rs1, rs2, funct7):
    for name, val, hi in (("rd", rd, 31), ("rs1", rs1, 31), ("rs2", rs2, 31),
                          ("funct3", funct3, 7), ("funct7", funct7, 127),
                          ("opcode", opcode, 127)):
        assert 0 <= val <= hi, "%s=%d out of range" % (name, val)
    return (funct7 << 25) | (rs2 << 20) | (rs1 << 15) | (funct3 << 12) | (rd << 7) | opcode


def lui(rd, imm20):
    """LUI rd, imm20.

    ⚠️ On RV64 LUI **sign-extends** the 32-bit result, so any imm20 with bit 19 set
    produces a *negative* 64-bit value:  lui x1, 0x80000  gives 0xFFFFFFFF80000000, not
    0x0000000080000000. That is exactly why the programs below use AUIPC instead --
    see ADDR_BASE and the note on D-170 in the docstring.
    """
    assert 0 <= imm20 <= 0xFFFFF
    return (imm20 << 12) | (rd << 7) | 0x37


def auipc(rd, imm20):
    """AUIPC rd, imm20 -- rd = PC + (imm20 << 12), and PC is 0x8000_0000 here.

    Signed-free: imm20 is added to a 64-bit PC, no 32-bit truncation, so imm20 = 0 gives
    exactly 0x8000_0000 with tag bits 63..57 = 0000000 (FormBare).
    """
    assert 0 <= imm20 <= 0xFFFFF
    return (imm20 << 12) | (rd << 7) | 0x17


def slli(rd, rs1, shamt):
    assert 0 <= shamt <= 63
    return (shamt << 20) | (rs1 << 15) | (0b001 << 12) | (rd << 7) | 0x13


def srli(rd, rs1, shamt):
    assert 0 <= shamt <= 63
    return (shamt << 20) | (rs1 << 15) | (0b101 << 12) | (rd << 7) | 0x13


def li_addr(rd, value):
    """Load a 64-bit absolute address with a *known* bit pattern -- three instructions.

    Both of the obvious one-instruction forms are traps here, and both were hit for real:

      LUI rd, imm20      RV64 sign-extends the 32-bit result, so imm20 with bit 19 set
                         yields a NEGATIVE value: lui x1, 0x80003 -> 0xFFFFFFFF80003000.
                         (Measured: "store/amo-access-fault ... tval 0xFFFFFFFF80003000".)
      AUIPC rd, imm20    pc-relative, so it only lands on the intended page when the
                         instruction happens to sit at the start of that page. In the
                         tail of a program it gave 0x80003028 instead of 0x80003000.

    So: build it as LUI, then clear the upper half -- shift left 32, shift right 32.
        lui rd, 0x80003        -> 0xFFFFFFFF_80003000
        slli rd, rd, 32        -> 0x80003000_00000000
        srli rd, rd, 32        -> 0x00000000_80003000
    Position independent, sign-extension free, and the tag field (bits 63..57) ends up
    as 0000000, i.e. FormBare -- which is what U1/U3 need to start from.
    """
    assert value & 0xFFF == 0, "only page-aligned constants are supported here"
    return [lui(rd, value >> 12), slli(rd, rd, 32), srli(rd, rd, 32)]


def addi(rd, rs1, imm):
    assert -2048 <= imm <= 2047, "addi immediate %d does not fit 12 bits" % imm
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13


def sd(rs2, offset, rs1):
    assert -2048 <= offset <= 2047
    imm = offset & 0xFFF
    return ((imm >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | (0b011 << 12) \
        | ((imm & 0x1F) << 7) | 0x23


def ld(rd, offset, rs1):
    assert -2048 <= offset <= 2047
    return ((offset & 0xFFF) << 20) | (rs1 << 15) | (0b011 << 12) | (rd << 7) | 0x03


def jal(rd, offset):
    """JAL rd, offset -- used as `jal x0, 0` (spin) when HTIF is not taken."""
    imm = offset & 0x1FFFFF
    return (((imm >> 20) & 1) << 31) | (((imm >> 1) & 0x3FF) << 21) \
        | (((imm >> 11) & 1) << 20) | (((imm >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


# --- TruISA, from model/truisa/truisa_inst.sail's encdec clauses ---------------------
#   CADD   : 0b0000110 @ rs2 @ cs1 @ 0b000 @ cd @ 0b0110011   (and rs2 != x0)
#   SCBNDS : 0b0000111 @ rs2 @ cs1 @ 0b000 @ cd @ 0b0110011
#   SCADDR : 0b0000110 @ rs2 @ cs1 @ 0b001 @ cd @ 0b0110011
#   SC     : imm[11:5] @ cs2 @ cs1 @ 0b100 @ imm[4:0] @ 0b0100011
# The capability operand always sits in the *rs1* field of the R-type layout.

def cadd(cd, cs1, rs2):
    assert rs2 != 0, "CADD with rs2 = x0 is not encodable (that word is CMV)"
    return _r(0x33, 0b000, cd, cs1, rs2, 0b0000110)


def scbnds(cd, cs1, rs2):
    return _r(0x33, 0b000, cd, cs1, rs2, 0b0000111)


def scaddr(cd, cs1, rs2):
    return _r(0x33, 0b001, cd, cs1, rs2, 0b0000110)


def sc(cs2, cs1, offset=0):
    assert -2048 <= offset <= 2047
    imm = offset & 0xFFF
    return ((imm >> 5) << 25) | (cs2 << 20) | (cs1 << 15) | (0b100 << 12) \
        | ((imm & 0x1F) << 7) | 0x23


# ---------------------------------------------------------------- ELF container

TEXT_ADDR = 0x80000000
SCRATCH_ADDR = 0x80001000
SIG_ADDR = 0x80002000
TOHOST_ADDR = 0x80003000
SIG_SIZE = 0x40

TEXT_OFF = 0x1000
DATA_OFF = 0x2000
DATA_VADDR = SCRATCH_ADDR
DATA_SIZE = (TOHOST_ADDR - SCRATCH_ADDR) + 8       # covers scratch, signature, tohost


def build(words, symbols):
    """words: list of 32-bit ints. symbols: list of (name, addr) -- tohost is added."""
    text = b"".join(struct.pack("<I", w) for w in words)

    data = bytearray(DATA_SIZE)
    # tohost lives inside the data segment, all zeroes to start with
    data_off = TOHOST_ADDR - DATA_VADDR
    data[data_off:data_off + 8] = struct.pack("<Q", 0)

    # --- section bodies, appended in order after the two PT_LOAD regions
    strtab = b"\x00"
    sym_entries = []
    names = list(symbols) + [("tohost", TOHOST_ADDR),
                             ("begin_signature", SIG_ADDR),
                             ("end_signature", SIG_ADDR + SIG_SIZE)]
    for name, addr in names:
        off = len(strtab)
        strtab += name.encode() + b"\x00"
        sym_entries.append((off, addr))

    symtab = b"\x00" * 24                             # index 0: STN_UNDEF
    for off, addr in sym_entries:
        # st_name, st_info (STB_GLOBAL|STT_OBJECT), st_other, st_shndx(.data=2), st_value, st_size
        symtab += struct.pack("<IBBHQQ", off, (1 << 4) | 1, 0, 2, addr, 0)

    shstrtab = b"\x00.text\x00.data\x00.symtab\x00.strtab\x00.shstrtab\x00"
    sh = {
        ".text": 1, ".data": 7, ".symtab": 14, ".strtab": 22, ".shstrtab": 31,
    }

    off_text = TEXT_OFF
    off_data = DATA_OFF
    off_symtab = off_data + DATA_SIZE
    off_strtab = off_symtab + len(symtab)
    off_shstrtab = off_strtab + len(strtab)
    off_shdr = (off_shstrtab + len(shstrtab) + 7) & ~7
    shnum = 6

    ehdr_size = 64
    phnum = 2
    phoff = ehdr_size

    ehdr = b"\x7fELF" + bytes([2, 1, 1, 0]) + b"\x00" * 8   # ELF64, LE, v1, SysV
    ehdr += struct.pack("<HHIQQQIHHHHHH",
                        2,        # e_type = ET_EXEC
                        243,      # e_machine = EM_RISCV
                        1,        # e_version
                        TEXT_ADDR,  # e_entry
                        phoff, off_shdr,
                        0,        # e_flags
                        ehdr_size, 56, phnum,
                        64, shnum, 5)

    phdrs = b""
    # text: R+X
    phdrs += struct.pack("<IIQQQQQQ", 1, 5, off_text, TEXT_ADDR, TEXT_ADDR,
                         len(text), len(text), 0x1000)
    # data: R+W
    phdrs += struct.pack("<IIQQQQQQ", 1, 6, off_data, DATA_VADDR, DATA_VADDR,
                         DATA_SIZE, DATA_SIZE, 0x1000)

    shdrs = b""
    shdrs += b"\x00" * 64                                            # 0 NULL
    shdrs += struct.pack("<IIQQQQIIQQ", sh[".text"], 1, 6, TEXT_ADDR, off_text,
                         len(text), 0, 0, 16, 0)                     # PROGBITS, AX
    shdrs += struct.pack("<IIQQQQIIQQ", sh[".data"], 1, 3, DATA_VADDR, off_data,
                         DATA_SIZE, 0, 0, 16, 0)                     # PROGBITS, WA
    shdrs += struct.pack("<IIQQQQIIQQ", sh[".symtab"], 2, 0, 0, off_symtab,
                         len(symtab), 4, 1, 8, 24)                   # SYMTAB, link=strtab
    shdrs += struct.pack("<IIQQQQIIQQ", sh[".strtab"], 3, 0, 0, off_strtab,
                         len(strtab), 0, 0, 1, 0)                    # STRTAB
    shdrs += struct.pack("<IIQQQQIIQQ", sh[".shstrtab"], 3, 0, 0, off_shstrtab,
                         len(shstrtab), 0, 0, 1, 0)                  # STRTAB

    img = bytearray(off_shdr + len(shdrs))
    img[0:64] = ehdr
    img[phoff:phoff + len(phdrs)] = phdrs
    img[off_text:off_text + len(text)] = text
    img[off_data:off_data + DATA_SIZE] = bytes(data)
    img[off_symtab:off_symtab + len(symtab)] = symtab
    img[off_strtab:off_strtab + len(strtab)] = strtab
    img[off_shstrtab:off_shstrtab + len(shstrtab)] = shstrtab
    img[off_shdr:off_shdr + len(shdrs)] = shdrs
    return bytes(img)


# ---------------------------------------------------------------- the four programs

X1, X2, X3, X4, X5, X6, X7 = 1, 2, 3, 4, 5, 6, 7
BARE_BASE = 0x80000          # lui imm: x1 = 0x8000_0000, tag bits 63..57 = 0000000


def prog_container():
    """Self-test of the container: one addi, write tohost = 1, then spin.

    Writes `1` to tohost, which is HTIF's "passed" value; the emulator should report
    SUCCESS and exit with 0 without needing --inst-limit.
    """
    return [
        *li_addr(X1, TOHOST_ADDR),  # x1 = 0x8000_3000 (tohost)
        addi(X2, 0, 1),              # x2 = 1
        sd(X2, 0, X1),               # *tohost = 1
        jal(0, 0),                   # spin (in case HTIF is not taken)
    ]


def _tail_store_sig():
    """sc c1 -> scratch, ld it back, sd into the signature area.

    A capability register cannot be read by an `x` instruction: C(r) and X(r) are two
    views of the same register file, and only the integer view is visible to `--trace`.
    So the pointer is stored with `sc` (which writes its 64-bit encoding, tag bits
    included -- ADR-0030), loaded back with `ld`, and dropped into the signature area
    for --test-signature to compare mechanically.
    """
    return [
        *li_addr(X5, SCRATCH_ADDR), # x5 = 0x8000_1000 scratch (slot-external memory)
        sc(X1, X5, 0),               # sc c1, 0(x5)      -> 64-bit encoding in memory
        ld(X6, 0, X5),               # x6 = the 64-bit word
        *li_addr(X7, SIG_ADDR),     # x7 = 0x8000_2000 signature area
        sd(X6, 0, X7),               # signature[0] = x6
        *li_addr(X1, TOHOST_ADDR),  # x1 = tohost
        addi(X2, 0, 1),              # success
        sd(X2, 0, X1),
        jal(0, 0),
    ]


def prog_u1():
    """U1: Bare -> SCBNDS -> Aligned PTR, then CADD +8 inside the slot."""
    return [
        *li_addr(X1, TEXT_ADDR),    # x1 = 0x8000_0000, FormBare (tag = 0000000)
        addi(X2, 0, 12),             # N = 12  (4 KiB slot)
        scbnds(X1, X1, X2),          # c1 <- Aligned PTR, slot [0x8000_0000, 0x8000_0FFF]
        addi(X3, 0, 8),              # delta = 8
        cadd(X1, X1, X3),            # c1.address += 8, still Aligned
    ] + _tail_store_sig()


def prog_u2():
    """U2: push to the top of the slot with SCADDR, then CADD past the end -> poisoned."""
    return [
        *li_addr(X1, TEXT_ADDR),
        addi(X2, 0, 12),
        scbnds(X1, X1, X2),          # Aligned, slot [0x8000_0000, 0x8000_0FFF]
        lui(X4, 0x1),                # x4 = 0x1000
        addi(X4, X4, -8),            # x4 = 0xFF8
        scaddr(X1, X1, X4),          # c1.address = 0x8000_0FF8, still inside the slot
        addi(X3, 0, 8),              # +8 takes it to 0x8000_1000 -> outside
        cadd(X1, X1, X3),
    ] + _tail_store_sig()


def prog_u3():
    """U3: skip SCBNDS -- c1 stays Bare, CADD derives across the whole address space."""
    return [
        *li_addr(X1, TEXT_ADDR),    # Bare, no SCBNDS
        addi(X3, 0, 8),
        cadd(X1, X1, X3),            # ADR-0019: Bare derives everywhere, no trap
    ] + _tail_store_sig()


def prog_u4():
    """U4: the `pac` invariant across CADD -- judgement 5 of m2-baseline.md section 4.

    Skeleton and expectations come from D-176 section 4 (architecture group), not from
    here. Two signature words, both 64-bit encodings of the same capability register,
    taken before and after a CADD that only changes the address:

        [0] written before CADD   -> bits 63..48 (tag + pac) and bits 47..0 (address)
        [8] written after  CADD   -> the *same* bits 63..48, address + 8

    Assertions (D-176 section 4):
        a) bits 63..48 identical in both words  (first-measurement truth 0x98C8, kept)
        b) bits 47..0  of the second = first + 8

    Both are checked as absolute values by run.sh:
        [0] = 0x98C8_0000_8000_0008   (same word U1 already pins)
        [8] = 0x98C8_0000_8000_0010   (high half unchanged, low half + 8)

    ADR-0005: the only places that sign a capability are SCBNDS and DIDW. CADD changes
    the address and nothing else, so a changed `pac` here means CADD went through a
    signing path -- a model defect, not a test bug.
    """
    return [
        *li_addr(X1, TEXT_ADDR),
        addi(X2, 0, 12),
        scbnds(X1, X1, X2),          # c1 <- Aligned PTR, slot [0x8000_0000, 0x8000_0FFF]
        *li_addr(X5, SCRATCH_ADDR),  # x5 = 0x8000_1000
        sc(X1, X5, 0),               # before: c1 -> scratch
        ld(X6, 0, X5),
        *li_addr(X7, SIG_ADDR),      # x7 = 0x8000_2000
        sd(X6, 0, X7),               # signature[0]  <- encoding before CADD
        addi(X3, 0, 8),
        cadd(X1, X1, X3),            # address += 8, tag/pac must not move
        sc(X1, X5, 0),               # after: c1 -> scratch
        ld(X6, 0, X5),
        sd(X6, 8, X7),               # signature[8]  <- encoding after CADD
    ] + _tail_exit()


def _tail_exit():
    """Write 1 to tohost and spin -- the exit tail, without touching the signature."""
    return [
        *li_addr(X1, TOHOST_ADDR),
        addi(X2, 0, 1),
        sd(X2, 0, X1),
        jal(0, 0),
    ]


PROGRAMS = [("container", prog_container), ("u1", prog_u1),
            ("u2", prog_u2), ("u3", prog_u3), ("u4", prog_u4)]


def dump(name, words):
    print("== %s: %d words, entry 0x%08x" % (name, len(words), TEXT_ADDR))
    for i, w in enumerate(words):
        print("   [%2d] 0x%08x" % (i, w))


def main(argv):
    outdir = argv[1] if len(argv) > 1 else "."
    verbose = "--verbose" in argv
    for name, fn in PROGRAMS:
        words = fn()
        if verbose:
            dump(name, words)
        blob = build(words, [("_start", TEXT_ADDR)])
        path = "%s/%s.elf" % (outdir, name)
        with open(path, "wb") as fh:
            fh.write(blob)
        print("%-10s %6d bytes  %2d words  -> %s" % (name, len(blob), len(words), path))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
