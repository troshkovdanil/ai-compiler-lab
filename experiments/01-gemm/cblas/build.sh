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

CXX="${LLVM_HOME}/bin/clang++"

OPENBLAS_INSTALL="${ROOT_DIR}/build/openblas-install"
OPENBLAS_LIBRARY="${OPENBLAS_INSTALL}/lib/libopenblas.a"
OPENBLAS_HEADER="${OPENBLAS_INSTALL}/include/openblas/cblas.h"

BUILD_DIR="${SCRIPT_DIR}/build"

echo "[gemm-cblas] Root:     ${ROOT_DIR}"
echo "[gemm-cblas] LLVM:     ${LLVM_HOME}"
echo "[gemm-cblas] OpenBLAS: ${OPENBLAS_INSTALL}"
echo "[gemm-cblas] Build:    ${BUILD_DIR}"

if [[ ! -x "${CXX}" ]]; then
    echo
    echo "[gemm-cblas] ERROR: clang++ not found:"
    echo "  ${CXX}"
    echo
    echo "Run scripts/build-llvm.sh first."
    exit 1
fi

if [[ ! -f "${OPENBLAS_HEADER}" ]]; then
    echo
    echo "[gemm-cblas] ERROR: cblas.h not found:"
    echo "  ${OPENBLAS_HEADER}"
    echo
    echo "Run scripts/build-openblas.sh first."
    exit 1
fi

if [[ ! -f "${OPENBLAS_LIBRARY}" ]]; then
    echo
    echo "[gemm-cblas] ERROR: OpenBLAS library not found:"
    echo "  ${OPENBLAS_LIBRARY}"
    echo
    echo "Run scripts/build-openblas.sh first."
    exit 1
fi

echo
echo "[gemm-cblas] Compiler:"
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
echo "[gemm-cblas] Running..."
echo

"${BUILD_DIR}/cblas-gemm"
