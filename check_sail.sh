#!/usr/bin/env bash
# ---------------------------------------------------------------------------------------
# check_sail.sh -- FAST type check: runs the Sail stage only (~45 s), no C, no link.
#
# Why this exists: the full build (build_emulators.sh) takes ~570 s, and almost all of it
# is gcc compiling the ~15 MB of generated C. For answering "does my Sail still
# type-check" none of that is needed -- the Sail stage alone is ~40 s, the source copy ~6 s.
#
#     bash check_sail.sh      ~45 s   Sail type check only   (use this while editing)
#     bash build_emulators.sh ~570 s  full build + simulator (only when explicitly asked)
#
# ⛔ This script does NOT produce a simulator. If you need build/c_emulator/sail_riscv_sim,
#    that is the full build: a deliberate, separate command.
#
# Prerequisites: a WSL tree that has ALREADY been configured once (build/ exists). This
# script only re-syncs sources and re-runs the Sail stage in it; it never configures.
#
# Environment (all overridable -- these are environment quantities, not documented facts,
# same reason proxy ports are never hardcoded in docs):
#   WSL_TREE    configured WSL build tree      (default /home/td/build-layered)
#   WSL_DISTRO  WSL distribution name          (default Ubuntu-22.04)
#   OPAM_BIN    directory holding `sail`       (default /home/td/.opam/5.1.1/bin)
# ---------------------------------------------------------------------------------------
set -u

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
MSYS_NO_PATHCONV=1 wsl.exe -d "$WSL_DISTRO" -- bash -s -- "$WSL_TREE" "$SRC_WSL" "$OPAM_BIN" <<'WSL_EOF'
set -u
T="$1"; SRC="$2"; OPAM="$3"
export PATH="$OPAM:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# 1. Sync sources, keeping the existing build/.
#    ⚠️ The exclude MUST be anchored: a bare 'build' also drops
#    dependencies/softfloat/berkeley-softfloat-3/build/, and the failure then looks like an
#    upstream softfloat error (platform.h missing). Measured twice.
rsync -a --exclude /build --exclude /.git --exclude /sail_smt_cache "$SRC"/ "$T"/

cd "$T" || exit 3

# 2. Force the Sail stage to re-run. rsync preserves mtimes, so an untouched file leaves
#    the old model.c looking up to date -- a silent FALSE PASS, the one failure mode this
#    check must not have. Touching is cheaper than reasoning about mtimes.
touch model/truisa/*.sail model/CMakeLists.txt 2>/dev/null

t0=$(date +%s)
make -C build generated_sail_riscv_model > /tmp/sailcheck.log 2>&1; rc=$?
t1=$(date +%s)

errs=$(grep -cE '^Type error|^Syntax error|not found|already bound' /tmp/sailcheck.log || true)
warns=$(grep -cE 'Warning' /tmp/sailcheck.log || true)

if [ "$rc" -eq 0 ] && [ "$errs" -eq 0 ]; then
  echo "check_sail: OK   rc=0  errs=0  warnings=$warns  $((t1-t0))s"
  exit 0
fi
echo "check_sail: FAIL rc=$rc  errs=$errs  $((t1-t0))s" >&2
echo '--- last 40 lines of the Sail log ---' >&2
tail -40 /tmp/sailcheck.log >&2
exit 1
WSL_EOF
