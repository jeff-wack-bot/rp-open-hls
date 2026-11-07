#!/bin/bash
# PandA Bambu HLS from source on aarch64, clang/LLVM 19 front end from conda-forge.
set -euo pipefail
. "$(dirname "$0")/env.sh"
BAMBU_TAG=${BAMBU_TAG:-2026.11}
LLVM=$OPT/llvm19          # micromamba create -p $OPT/llvm19 -c conda-forge clang=19 clangxx=19 clangdev=19 llvmdev=19 llvm-tools=19 lld=19
STEP=${1:-all}
cd $OPT/src
[ -d bambu ] || git clone --depth 1 -b $BAMBU_TAG https://github.com/ferrandi/PandA-bambu.git bambu
cd bambu
git submodule update --init --depth 1
export PATH=$LLVM/bin:$PATH
if [ $STEP = all -o $STEP = configure ]; then
cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_PREFIX_PATH="$CONDA_ENV" -DCMAKE_INSTALL_PREFIX=$OPT/bambu \
  -DCMAKE_INSTALL_RPATH="$CONDA_ENV/lib;$LLVM/lib" -DCMAKE_BUILD_RPATH="$CONDA_ENV/lib;$LLVM/lib" \
  -DPANDA_ENABLE_WERROR=OFF -DPANDA_ENABLE_OPT=OFF \
  -DPANDA_MIN_CLANG_VERSION=19.0.0 -DPANDA_MAX_CLANG_VERSION=19.99.0 \
  -DPANDA_LIBBAMBU_COMPILER=I386_CLANG19 -DPANDA_SYNC_PARAMETER_METADATA=OFF \
  ${BAMBU_EXTRA_CMAKE:-}
fi
if [ $STEP = all -o $STEP = build ]; then
cmake --build build --parallel ${JOBS:-2}
cmake --install build
fi
