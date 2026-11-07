#!/bin/bash
# Icarus Verilog from source into $OPT/iverilog
set -euo pipefail
. "$(dirname "$0")/env.sh"
IVERILOG_TAG=${IVERILOG_TAG:-v13_0}
cd $OPT/src; [ -d iverilog ] || git clone https://github.com/steveicarus/iverilog.git
cd iverilog && git checkout -q $IVERILOG_TAG
sh autoconf.sh
./configure --prefix=$OPT/iverilog
make -j${JOBS:-2} && make install
iverilog -V 2>&1 | head -1
