source ../tinygpu-env/bin/activate
pip install "cocotb==1.7.2"
export PYGPI_PYTHON_BIN="$(which python3)"
export COCOTB_LIB_DIR="$(cocotb-config --lib-dir)"

