# Source this file: puts the user-space toolchain on PATH.
#   . tools/env.sh
export OPT=${OPT:-$HOME/opt}
export MAMBA_ROOT_PREFIX=$OPT/mamba
# conda env with build deps (cmake, ninja, boost, eigen, bison, flex, python3.12, verilator)
export CONDA_ENV=$OPT/env
export PATH=$OPT/bin:$OPT/yosys/bin:$OPT/nextpnr/bin:$OPT/prjxray/bin:$OPT/iverilog/bin:$OPT/bootgen/bin:$OPT/bambu/bin:$CONDA_ENV/bin:$PATH
# prjxray database (shared by nextpnr chipdb generation and fasm2frames)
export PRJXRAY_DB=$OPT/src/prjxray-db
export XRAY_DIR=$OPT/src/prjxray
export PYTHONPATH=$XRAY_DIR:$XRAY_DIR/third_party/fasm${PYTHONPATH:+:$PYTHONPATH}
