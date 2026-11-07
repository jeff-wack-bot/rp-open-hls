#!/bin/bash
# openXC7/nextpnr (himbaechel xilinx uarch) + chipdb for the Red Pitaya die (xc7z010).
# Pins follow openXC7/toolchain-nix (nix/nextpnr.nix, nix/prjxray-db.nix).
set -euo pipefail
. "$(dirname "$0")/env.sh"
NEXTPNR_REV=${NEXTPNR_REV:-cf5f7a210fa2deac8b6967c43acf426298c8e1a6}
PRJXRAY_DB_REV=${PRJXRAY_DB_REV:-b12466df16ecb6fe194fe436ec020ac08d32d61e}
DIE=${DIE:-xc7z010}
STEP=${1:-all}   # all | chipdb-bba | binary | chipdb-bin
cd $OPT/src
[ -d prjxray-db ] || git clone https://github.com/openXC7/prjxray-db.git
git -C prjxray-db checkout -q $PRJXRAY_DB_REV
[ -d nextpnr-openxc7 ] || git clone https://github.com/openXC7/nextpnr.git nextpnr-openxc7
cd nextpnr-openxc7
git checkout -q $NEXTPNR_REV
git submodule update --init --recursive
mkdir -p $OPT/nextpnr/bin $OPT/nextpnr/share
if [ $STEP = all -o $STEP = chipdb-bba ]; then
  # ~1-2 GB of Python, single-threaded
  python3 himbaechel/uarch/xilinx/gen/xilinx_gen.py --xray $PRJXRAY_DB/zynq7 --device $DIE --bba $OPT/nextpnr/share/$DIE.bba
fi
if [ $STEP = all -o $STEP = binary ]; then
  cmake -B build -G Ninja . -DARCH=himbaechel -DHIMBAECHEL_UARCH=xilinx \
    -DBUILD_GUI=OFF -DBUILD_PYTHON=OFF -DBUILD_TESTS=OFF -DUSE_OPENMP=ON \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH=$CONDA_ENV \
    -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
    -DCMAKE_BUILD_RPATH=$CONDA_ENV/lib \
    -DHIMBAECHEL_PRJXRAY_DB=$PRJXRAY_DB -DHIMBAECHEL_XILINX_DEVICES=
  cmake --build build --target nextpnr-himbaechel bbasm --parallel ${JOBS:-2}
  cp build/nextpnr-himbaechel build/bba/bbasm $OPT/nextpnr/bin/
  sed "s|^BIN=\"nextpnr-himbaechel\"|BIN=\"$OPT/nextpnr/bin/nextpnr-himbaechel\"|" .github/scripts/nextpnr-xilinx-shim.sh > $OPT/nextpnr/bin/nextpnr-xilinx
  chmod +x $OPT/nextpnr/bin/nextpnr-xilinx
fi
if [ $STEP = all -o $STEP = chipdb-bin ]; then
  bbasm -l $OPT/nextpnr/share/$DIE.bba $OPT/nextpnr/share/chipdb-$DIE.bin
  rm -f $OPT/nextpnr/share/$DIE.bba
fi
