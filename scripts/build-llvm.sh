#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LLVM_VERSION="${LLVM_VERSION:-llvmorg-22.1.8}"

SRC_DIR="${ROOT_DIR}/third_party/llvm-project"
BUILD_DIR="${ROOT_DIR}/build/llvm"
INSTALL_DIR="${ROOT_DIR}/build/llvm-install"

echo "[llvm] Version: ${LLVM_VERSION}"
echo "[llvm] Source:  ${SRC_DIR}"
echo "[llvm] Build:   ${BUILD_DIR}"
echo "[llvm] Install: ${INSTALL_DIR}"

mkdir -p "${ROOT_DIR}/third_party"
mkdir -p "${ROOT_DIR}/build"

if [[ ! -d "${SRC_DIR}/.git" ]]; then
    echo "[llvm] Cloning llvm-project..."
    git clone \
        --depth 1 \
        --branch "${LLVM_VERSION}" \
        https://github.com/llvm/llvm-project.git \
        "${SRC_DIR}"
else
    echo "[llvm] Source already exists."
fi

cmake \
    -S "${SRC_DIR}/llvm" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DLLVM_ENABLE_PROJECTS="clang;mlir" \
    -DLLVM_TARGETS_TO_BUILD="X86;AArch64;ARM;RISCV" \
    -DLLVM_ENABLE_ASSERTIONS=ON \
    -DLLVM_ENABLE_LLD=ON \
    -DLLVM_CCACHE_BUILD=ON

cmake --build "${BUILD_DIR}" --parallel "$(nproc)"

cmake --install "${BUILD_DIR}"

echo
echo "[llvm] Build complete."
echo
echo "Add LLVM to PATH:"
echo
echo "    export PATH=\"${INSTALL_DIR}/bin:\$PATH\""
echo
echo "Verify with:"
echo
echo "    clang --version"
echo "    mlir-opt --version"
echo "    mlir-translate --version"
echo "    llc --version"
