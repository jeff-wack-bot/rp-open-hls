#!/usr/bin/env python3
"""Vectors for hls/decim_biquad.c: per line 16 ADC samples (int16) then y (hex)."""
import random, sys, os
sys.path.insert(0, os.path.dirname(__file__))
from biquad_ref import Section, SEC0, SEC1, M32
rnd = random.Random(7)
s0, s1 = Section(), Section()
with open(sys.argv[1], "w") as f:
    for n in range(400):
        adc = [8191] * 16 if n == 0 else ([0] * 16 if n < 100 else [rnd.randint(-8192, 8191) for _ in range(16)])
        x = (sum(adc) << 12) & M32
        x = x - (1 << 32) if x >> 31 else x
        y = s1.step(s0.step(x, *SEC0), *SEC1)
        f.write(" ".join(f"{a & 0xffff:04x}" for a in adc) + f" {y & M32:08x}\n")
