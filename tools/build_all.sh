#!/bin/bash
# Pinned open toolchain for the Red Pitaya (xc7z010clg400-1) on aarch64, user space only.
#   yosys          v0.70 (source; Debian 0.66-1 .deb as fast path: tools/get_yosys_deb.sh)
#   nextpnr        openXC7/nextpnr cf5f7a210fa2 (himbaechel xilinx) + chipdb xc7z010
#   prjxray-db     openXC7/prjxray-db b12466df16ec
#   prjxray        openXC7/prjxray 54fea88cc61b (xc7frames2bit, bitread, fasm2frames.py)
#   fasm           openXC7 fork 2f57ccb1727a (textX fallback parser)
#   bootgen        Xilinx/bootgen xilinx_v2026.2
#   iverilog       v13_0
#   verilator      5.054 (conda-forge)
#   bambu          PandA-bambu 2026.11 + clang/LLVM 19.1.7 (conda-forge)
set -euo pipefail
cd "$(dirname "$0")"
. ./env.sh
mkdir -p $OPT/bin $OPT/src
[ -x $OPT/bin/micromamba ] || curl -Ls https://micro.mamba.pm/api/micromamba/linux-aarch64/latest | tar -xj -C $OPT bin/micromamba
[ -d $CONDA_ENV ] || micromamba create -y -p $CONDA_ENV -c conda-forge python=3.12 cmake ninja libboost-devel eigen \
    bison flex readline libffi pkg-config zlib verilator=5.054 autoconf automake libtool gperf openssl pip
[ -d $OPT/llvm19 ] || micromamba create -y -p $OPT/llvm19 -c conda-forge clang=19 clangxx=19 clangdev=19 llvmdev=19 llvm-tools=19 lld=19
./get_yosys_deb.sh
./build_bootgen.sh
./build_iverilog.sh
./build_prjxray.sh
./build_nextpnr.sh all
./build_bambu.sh all
./build_yosys.sh        # slowest (~2+ h on the Pi 5 with the slang SV front end)
