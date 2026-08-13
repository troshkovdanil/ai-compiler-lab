#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

OPENBLAS_VERSION="${OPENBLAS_VERSION:-v0.3.30}"

SRC_DIR="${ROOT_DIR}/third_party/OpenBLAS"
BUILD_DIR="${ROOT_DIR}/build/openblas"
INSTALL_DIR="${ROOT_DIR}/build/openblas-install"

LLVM_HOME="${LLVM_HOME:-${ROOT_DIR}/build/llvm-install}"

CC="${LLVM_HOME}/bin/clang"
LLVM_NM="${LLVM_HOME}/bin/llvm-nm"

echo "[openblas] Version: ${OPENBLAS_VERSION}"
echo "[openblas] Source:  ${SRC_DIR}"
echo "[openblas] Build:   ${BUILD_DIR}"
echo "[openblas] Install: ${INSTALL_DIR}"
echo "[openblas] LLVM:    ${LLVM_HOME}"

if [[ ! -x "${CC}" ]]; then
    echo
    echo "[openblas] ERROR: clang not found:"
    echo "  ${CC}"
    echo
    echo "Run scripts/build-llvm.sh first."
    exit 1
fi

if [[ ! -x "${LLVM_NM}" ]]; then
    echo
    echo "[openblas] ERROR: llvm-nm not found:"
    echo "  ${LLVM_NM}"
    exit 1
fi

echo
echo "[openblas] Compiler:"
"${CC}" --version | head -n1

mkdir -p "${ROOT_DIR}/third_party"
mkdir -p "${ROOT_DIR}/build"

#
# Clone / select OpenBLAS version.
#
if [[ ! -d "${SRC_DIR}/.git" ]]; then
    echo
    echo "[openblas] Cloning OpenBLAS..."

    git clone \
        --depth 1 \
        --branch "${OPENBLAS_VERSION}" \
        https://github.com/OpenMathLib/OpenBLAS.git \
        "${SRC_DIR}"
else
    echo
    echo "[openblas] Source already exists."

    current_tag="$(
        git -C "${SRC_DIR}" \
            describe --tags --exact-match HEAD 2>/dev/null || true
    )"

    if [[ "${current_tag}" != "${OPENBLAS_VERSION}" ]]; then
        echo "[openblas] Checking out ${OPENBLAS_VERSION}..."

        git -C "${SRC_DIR}" fetch \
            --depth 1 \
            origin \
            "refs/tags/${OPENBLAS_VERSION}:refs/tags/${OPENBLAS_VERSION}"

        git -C "${SRC_DIR}" checkout \
            --detach \
            "${OPENBLAS_VERSION}"
    fi
fi

#
# Always configure from scratch.
#
# Important:
#
# OpenBLAS distinguishes between:
#
#   NO_CBLAS undefined
#
# and:
#
#   NO_CBLAS=OFF
#
# CBLAS is generated only when NO_CBLAS is not defined at all.
#
rm -rf "${BUILD_DIR}"
rm -rf "${INSTALL_DIR}"

echo
echo "[openblas] Configuring..."

cmake \
    -S "${SRC_DIR}" \
    -B "${BUILD_DIR}" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER="${CC}" \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DBUILD_STATIC_LIBS=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_WITHOUT_LAPACK=ON \
    -DBUILD_WITHOUT_LAPACKE=ON \
    -DBUILD_WITHOUT_CBLAS=OFF \
    -DBUILD_BENCHMARKS=OFF \
    -DNOFORTRAN=ON \
    -DDYNAMIC_ARCH=ON \
    -DUSE_THREAD=OFF

echo
echo "[openblas] Checking configuration..."

#
# NO_CBLAS must not exist in CMakeCache at all.
#
if grep -q '^NO_CBLAS:' "${BUILD_DIR}/CMakeCache.txt"; then
    echo
    echo "[openblas] ERROR: NO_CBLAS unexpectedly exists:"
    grep '^NO_CBLAS:' "${BUILD_DIR}/CMakeCache.txt"

    echo
    echo "NO_CBLAS must remain undefined when building CBLAS."
    exit 1
fi

echo "[openblas] Relevant CMake options:"

grep -E \
    '^(BUILD_WITHOUT_CBLAS|BUILD_WITHOUT_LAPACK|BUILD_WITHOUT_LAPACKE|DYNAMIC_ARCH|USE_THREAD|NOFORTRAN):' \
    "${BUILD_DIR}/CMakeCache.txt" \
    || true

#
# Build.
#
echo
echo "[openblas] Building..."

cmake \
    --build "${BUILD_DIR}" \
    --parallel "$(nproc)"

#
# Verify build artifact.
#
echo
echo "[openblas] Checking build artifact..."

BUILD_LIBRARY="${BUILD_DIR}/lib/libopenblas.a"

if [[ ! -f "${BUILD_LIBRARY}" ]]; then
    echo
    echo "[openblas] ERROR: static OpenBLAS library not found:"
    echo "  ${BUILD_LIBRARY}"
    exit 1
fi

echo "[openblas] Library:"
echo "  ${BUILD_LIBRARY}"

#
# Verify cblas_sgemm is present before installation.
#
echo
echo "[openblas] Checking cblas_sgemm symbol..."

