#!/bin/bash
# openXC7/prjxray (rev used by openXC7 CI): xc7frames2bit + fasm2frames.py.
# Patches mirror openXC7/toolchain-nix nix/prjxray.nix (old CMake minimums, gcc>=13 includes).
set -euo pipefail
. "$(dirname "$0")/env.sh"
PRJXRAY_REV=${PRJXRAY_REV:-54fea88cc61b58b76a83d0be7b1194a5ec1d7d2d}
cd $OPT/src
[ -d prjxray ] || git clone https://github.com/openXC7/prjxray.git
cd prjxray && git checkout -q $PRJXRAY_REV && git submodule update --init --recursive
sed -i 's/VERSION 3.5.0/VERSION 3.14.0/g' CMakeLists.txt
sed -i 's/VERSION 3.0.2/VERSION 3.14.0/g' third_party/gflags/CMakeLists.txt
sed -i 's/VERSION 2.8.12/VERSION 3.14.0/g' third_party/cctz/CMakeLists.txt
grep -q 'Wno-deprecated")' lib/CMakeLists.txt || sed -i '29 itarget_compile_options(libprjxray PUBLIC "-Wno-deprecated")' lib/CMakeLists.txt
cmake -B build -G Ninja . -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DCMAKE_PREFIX_PATH=$CONDA_ENV \
  -DCMAKE_CXX_FLAGS="-include stdint.h -include cstdint -Wno-free-nonheap-object -Wno-error" -DCMAKE_C_FLAGS="-Wno-error"
cmake --build build --target xc7frames2bit bitread --parallel ${JOBS:-2}
mkdir -p $OPT/prjxray/bin && cp build/tools/xc7frames2bit build/tools/bitread $OPT/prjxray/bin/
# python side (fasm2frames): pure-Python textX parser is enough for small designs
pip install -q textx pyyaml simplejson intervaltree ordered-set progressbar2
