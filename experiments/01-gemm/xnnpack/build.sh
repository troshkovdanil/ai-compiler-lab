#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

ROOT_DIR="$(
    cd "${SCRIPT_DIR}/../../.."
    pwd
)"

LLVM_HOME="${LLVM_HOME:-${ROOT_DIR}/build/llvm-install}"

CC="${LLVM_HOME}/bin/clang"
CXX="${LLVM_HOME}/bin/clang++"

XNNPACK_DIR="${ROOT_DIR}/third_party/XNNPACK"
XNNPACK_BUILD="${XNNPACK_DIR}/build/local"

BUILD_DIR="${SCRIPT_DIR}/build"

echo "[gemm-xnnpack] Root:    ${ROOT_DIR}"
echo "[gemm-xnnpack] LLVM:    ${LLVM_HOME}"
echo "[gemm-xnnpack] XNNPACK: ${XNNPACK_DIR}"
echo "[gemm-xnnpack] Build:   ${BUILD_DIR}"

if [[ ! -x "${CC}" ]]; then
    echo
    echo "[gemm-xnnpack] ERROR: clang not found:"
    echo "  ${CC}"
    echo
    echo "Run scripts/build-llvm.sh first."
    exit 1
fi

if [[ ! -f "${XNNPACK_BUILD}/libXNNPACK.a" ]]; then
    echo
    echo "[gemm-xnnpack] ERROR: XNNPACK library not found:"
    echo "  ${XNNPACK_BUILD}/libXNNPACK.a"
    echo
    echo "Run scripts/build-xnnpack.sh first."
    exit 1
fi

echo
echo "[gemm-xnnpack] Compiler:"
"${CXX}" --version | head -n1

rm -rf "${BUILD_DIR}"

cmake \
    -S "${SCRIPT_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_COMPILER="${CXX}"

cmake \
    --build "${BUILD_DIR}" \
    --parallel "$(nproc)"

echo
echo "[gemm-xnnpack] Running..."
echo

"${BUILD_DIR}/xnnpack-gemm"
