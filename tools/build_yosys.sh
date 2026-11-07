#!/bin/bash
# Build yosys from source into $OPT/yosys (pinned tag).
set -euo pipefail
. "$(dirname "$0")/env.sh"
YOSYS_TAG=${YOSYS_TAG:-v0.70}
cd $OPT/src
[ -d yosys ] || git clone https://github.com/YosysHQ/yosys.git
cd yosys
git checkout -q $YOSYS_TAG
git submodule sync --recursive >/dev/null
git submodule update --init --force
cmake -B build -G Ninja . -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ \
  -DCMAKE_PREFIX_PATH=$CONDA_ENV -DCMAKE_INSTALL_PREFIX=$OPT/yosys \
  -DCMAKE_INSTALL_RPATH="$OPT/yosys/lib;$CONDA_ENV/lib" -DCMAKE_BUILD_WITH_INSTALL_RPATH=OFF \
  -DYOSYS_ENABLE_UNIT_TESTS=OFF -DYOSYS_WITHOUT_TCL=ON ${YOSYS_EXTRA_CMAKE:-}
cmake --build build --parallel ${JOBS:-3}
cmake --install build
yosys -V
