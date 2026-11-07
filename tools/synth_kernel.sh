#!/bin/bash
# Kernel-only yosys synthesis (no IO, no P&R) for resource comparison:
# LUT/FF/CARRY/DSP counts and how many DSP48E1 use their internal
# A/B/M/P pipeline registers (yosys only packs registers directly adjacent to
# a DSP; it does not retime trailing registers into a multi-DSP cascade).
# usage: tools/synth_kernel.sh <name> <defines> <files...>
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); . "$HERE/env.sh"
YOSYS=${YOSYS:-$(command -v yosys || echo $OPT/deb/root/usr/bin/yosys)}
NAME=$1; DEFS=$2; shift 2
SRCS=$(realpath "$@" | tr "\n" " ")
OUT=$HERE/../build/kern_$NAME; mkdir -p $OUT; cd $OUT
for f in $SRCS; do cp -n "$(dirname "$f")"/*.mem . 2>/dev/null || true; done
[ -n "$(ls *.mem 2>/dev/null)" ] && [ ! -f array.mem ] && cp "$(ls *.mem | head -1)" array.mem
$YOSYS -q -l yosys.log -p "read_verilog -sv $DEFS $SRCS; synth_xilinx -flatten -abc9 -arch xc7 -noiopad -top kernel_wrap; tee -q -o stat.txt stat; write_json k.json"
python3 - k.json stat.txt "$NAME" <<'EOF'
import json, re, sys
d = json.load(open(sys.argv[1]))
regs = {"AREG": 0, "BREG": 0, "MREG": 0, "PREG": 0}
ndsp = 0
for m in d["modules"].values():
    for c in m["cells"].values():
        if c["type"] == "DSP48E1":
            ndsp += 1
            for r in regs:
                if int(str(c["parameters"].get(r, "0")), 2 if set(str(c["parameters"].get(r, "0"))) <= {"0","1"} else 10):
                    regs[r] += 1
st = open(sys.argv[2]).read()
cells = {m.group(2): int(m.group(1)) for m in re.finditer(r"^\s+(\d+)\s+(?:[\d.]+\s+)?\$?(\w+)\s*$", st, re.M)}
lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]", k))
ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[RSCP]E?", k))
print(f"{sys.argv[3]}: LUT {lut}, FF {ff}, CARRY4 {cells.get('CARRY4',0)}, DSP48E1 {ndsp} "
      f"(with AREG {regs['AREG']}, BREG {regs['BREG']}, MREG {regs['MREG']}, PREG {regs['PREG']})")
EOF
