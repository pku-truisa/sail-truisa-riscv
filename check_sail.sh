#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------
# check_sail.sh -- FAST type check. Never builds the simulator.
#
#     bash check_sail.sh            RV64 (default)   ~40 s   Sail stage only, via make
#     bash check_sail.sh rv32       RV32             ~40 s   Sail stage with config/rv32d.json
#     bash check_sail.sh both       RV64 then RV32   ~80 s   both must pass
#     bash build_emulators.sh       full build       ~570 s  only when explicitly asked
#
# ⚠️ Times above are for a warm WSL. On a cold one (WSL just restarted, /mnt/d not yet in
#    cache) the same runs take ~290 s each -- that is the filesystem, not the model.
#
# Why this exists: the full build is ~570 s and almost all of it is gcc compiling the
# ~15 MB of generated C. For "does my Sail still type-check" none of that is needed.
#
# ⚠️ WHY RV32 NEEDS ITS OWN PATH. `xlen` is `type xlen : Int = config base.xlen`
#    (riscv_xlen.sail:10) and the default config says 64. So every ordinary Sail run
#    **only ever type-checks the ELSE branch** of `if xlen == 32 ...` -- the RV32 arm is
#    never compiled unless `--config config/rv32d.json` is passed. The CMake target does
#    not pass it, so `make generated_sail_riscv_model` cannot validate RV32 at all; this
#    script therefore calls `sail` directly for that mode.
#
# ⛔ This script does NOT produce a simulator. If you need build/c_emulator/sail_riscv_sim,
#    that is the full build: a deliberate, separate command.
#
# Prerequisites: a WSL tree that has ALREADY been configured once (build/ exists). This
# script only re-syncs sources and re-runs the Sail stage in it; it never configures.
#
# Environment (all overridable -- environment quantities, not documented facts, same
# reason proxy ports are never hardcoded in docs):
#   WSL_TREE    configured WSL build tree      (default /home/td/build-layered)
#   WSL_DISTRO  WSL distribution name          (default Ubuntu-22.04)
#   OPAM_BIN    directory holding `sail`       (default /home/td/.opam/5.1.1/bin)
# ---------------------------------------------------------------------------------------
set -u

MODE="${1:-rv64}"
case "$MODE" in
  rv64|rv32|both) ;;
  -h|--help) sed -n '3,25p' "$0"; exit 0 ;;
  *) echo "check_sail: unknown mode '$MODE' (use rv64 | rv32 | both)" >&2; exit 2 ;;
esac

WSL_TREE="${WSL_TREE:-/home/td/build-layered}"
WSL_DISTRO="${WSL_DISTRO:-Ubuntu-22.04}"
OPAM_BIN="${OPAM_BIN:-/home/td/.opam/5.1.1/bin}"
# ⚠️ `pwd` in MSYS/Git-Bash returns /d/td/foo, NOT D:/td/foo -- taking cut -c3- of that
# yields /td/foo and silently produces /mnt///td/foo. `pwd -W` gives the Windows form.
# The rsync then fails but the Sail stage still reports OK against the STALE tree, which
# is exactly the false pass this script exists to prevent (measured once).
cd "$(dirname "$0")"
SRC_WIN="$(pwd -W 2>/dev/null || pwd)"
DRIVE="$(printf '%s' "$SRC_WIN" | cut -c1 | tr 'A-Z' 'a-z')"
SRC_WSL="/mnt/$DRIVE$(printf '%s' "$SRC_WIN" | cut -c3-)"

# A configured tree is required: this script refuses to configure one, because configuring
# is exactly the expensive step the caller is trying to avoid.
if ! MSYS_NO_PATHCONV=1 wsl.exe -d "$WSL_DISTRO" -- bash -c "test -d '$WSL_TREE/build'" 2>/dev/null; then
  echo "check_sail: no configured tree at $WSL_TREE (build/ missing)." >&2
  echo "check_sail: run build_emulators.sh there once; this script never configures." >&2
  exit 2
fi

# The body goes over stdin instead of `bash -c "...": two reasons, both measured.
#  1. WSL inherits the Windows PATH, which contains 'Program Files (x86)' -- a stray
#     parenthesis that makes a `bash -c` string a syntax error. So PATH is RESET below,
#     not prepended (sail/NOTES.md records the same trap).
#  2. Quoting a multi-line script through two shells is how insertion bugs happen.
MSYS_NO_PATHCONV=1 wsl.exe -d "$WSL_DISTRO" -- bash -s -- "$WSL_TREE" "$SRC_WSL" "$OPAM_BIN" "$MODE" <<'WSL_EOF'
set -u
T="$1"; SRC="$2"; OPAM="$3"; MODE="$4"
export PATH="$OPAM:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 1. Sync sources, keeping the existing build/.
#    ⚠️ The exclude MUST be anchored: a bare 'build' also drops
#    dependencies/softfloat/berkeley-softfloat-3/build/, and the failure then looks like an
#    upstream softfloat error (platform.h missing). Measured twice.
rsync -a --exclude /build --exclude /.git --exclude /sail_smt_cache "$SRC"/ "$T"/ || exit 3
cd "$T" || exit 3