CBLAS_SGEMM_LINE="$(
    "${LLVM_NM}" \
        -A \
        "${BUILD_LIBRARY}" \
        | grep -E '[[:space:]]T[[:space:]]+cblas_sgemm$' \
        | head -n1 \
        || true
)"

if [[ -z "${CBLAS_SGEMM_LINE}" ]]; then
    echo
    echo "[openblas] ERROR: cblas_sgemm symbol not found in:"
    echo "  ${BUILD_LIBRARY}"
    exit 1
fi

echo "[openblas] Found:"
echo "  ${CBLAS_SGEMM_LINE}"

#
# Install.
#
echo
echo "[openblas] Installing..."

cmake \
    --install "${BUILD_DIR}"

#
# Locate installed artifacts.
#
echo
echo "[openblas] Locating installed artifacts..."

HEADER="$(
    find "${INSTALL_DIR}/include" \
        -type f \
        -name 'cblas.h' \
        | head -n1
)"

INSTALLED_LIBRARY="$(
    find "${INSTALL_DIR}/lib" \
        -maxdepth 1 \
        -type f \
        -name 'libopenblas*.a' \
        | head -n1
)"

if [[ -z "${HEADER}" ]]; then
    echo
    echo "[openblas] ERROR: installed cblas.h not found."
    exit 1
fi

if [[ -z "${INSTALLED_LIBRARY}" ]]; then
    echo
    echo "[openblas] ERROR: installed OpenBLAS library not found."
    exit 1
fi

CBLAS_INCLUDE_DIR="$(dirname "${HEADER}")"

echo "[openblas] Header:"
echo "  ${HEADER}"

echo
echo "[openblas] Include directory:"
echo "  ${CBLAS_INCLUDE_DIR}"

echo
echo "[openblas] Installed library:"
echo "  ${INSTALLED_LIBRARY}"

#
# Real CBLAS SGEMM smoke test.
#
# This validates:
#
#   cblas.h
#   compilation
#   linking
#   cblas_sgemm()
#   runtime
#   numerical result
#
echo
echo "[openblas] Running CBLAS SGEMM smoke test..."

SMOKE_DIR="${BUILD_DIR}/smoke"
SMOKE_SOURCE="${SMOKE_DIR}/cblas-smoke.c"
SMOKE_BINARY="${SMOKE_DIR}/cblas-smoke"

mkdir -p "${SMOKE_DIR}"

cat > "${SMOKE_SOURCE}" <<'EOF'
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include <cblas.h>

int main(void)
{
    /*
     * A =
     *
     *   [ 1  2 ]
     *   [ 3  4 ]
     *
     * B =
     *
     *   [ 5  6 ]
     *   [ 7  8 ]
     *
     * C = A * B =
     *
     *   [ 19 22 ]
     *   [ 43 50 ]
     */

    const float A[4] = {
        1.0f, 2.0f,
        3.0f, 4.0f,
    };

    const float B[4] = {
        5.0f, 6.0f,
        7.0f, 8.0f,
    };

    float C[4] = {
        0.0f, 0.0f,
        0.0f, 0.0f,
    };

    cblas_sgemm(
        CblasRowMajor,
        CblasNoTrans,
        CblasNoTrans,

        2,
        2,
        2,

        1.0f,

        A,
        2,

        B,
        2,

        0.0f,

        C,
        2);

    const float expected[4] = {
        19.0f, 22.0f,
        43.0f, 50.0f,
    };

    for (size_t i = 0; i < 4; ++i) {
        const float error =
            fabsf(C[i] - expected[i]);

        if (error > 1.0e-6f) {
            fprintf(
                stderr,
                "CBLAS SGEMM mismatch at %zu: "
                "got=%f expected=%f error=%f\n",
                i,
                C[i],
                expected[i],
                error);

            return EXIT_FAILURE;
        }
    }

    printf(
        "CBLAS SGEMM result: "
        "[%.0f %.0f; %.0f %.0f]\n",
        C[0],
        C[1],
        C[2],
        C[3]);

    return EXIT_SUCCESS;
}
EOF

"${CC}" \
    -O2 \
    -I"${CBLAS_INCLUDE_DIR}" \
    "${SMOKE_SOURCE}" \
    "${INSTALLED_LIBRARY}" \
    -lm \
    -lpthread \
    -o "${SMOKE_BINARY}"

"${SMOKE_BINARY}"

echo
echo "[openblas] CBLAS SGEMM smoke test: OK"

#
# Print interesting symbols for later GEMM investigation.
#
echo
echo "[openblas] Relevant SGEMM symbols:"

"${LLVM_NM}" \
    -A \
    "${INSTALLED_LIBRARY}" \
    | grep -E \
        'cblas_sgemm|[[:space:]]sgemm_(nn|nt|tn|tt)$' \
    | head -30 \
    || true

echo
echo "------------------------------------------------------------"
echo "[openblas] Build PASSED"
echo "------------------------------------------------------------"

echo
echo "Include:"
echo "  ${CBLAS_INCLUDE_DIR}"

echo
echo "Library:"
echo "  ${INSTALLED_LIBRARY}"
