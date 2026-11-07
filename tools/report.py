#!/usr/bin/env python3
"""Summarise a tools/flow.sh build dir: yosys cell counts (LUT = LUT1..6 cells,
i.e. real LUT6 sites before packing) and nextpnr's final Fmax per clock.
NOTE: nextpnr-himbaechel/xilinx has no DSP48E1 timing arcs, so paths through
DSPs are not included in its Fmax (see README).

usage: report.py build/<name> [...]
"""
import re
import sys

for d in sys.argv[1:]:
    stat = open(f"{d}/stat.txt").read()
    cells = {}
    # last (top / flattened) cell table in the stat output
    for m in re.finditer(r"^\s+(\d+)\s+(?:[\d.]+\s+)?\$?(\w+)\s*$", stat, re.M):
        cells[m.group(2)] = int(m.group(1))
    lut = sum(v for k, v in cells.items() if re.fullmatch(r"LUT[1-6]", k))
    ff = sum(v for k, v in cells.items() if re.fullmatch(r"FD[RSCP]E?", k))
    lutram = sum(v for k, v in cells.items() if k.startswith("RAM") and not k.startswith("RAMB"))
    dsp = cells.get("DSP48E1", 0)
    b36, b18 = cells.get("RAMB36E1", 0), cells.get("RAMB18E1", 0)
    log = open(f"{d}/nextpnr.log").read()
    fmax = {}
    for m in re.finditer(r"Max frequency for clock '([^']+)': ([\d.]+) MHz \((PASS|FAIL) at ([\d.]+) MHz\)", log):
        fmax[m.group(1)] = (float(m.group(2)), m.group(3), float(m.group(4)))  # last = post-route
    print(f"{d}: LUT {lut}, FF {ff}, LUTRAM {lutram}, CARRY4 {cells.get('CARRY4', 0)}, "
          f"DSP48E1 {dsp}, RAMB36 {b36}, RAMB18 {b18}")
    for clk, (f, st, tgt) in fmax.items():
        name = clk if len(clk) < 60 else clk[:28] + "..." + clk[-28:]
        print(f"    Fmax {name}: {f:.1f} MHz ({st} at {tgt:.0f} MHz)")
