#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

TVM_VERSION="${TVM_VERSION:-v0.26.0}"

LLVM_HOME="${LLVM_HOME:-${ROOT_DIR}/build/llvm-install}"
LLVM_CONFIG="${LLVM_HOME}/bin/llvm-config"

SRC_DIR="${ROOT_DIR}/third_party/tvm"
BUILD_DIR="${SRC_DIR}/build"
VENV_DIR="${ROOT_DIR}/.venv"

if [[ ! -x "${LLVM_CONFIG}" ]]; then
    echo "error: llvm-config not found:"
    echo "  ${LLVM_CONFIG}"
    echo
    echo "Run scripts/build-llvm.sh first."
    exit 1
fi

echo "[tvm] Version: ${TVM_VERSION}"
echo "[tvm] LLVM:    $(${LLVM_CONFIG} --version)"
echo "[tvm] Source:  ${SRC_DIR}"
echo "[tvm] Build:   ${BUILD_DIR}"

mkdir -p "${ROOT_DIR}/third_party"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    echo "[tvm] Cloning TVM..."
    git clone \
        --recursive \
        --depth 1 \
        --branch "${TVM_VERSION}" \
        https://github.com/apache/tvm.git \
        "${SRC_DIR}"
else
    echo "[tvm] Source already exists."
    git -C "${SRC_DIR}" submodule update --init --recursive
fi

rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"

cp "${SRC_DIR}/cmake/config.cmake" \
   "${BUILD_DIR}/config.cmake"

cat >> "${BUILD_DIR}/config.cmake" <<EOF

set(CMAKE_BUILD_TYPE RelWithDebInfo)

set(USE_LLVM "${LLVM_CONFIG} --ignore-libllvm --link-static")
set(HIDE_PRIVATE_SYMBOLS ON)

set(USE_CUDA OFF)
set(USE_VULKAN OFF)
set(USE_OPENCL OFF)
set(USE_METAL OFF)
set(USE_ROCM OFF)

set(USE_CUBLAS OFF)
set(USE_CUDNN OFF)
set(USE_CUTLASS OFF)
EOF

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja

cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

if [[ ! -d "${VENV_DIR}" ]]; then
    python3 -m venv "${VENV_DIR}"
fi

source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip

python -m pip install \
    numpy \
    cython

python -m pip install \
    "${SRC_DIR}/3rdparty/tvm-ffi"

export TVM_LIBRARY_PATH="${BUILD_DIR}"

python -m pip install -e "${SRC_DIR}"

python - <<'PY'
import tvm

print()
print("TVM:", tvm.__version__)
print("TVM Python:", tvm.__file__)
print()

for key, value in tvm.support.libinfo().items():
    if key in ("GIT_COMMIT_HASH", "USE_LLVM", "LLVM_VERSION"):
        print(f"{key}: {value}")
PY

echo
echo "[tvm] Build complete."
echo
echo "Use:"
echo
echo "    source ${VENV_DIR}/bin/activate"
echo "    export TVM_LIBRARY_PATH=${BUILD_DIR}"
