#!/usr/bin/env python3
"""Yosys workaround (build-time copy only, the source repo is untouched):
`initial for (i = ...)` loops that share one module-level `integer i` make
yosys' proc_init fail with "Conflicting initialization values for \\i".
Wrap each such loop in a named block with its own local `integer i`.

usage: localize_initial_loops.py in.v out.v
"""
import re
import sys

src = open(sys.argv[1]).read()
out, pos, n = [], 0, 0
for m in re.finditer(r"\binitial(\s+)for\s*\(", src):
    if m.start() < pos:
        continue
    # end of the for header
    depth, j = 0, m.end() - 1
    while True:
        if src[j] == "(":
            depth += 1
        elif src[j] == ")":
            depth -= 1
            if depth == 0:
                break
        j += 1
    k = j + 1
    rest = src[k:]
    if re.match(r"\s*begin\b", rest):
        # match nested begin/end
        d = 0
        for t in re.finditer(r"\bbegin\b|\bend\b", rest):
            d += 1 if t.group() == "begin" else -1
            if d == 0:
                end = k + t.end()
                break
    else:
        end = src.index(";", k) + 1
    out.append(src[pos:m.start()])
    out.append(f"initial begin : init_loop_{n} integer i;{m.group(1)}" + src[m.start() + len("initial") + len(m.group(1)):end] + " end")
    pos, n = end, n + 1
out.append(src[pos:])
open(sys.argv[2], "w").write("".join(out))
print(f"{sys.argv[1]}: wrapped {n} initial loops", file=sys.stderr)
