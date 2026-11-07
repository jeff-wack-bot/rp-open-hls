#!/bin/bash
# C -> Verilog with PandA Bambu for one kernel function.
# usage: hls/run_bambu.sh <top function: biquad1|biquad2> [extra bambu options]
# Output: build/hls_<top>/<top>.v (+ bambu.log)
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/../tools/env.sh"
export PATH=$OPT/llvm19/bin:$PATH
[ -f $OPT/bambu/settings.sh ] && . $OPT/bambu/settings.sh
TOP=$1; shift
OUT=$HERE/../build/hls_$TOP${BAMBU_TAG:-}
mkdir -p "$OUT"; cd "$OUT"
s=$SECONDS
# - xc7z020-1clg484: Bambu's 7-series -1 characterisation (the -YOSYS variant fails with "Unknown backend flow: xilinx/yosys_flow" after writing the same RTL)
#   Same 7-series fabric/speed grade as the 7z010 (only the size differs).
# - 8 ns = the 125 MHz ADC clock domain the kernel lives in.
# - synchronous, active-high reset so static state (w, u) has a defined value.
bambu ${BAMBU_SRCS:-"$HERE/biquad.c"} --top-fname=$TOP \
  --compiler=I386_CLANG19 -O2 \
  --device-name=${BAMBU_DEVICE:-xc7z020-1clg484} --clock-period=${BAMBU_PERIOD:-8} \
  --reset-type=sync --reset-level=high \
  --generate-interface=${BAMBU_IF:-MINIMAL} --top-rtldesign-name=$TOP \
  "$@" 2>&1 | tee bambu.log
echo "bambu elapsed $((SECONDS - s)) s"
ls -la "$OUT"/*.v
