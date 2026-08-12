#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

XNNPACK_DIR="${ROOT_DIR}/third_party/XNNPACK"

LLVM_HOME="${LLVM_HOME:-${ROOT_DIR}/build/llvm-install}"

CC="${LLVM_HOME}/bin/clang"
CXX="${LLVM_HOME}/bin/clang++"

if [[ ! -x "${CC}" ]]; then
    echo "[xnnpack] ERROR: clang not found:"
    echo "  ${CC}"
    echo
    echo "Run scripts/build-llvm.sh first."
    exit 1
fi

echo "[xnnpack] LLVM compiler:"
"${CC}" --version | head -n1

mkdir -p "${ROOT_DIR}/third_party"

if [[ ! -d "${XNNPACK_DIR}/.git" ]]; then
    echo "[xnnpack] Cloning XNNPACK..."

    git clone \
        --recursive \
        https://github.com/google/XNNPACK.git \
        "${XNNPACK_DIR}"
else
    echo "[xnnpack] Source already exists."

    git -C "${XNNPACK_DIR}" \
        submodule update --init --recursive
fi

echo
echo "[xnnpack] Building..."

cd "${XNNPACK_DIR}"

./scripts/build-local.sh \
    -DCMAKE_C_COMPILER="${CC}" \
    -DCMAKE_CXX_COMPILER="${CXX}" \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo

echo
echo "[xnnpack] Build complete."
echo "[xnnpack] Build directory:"
echo "  ${XNNPACK_DIR}/build/local"
