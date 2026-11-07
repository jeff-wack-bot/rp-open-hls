#!/bin/bash
# Reproduce every result in README.md (after tools/build_all.sh).
set -euo pipefail
cd "$(dirname "$0")/.."
R=$PWD; . tools/env.sh
mkdir -p build/vec
echo "### reference model + C kernel"
python3 -I ref/biquad_ref.py build/vec 2000
python3 -I ref/decim_vectors.py build/vec/vectors_decim.txt
gcc -O2 -Wall -o build/check_c ref/check_c.c hls/biquad.c
build/check_c 1 build/vec/vectors_biquad1.txt
build/check_c 2 build/vec/vectors_biquad2.txt

echo "### HLS (Bambu)"
hls/run_bambu.sh biquad1 > /dev/null
hls/run_bambu.sh biquad2 > /dev/null
BAMBU_SRCS="$R/hls/decim_biquad.c $R/hls/biquad.c" BAMBU_IF=INFER hls/run_bambu.sh decim_biquad2 > /dev/null

echo "### bit-exact RTL simulation (iverilog)"
for n in 1 2; do
  ( cd build/hls_biquad$n; D=; [ $n = 1 ] && D=-DKERNEL_NSEC1
    iverilog -g2012 $D -o tb -P tb_kernel.NSEC=$n $R/sim/tb_kernel.v $R/rtl/kernel_bambu.v biquad$n.v panda_libtech.v
    vvp -n tb +VEC=../vec/vectors_biquad$n.txt | grep RESULT
    vvp -n tb +VEC=../vec/vectors_biquad$n.txt +GAP=7 | grep RESULT )
  iverilog -g2012 -DKERNEL_NSEC=$n -o build/tb_hand$n -P tb_kernel.NSEC=$n sim/tb_kernel.v rtl/kernel_hand.v
  vvp -n build/tb_hand$n +VEC=build/vec/vectors_biquad$n.txt | sed 's/^RESULT/RESULT (hand RTL)/' | grep RESULT
done
( cd build/hls_decim_biquad2
  iverilog -g2012 -o tb $R/sim/tb_decim.v decim_biquad2.v panda_libtech.v && vvp -n tb | grep RESULT )
( cd build/hls_biquad2
  iverilog -g2012 -o tb_top $R/sim/tb_top.v $R/sim/prims_sim.v $R/rtl/rp_top.v $R/rtl/axi_regs.v \
     $R/rtl/kernel_bambu.v biquad2.v panda_libtech.v && vvp -n tb_top | grep -E "RESULT|LATENCY|OVERRUNS" )

echo "### Red Pitaya tops -> .bit/.bit.bin"
TOP=(rtl/rp_top.v rtl/axi_regs.v)
tools/flow.sh top_bambu2 rp_top constraints/rp_125_14.xdc "${TOP[@]}" rtl/kernel_bambu.v \
   build/hls_biquad2/biquad2.v build/hls_biquad2/panda_libtech.v > build/top_bambu2.flow.log 2>&1
DEFINES=-DKERNEL_NSEC1 tools/flow.sh top_bambu1 rp_top constraints/rp_125_14.xdc "${TOP[@]}" rtl/kernel_bambu.v \
   build/hls_biquad1/biquad1.v build/hls_biquad1/panda_libtech.v > build/top_bambu1.flow.log 2>&1
tools/flow.sh top_hand rp_top constraints/rp_125_14.xdc "${TOP[@]}" rtl/kernel_hand.v > build/top_hand.flow.log 2>&1
tools/check_bit.sh build/top_bambu2 | tail -1

echo "### bonus: cds_io2 (rp-frontend-bot/fpga/rtl, read-only) through yosys + nextpnr"
S=${CDS_IO2_RTL:-/home/bot/repos/rp-frontend-bot/fpga/rtl}; P=build/cds_io2_src; mkdir -p $P
cp $S/*.vh $S/cds_io2_tap.v $S/cds_io2_strobe.v $P/
python3 -I bonus/localize_initial_loops.py $S/cds_io2.v $P/cds_io2.v
PNR_OPTS=--timing-allow-fail STAGES="synth pnr" DEFINES="-I$(realpath $P)" tools/flow.sh cds_io2 cds_io2_bench bonus/cds_io2_bench.xdc \
   bonus/cds_io2_bench.v $P/cds_io2.v $P/cds_io2_tap.v $P/cds_io2_strobe.v > build/cds_io2.flow.log 2>&1

echo "### probe: are DSP48E1 paths timed by nextpnr?"
STAGES="synth pnr" tools/flow.sh dsp_probe dsp_timing_probe sim/probe/probe.xdc sim/probe/dsp_timing_probe.v > build/dsp_probe.flow.log 2>&1

echo "### reports"
python3 -I tools/report.py build/top_bambu1 build/top_bambu2 build/top_hand build/cds_io2 build/dsp_probe
tools/synth_kernel.sh bambu1 "-DKERNEL_NSEC1" rtl/kernel_bambu.v build/hls_biquad1/biquad1.v build/hls_biquad1/panda_libtech.v 2>/dev/null
tools/synth_kernel.sh bambu2 "" rtl/kernel_bambu.v build/hls_biquad2/biquad2.v build/hls_biquad2/panda_libtech.v 2>/dev/null
tools/synth_kernel.sh hand1 "-DKERNEL_NSEC=1" rtl/kernel_hand.v 2>/dev/null
tools/synth_kernel.sh hand2 "" rtl/kernel_hand.v 2>/dev/null
