#!/bin/bash
# Round-trip check of a generated bitstream:
#  1. decode the .bit back to FASM with prjxray bit2fasm (canonical form);
#  2. compare with the FASM nextpnr emitted;
#  3. features nextpnr wrote that are absent from the decoded bitstream must
#     carry no configuration bits (pseudo-pips, defaults): assemble them alone
#     with fasm2frames and count the bits they would set.
# usage: tools/check_bit.sh build/<name>
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
D=$(realpath "$1"); N=$(basename "$D"); PART=${PART:-xc7z010clg400-1}
cd "$D"
python3 $XRAY_DIR/utils/bit2fasm.py --db-root $PRJXRAY_DB/zynq7 --part $PART \
   --bitread $OPT/prjxray/bin/bitread --canonical $N.bit > $N.rt.fasm 2>/dev/null
python3 "$HERE/fasm_diff.py" $N.fasm $N.rt.fasm only_nextpnr.fasm
python3 $XRAY_DIR/utils/fasm2frames.py --part $PART --db-root $PRJXRAY_DB/zynq7 --sparse \
   only_nextpnr.fasm only_nextpnr.frames 2>/dev/null
: > empty.fasm
python3 $XRAY_DIR/utils/fasm2frames.py --part $PART --db-root $PRJXRAY_DB/zynq7 --sparse \
   empty.fasm empty.frames 2>/dev/null
python3 "$HERE/fasm_diff.py" --count-bits only_nextpnr.frames empty.frames
