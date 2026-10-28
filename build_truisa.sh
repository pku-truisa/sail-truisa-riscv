#!/bin/bash
# build_truisa.sh - Build the TruISA model and simulators.
#
# Mirror of build_simulators.sh with -DTRUISA=ON.
# Keep the CMake flags below in sync with build_simulators.sh -- that script has
# only three lines of real logic, so drift is easy to spot but also easy to miss.
#
# NOTE: build_simulators.sh builds the CHERI model (upstream default).
#       This script builds the TruISA model (-DTRUISA=ON).
#
# Output goes to build-truisa/ instead of build/, so the two models can coexist
# and neither clobbers the other.
#
# ⚠️ Requires -DTRUISA=ON support in CMakeLists.txt (see L2) and a truisa file
#    chain in model/CMakeLists.txt (see L3). Without them CMake accepts the
#    variable silently but builds the CHERI model -- i.e. you get the wrong
#    simulator with no error. Check the first line of output for the model name.

set -e
: "${DOWNLOAD_GMP:=TRUE}"
cmake -S . -B build-truisa \
      -DCMAKE_BUILD_TYPE=RelWithDebInfo \
      -DDOWNLOAD_GMP="${DOWNLOAD_GMP}" \
      -DTRUISA=ON
jobs=$( (nproc || sysctl -n hw.ncpu || echo 2) 2>/dev/null)
cmake --build build-truisa -j${jobs}
