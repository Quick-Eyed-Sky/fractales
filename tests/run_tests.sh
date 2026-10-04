#!/bin/sh
# Runs the tests that need no Mac: the high-precision core, and the GPU kernel executed on the
# CPU and compared with 113-bit arithmetic. Needs gcc with libquadmath (Linux) .
#   sh tests/run_tests.sh [folder for the test pictures]
set -e
cd "$(dirname "$0")/.."
OUT="${TMPDIR:-/tmp}/fractales-tests"; mkdir -p "$OUT"
gcc -O2 -Wall -Wextra -Isource tests/test_core.c source/FractalCore.c -lquadmath -lm -o "$OUT/test_core"
"$OUT/test_core"
g++ -O2 -std=gnu++17 -Wall -Wno-attributes -Itests/shim -Isource tests/test_shader.cpp source/FractalCore.c -lquadmath -o "$OUT/test_shader"
"$OUT/test_shader" ${1:+"$1"}
