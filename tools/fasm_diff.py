#!/usr/bin/env python3
"""Helper for tools/check_bit.sh.
  fasm_diff.py a.fasm b.fasm out_only_a.fasm   compare canonical feature sets
  fasm_diff.py --count-bits x.frames base.frames   count bits set in x but not in base
"""
import os
import sys
import warnings

if sys.argv[1] == "--count-bits":
    def load(p):
        d = {}
        for line in open(p):
            parts = line.split()
            if len(parts) > 1:
                d[parts[0]] = [int(w, 16) for w in parts[1].split(",")]
        return d
    x, base = load(sys.argv[2]), load(sys.argv[3])   # base = empty FASM (required features)
    bits = 0
    for a, ws in x.items():
        bw = base.get(a, [0] * len(ws))
        bits += sum(bin(w & ~b).count("1") for w, b in zip(ws, bw))
    print(f"configuration bits set by nextpnr-only features: {bits} "
          f"(0 => the bitstream encodes every bit-carrying feature nextpnr emitted)")
    sys.exit(0)

sys.path.insert(0, os.environ["XRAY_DIR"] + "/third_party/fasm")
warnings.filterwarnings("ignore")
import fasm  # noqa: E402


def canon(p):
    s = set()
    for line in fasm.parse_fasm_filename(p):
        if line.set_feature:
            for c in fasm.canonical_features(line.set_feature):
                s.add(fasm.set_feature_to_str(c))
    return s


a, b = canon(sys.argv[1]), canon(sys.argv[2])
print(f"nextpnr FASM features: {len(a)}, decoded from .bit: {len(b)}, common: {len(a & b)}, "
      f"only-in-nextpnr: {len(a - b)}, only-in-bit: {len(b - a)}")
open(sys.argv[3], "w").write("\n".join(sorted(a - b)) + "\n")
kinds = {}
for x in b - a:
    k = x.split(".", 1)[1] if "." in x else x
    k = k.split(".")[-2] + "." + k.split(".")[-1] if k.count(".") >= 1 else k
    kinds[k] = kinds.get(k, 0) + 1
print("  only-in-bit kinds (default/required features bit2fasm reports):",
      ", ".join(f"{k} x{v}" for k, v in sorted(kinds.items(), key=lambda t: -t[1])[:6]))
