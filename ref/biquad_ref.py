#!/usr/bin/env python3
"""Independent bit-exact reference for hls/biquad.c (Python ints, explicit wrap)
and stimulus/expected-value generator for the C and RTL testbenches.

Vector file format (one sample per line, hex, two's complement 32 bit):
    clear x coef0 ... coefN-1 y_expected
biquad1: N=5 (g c0 c1 a10 a11), biquad2: N=10.
"""
import math
import random
import sys

FRAC = 28
M32, M64 = (1 << 32) - 1, (1 << 64) - 1


def s32(v):
    v &= M32
    return v - (1 << 32) if v >> 31 else v


def mac3(a, x, b, y, c, z):
    s = (a * x + b * y + c * z) & M64          # wrap mod 2^64
    return s32(s >> FRAC)                      # bits [59:28], wrap to 32


class Section:
    def __init__(self):
        self.w = self.u = 0

    def step(self, x, g, c0, c1, a10, a11, clear=0):
        if clear:
            self.w = self.u = 0
        y = mac3(g, x, c0, self.w, c1, self.u)
        wn = mac3(g, x, a10, self.w, a11, self.u)
        self.u = s32(self.u + self.w)
        self.w = wn
        return y


def ligo_coefficients(a, b):
    """SOS (a0=1,a1,a2), (b0,b1,b2) -> LIGO form (same as hls_codegen.py)."""
    _, a1, a2 = a
    b0, b1, b2 = b
    g = b0
    a10 = -a1 - 1.0
    a11 = -a2 + a10
    c0 = b1 / b0 - a1
    c1 = b2 / b0 - a2 + c0
    return g, c0, c1, a10, a11


def q28(v):
    r = int(round(v * (1 << FRAC)))
    assert -(1 << 31) <= r < (1 << 31), f"coefficient {v} out of Q4.28 range"
    return r


def lowpass(f0, fs, q):
    """RBJ cookbook 2nd-order lowpass."""
    w0 = 2 * math.pi * f0 / fs
    al = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    a0 = 1 + al
    b = [(1 - cw) / 2 / a0, (1 - cw) / a0, (1 - cw) / 2 / a0]
    a = [1.0, -2 * cw / a0, (1 - al) / a0]
    return a, b


def resonant(f0, fs, q, gain_db):
    """RBJ peaking EQ."""
    A = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * f0 / fs
    al = math.sin(w0) / (2 * q)
    cw = math.cos(w0)
    a0 = 1 + al / A
    b = [(1 + al * A) / a0, -2 * cw / a0, (1 - al * A) / a0]
    a = [1.0, -2 * cw / a0, (1 - al / A) / a0]
    return a, b


FS = 125e6 / 16          # kernel sample rate in the Red Pitaya top (decimate by 16)
SEC0 = [q28(c) for c in ligo_coefficients(*lowpass(50e3, FS, 0.707))]
SEC1 = [q28(c) for c in ligo_coefficients(*resonant(200e3, FS, 2.0, 6.0))]


def stimulus(n, nsec, seed):
    """Yield (clear, x, coefs). Phases: impulse, step, random ADC codes,
    coefficient change, clear, then full-range random x and coefficients
    (exercises the 64-bit and 32-bit wrap paths)."""
    rnd = random.Random(seed)
    coefs = (SEC0 + SEC1)[: 5 * nsec]
    out = []
    out.append((1, 0, coefs))                          # clear
    out.append((0, 8191 << 16, coefs))                 # impulse (full-scale)
    out += [(0, 0, coefs)] * 199
    out += [(0, -8192 << 16, coefs)] * 200             # negative step
    for _ in range(n):                                  # random 14-bit ADC
        out.append((0, rnd.randint(-8192, 8191) << 16, coefs))
    c2 = [c + rnd.randint(-1000, 1000) for c in coefs]  # coefficient update
    for _ in range(200):
        out.append((0, rnd.randint(-8192, 8191) << 16, c2))
    out.append((1, 1 << 16, coefs))                    # clear + impulse
    out += [(0, 0, coefs)] * 100
    for _ in range(n):                                  # anything goes
        cr = [rnd.randint(-(1 << 31), (1 << 31) - 1) for _ in range(5 * nsec)]
        out.append((rnd.random() < 0.02, rnd.randint(-(1 << 31), (1 << 31) - 1), cr))
    return out


def run(stim, nsec):
    secs = [Section() for _ in range(nsec)]
    rows = []
    for clear, x, c in stim:
        v = x
        for i, s in enumerate(secs):
            v = s.step(v, *c[5 * i: 5 * i + 5], clear=clear)
        rows.append((clear, x, c, v))
    return rows


def write(path, rows):
    with open(path, "w") as f:
        for clear, x, c, y in rows:
            f.write(" ".join(f"{v & M32:08x}" for v in [clear, x, *c, y]) + "\n")


def main():
    outdir = sys.argv[1] if len(sys.argv) > 1 else "."
    n = int(sys.argv[2]) if len(sys.argv) > 2 else 2000
    for nsec in (1, 2):
        rows = run(stimulus(n, nsec, seed=1234 + nsec), nsec)
        write(f"{outdir}/vectors_biquad{nsec}.txt", rows)
        print(f"biquad{nsec}: {len(rows)} vectors -> {outdir}/vectors_biquad{nsec}.txt")
    print("SEC0 (g c0 c1 a10 a11, Q4.28):", " ".join(f"0x{v & M32:08x}" for v in SEC0))
    print("SEC1 (g c0 c1 a10 a11, Q4.28):", " ".join(f"0x{v & M32:08x}" for v in SEC1))


if __name__ == "__main__":
    main()
