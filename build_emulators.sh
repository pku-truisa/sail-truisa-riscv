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
