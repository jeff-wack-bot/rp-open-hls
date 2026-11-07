#!/bin/bash
# Fast path: Debian's prebuilt yosys (arm64) unpacked in user space (no sudo).
# Used for all results in README while the from-source v0.70 build ran.
set -euo pipefail
. "$(dirname "$0")/env.sh"
mkdir -p $OPT/deb/dl && cd $OPT/deb/dl
apt-get download yosys=${YOSYS_DEB:-0.66-1} yosys-abc=${YOSYS_DEB:-0.66-1}
for f in yosys_*.deb yosys-abc_*.deb; do dpkg -x $f $OPT/deb/root; done
$OPT/deb/root/usr/bin/yosys -V