# 2. Force the Sail stage to re-run. rsync preserves mtimes, so an untouched file leaves
#    the old model.c looking up to date -- a silent FALSE PASS, the one failure mode this
#    check must not have. Touching is cheaper than reasoning about mtimes.
touch model/truisa/*.sail model/CMakeLists.txt 2>/dev/null

report() {   # $1=label $2=rc $3=secs $4=log
  errs=$(grep -cE '^Type error|^Syntax error|not found|already bound' "$4" || true)
  warns=$(grep -cE 'Warning' "$4" || true)
  if [ "$2" -eq 0 ] && [ "$errs" -eq 0 ]; then
    echo "check_sail[$1]: OK    rc=0  errs=0  warnings=$warns  ${3}s"
    return 0
  fi
  echo "check_sail[$1]: FAIL  rc=$2  errs=$errs  ${3}s" >&2
  echo "--- last 40 lines of the Sail log ---" >&2
  tail -40 "$4" >&2
  return 1
}

run_rv64() {
  local t0 t1 rc
  t0=$(date +%s)
  make -C build generated_sail_riscv_model > /tmp/sailcheck-rv64.log 2>&1; rc=$?
  t1=$(date +%s)
  report rv64 "$rc" "$((t1-t0))" /tmp/sailcheck-rv64.log
}

run_rv32() {
  # ⚠️⚠️ `--config config/rv32d.json` does NOT change xlen during TYPE CHECKING -- it only
  # affects the constants in the code that gets generated. Measured 2026-10-31:
  #   --config rv32d.json  -> 102 warnings,  37 s  (identical to RV64 => the RV32 arm was
  #                                                never type-checked; that is a FALSE PASS)
  #   xlen hardcoded to 32 -> 186 warnings, 357 s  (this is the real RV32 check)
  # So the only honest way is to patch xlen in the WSL COPY (never the Windows source,
  # never a git-tracked file in the workspace) and restore it afterwards.
  cp model/riscv_xlen.sail /tmp/xlen.bak || return 1
  sed -i 's|^type xlen : Int = config base.xlen|type xlen : Int = 32|' model/riscv_xlen.sail
  if ! grep -q '^type xlen : Int = 32' model/riscv_xlen.sail; then
    cp /tmp/xlen.bak model/riscv_xlen.sail
    echo "check_sail[rv32]: could not patch xlen (riscv_xlen.sail layout changed?)" >&2
    return 1
  fi
  local t0 t1 rc
  t0=$(date +%s)
  make -C build generated_sail_riscv_model > /tmp/sailcheck-rv32.log 2>&1; rc=$?
  t1=$(date +%s)
  # Restore unconditionally, then touch so the next RV64 run cannot reuse RV32's model.c.
  cp /tmp/xlen.bak model/riscv_xlen.sail
  touch model/riscv_xlen.sail
  report rv32 "$rc" "$((t1-t0))" /tmp/sailcheck-rv32.log
}

run_rv32_old_cfg_unused() {
  # Kept only as a record of the approach that does NOT work (see run_rv32).
  python3 - "$T" <<'PY' || return 1
import sys
T = sys.argv[1]
p = T + '/build/model/CMakeFiles/generated_sail_riscv_model.dir/build.make'
for line in open(p, encoding='utf-8', errors='replace'):
    s = line.strip()
    if s.startswith('cd ') and '/sail ' in s and 'sail_riscv_model' in s:
        s = s.replace('-o ' + T + '/build/sail_riscv_model', '-o /tmp/rv32model')
        s = s.replace('-O --Oconstant-fold',
                      '--config ' + T + '/config/rv32d.json -O --Oconstant-fold', 1)
        open('/tmp/rv32cmd.sh', 'w', encoding='utf-8').write('#!/bin/bash\n' + s + '\n')
        sys.exit(0)
sys.exit('sail recipe not found in ' + p)
PY
}

fail=0
case "$MODE" in
  rv64) run_rv64 || fail=1 ;;
  rv32) run_rv32 || fail=1 ;;
  both) run_rv64 || fail=1; run_rv32 || fail=1 ;;
esac
exit $fail
WSL_EOF
