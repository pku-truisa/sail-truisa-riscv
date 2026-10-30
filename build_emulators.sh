#!/bin/sh

# Build the TruISA simulator.
#
# This is the ONLY build entry point: this tree builds the TruISA model and nothing
# else (ADR-0024 decision 11). The CHERI chain's source sets are gone from
# model/CMakeLists.txt, so there is no "other model" to select -- TRUISA defaults to
# ON and a tree that asks for OFF is rejected outright.
#
# The guard for that lives in model/CMakeLists.txt (a FATAL_ERROR naming this script),
# not here, and deliberately so: it covers every entry point, including a bare
# `cmake -B build`, whereas a check in this script would only cover people who run
# this script. The cache assertion near the end is a second, narrower check.

set -e
: "${DOWNLOAD_GMP:=TRUE}"

# Dependency completeness (D-168 section 3).
#
# A partial copy of this tree is indistinguishable from a working one until the C build
# reaches softfloat, where it fails with a *source-level* error:
#     .../source/RISCV/s_propagateNaNF128UI.c:39: fatal error: platform.h: No such file
# That reads as "upstream softfloat is broken". It is not: platform.h lives in
# dependencies/softfloat/berkeley-softfloat-3/build/Linux-RISCV-GCC/ and was simply not
# copied. Measured 2026-10-30 on a node with 445 of the 465 tracked files.
#
# Two layers, because some build nodes are plain copies and have no git:
#   1. if this is a git work tree, compare tracked file count with what is on disk;
#   2. always assert the handful of files whose absence produces the misleading error.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  want=$(git ls-files dependencies | wc -l)
  have=$(find dependencies -type f | wc -l)
  if [ "$want" -ne "$have" ]; then
    echo "ERROR: dependencies incomplete: git tracks $want files, $have on disk." >&2
    echo "       Fix with 'git checkout -- dependencies', or re-copy the tree." >&2
    echo "       Left unchecked, this surfaces as a softfloat error about platform.h." >&2
    exit 1
  fi
fi
for need in \
  dependencies/softfloat/CMakeLists.txt \
  dependencies/softfloat/berkeley-softfloat-3/build/Linux-RISCV-GCC/platform.h \
  dependencies/softfloat/berkeley-softfloat-3/source/include/softfloat.h
do
  if [ ! -f "$need" ]; then
    echo "ERROR: missing dependency file: $need" >&2
    echo "       This tree is an incomplete copy; softfloat would fail on platform.h." >&2
    exit 1
  fi
done

cmake -S . -B build -DCMAKE_BUILD_TYPE=RelWithDebInfo -DDOWNLOAD_GMP="${DOWNLOAD_GMP}"

# CMake caches option() values, so a build/ directory configured while the CHERI chain
# still existed keeps TRUISA=OFF regardless of the default. model/CMakeLists.txt now
# fails on that case before we get here; this assertion is belt and braces, and it
# states the post-condition explicitly: what we are about to compile is the TruISA
# model. If it ever fires, the CMake guard has been removed -- put it back there.
if ! grep -qE '^TRUISA:(BOOL|UNINITIALIZED)=ON' build/CMakeCache.txt; then
  echo "ERROR: build/ is not configured for the TruISA model." >&2
  echo "       Found: $(grep '^TRUISA' build/CMakeCache.txt 2>/dev/null || echo '<absent>')" >&2
  echo "       Delete build/ and run ./build_emulators.sh again." >&2
  exit 1
fi

jobs=$( (nproc || sysctl -n hw.ncpu || echo 2) 2>/dev/null)
cmake --build build -j${jobs}
