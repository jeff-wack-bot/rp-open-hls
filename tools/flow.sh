#!/bin/bash
# Open xc7z010 flow: yosys -> nextpnr-himbaechel (xilinx) -> fasm2frames ->
# xc7frames2bit -> bootgen (.bit.bin for fpgautil / fpga_manager).
#
# usage: tools/flow.sh <name> <top> <xdc|-> <verilog files...>
#   env: PART (xc7z010clg400-1), STAGES ("synth pnr bit bin"), SYNTH_OPTS,
#        PNR_OPTS, YOSYS (binary), DEFINES (e.g. "-DKERNEL_NSEC=1")
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
. "$HERE/env.sh"
NAME=$1; TOP=$2; XDC=$3; shift 3
SRCS=$(realpath "$@" | tr "\n" " ")
[ "$XDC" != - ] && XDC=$(realpath "$XDC")
PART=${PART:-xc7z010clg400-1}
DIE=xc7z010
STAGES=${STAGES:-synth pnr bit bin}
YOSYS=${YOSYS:-yosys}
OUT=$HERE/../build/$NAME
mkdir -p "$OUT"; cd "$OUT"
t() { local s=$SECONDS rc=0; "$@" || rc=$?; echo "elapsed $((SECONDS - s)) s" >&2; return $rc; }

if [[ $STAGES == *synth* ]]; then
  echo "== yosys ($($YOSYS -V))"
  t $YOSYS -q -l yosys.log -p "read_verilog -sv ${DEFINES:-} $SRCS; synth_xilinx -flatten -abc9 -arch xc7 -top $TOP ${SYNTH_OPTS:-}; tee -o stat.txt stat; write_json $NAME.json" 2> time_synth.txt
  cat time_synth.txt
  sed -n '/Number of cells/,$p' stat.txt | head -60
fi
if [[ $STAGES == *pnr* ]]; then
  echo "== nextpnr"
  XDCARG=(); [ "$XDC" != - ] && XDCARG=(-o "xdc=$XDC")
  t nextpnr-himbaechel --device $PART --chipdb $OPT/nextpnr/share/chipdb-$DIE.bin \
     --json $NAME.json "${XDCARG[@]}" -o fasm=$NAME.fasm --router router2 \
     --report report.json --log nextpnr.log ${PNR_OPTS:-} > /dev/null 2> time_pnr.txt || { tail -30 nextpnr.log; exit 1; }
  tail -1 time_pnr.txt
  sed -n '/Device utilisation/,/^Info: *$/p' nextpnr.log | head -40
  grep -E "Max frequency for clock|Max delay" nextpnr.log | tail -12
fi
if [[ $STAGES == *bit* ]]; then
  echo "== fasm2frames + xc7frames2bit"
  t python3 $XRAY_DIR/utils/fasm2frames.py --part $PART --db-root $PRJXRAY_DB/zynq7 $NAME.fasm $NAME.frames 2> time_fasm.txt || { cat time_fasm.txt; exit 1; }
  tail -1 time_fasm.txt
  $OPT/prjxray/bin/xc7frames2bit --part_file $PRJXRAY_DB/zynq7/$PART/part.yaml --part_name $PART \
     --frm_file $NAME.frames --output_file $NAME.bit
  ls -la $NAME.bit
fi
if [[ $STAGES == *bin* ]]; then
  echo "== bootgen"
  printf 'all:\n{\n\t%s\n}\n' "$NAME.bit" > $NAME.bif
  bootgen -image $NAME.bif -arch zynq -process_bitstream bin -w on > bootgen.log 2>&1 || { cat bootgen.log; exit 1; }
  ls -la $NAME.bit.bin
fi
