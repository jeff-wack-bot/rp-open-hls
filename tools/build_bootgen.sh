#!/bin/bash
# Xilinx bootgen (open source, Apache-2.0) for .bit -> .bit.bin
set -euo pipefail
. "$(dirname "$0")/env.sh"
BOOTGEN_TAG=${BOOTGEN_TAG:-xilinx_v2026.2}
cd $OPT/src; [ -d bootgen ] || git clone https://github.com/Xilinx/bootgen.git
cd bootgen && git checkout -q $BOOTGEN_TAG
make -j${JOBS:-2}
mkdir -p $OPT/bootgen/bin && cp build/bin/bootgen $OPT/bootgen/bin/
