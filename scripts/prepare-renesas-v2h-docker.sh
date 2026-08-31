#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

RENESAS_ROOT="${REPO_ROOT}/third_party/rzv_drp-ai_tvm"
DOWNLOAD_DIR="${REPO_ROOT}/third_party/renesas-downloads"
BUILD_DIR="${REPO_ROOT}/build/renesas-v2h-docker"

PRODUCT="V2H"

log() {
    printf '[renesas-docker] %s\n' "$*"
}

warn() {
    printf '[renesas-docker] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[renesas-docker] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local cmd="$1"

    command -v "${cmd}" >/dev/null 2>&1 ||
        die "Required command not found: ${cmd}"
}

find_single_file() {
    local pattern="$1"

    mapfile -t matches < <(
        find "${DOWNLOAD_DIR}" \
            -maxdepth 1 \
            -type f \
            -name "${pattern}" \
            -print
    )

    if [[ "${#matches[@]}" -eq 0 ]]; then
        return 1
    fi

    if [[ "${#matches[@]}" -gt 1 ]]; then
        printf '%s\n' "${matches[@]}" >&2
        die "Multiple files match: ${pattern}"
    fi

    printf '%s\n' "${matches[0]}"
}

require_command docker
require_command unzip
require_command find
require_command cp
require_command mktemp

[[ -d "${RENESAS_ROOT}/.git" ]] ||
    die "Renesas repository not found: ${RENESAS_ROOT}"

mkdir -p "${DOWNLOAD_DIR}"
mkdir -p "${BUILD_DIR}"

log "Product:        ${PRODUCT}"
log "Renesas repo:   ${RENESAS_ROOT}"
log "Downloads:      ${DOWNLOAD_DIR}"
log "Docker context: ${BUILD_DIR}"
log ""

#
# Find SDK archive.
#

SDK_FILE="$(
    find_single_file 'RTK0EF0180F*.zip' ||
        true
)"

if [[ -z "${SDK_FILE}" ]]; then
    warn "RZ/V2H AI SDK archive not found"
    warn "Expected under:"
    warn "  ${DOWNLOAD_DIR}/RTK0EF0180F*.zip"
    exit 2
fi

#
# Find Translator.
#
# Renesas downloads may arrive as:
#
#   r20ut....-drp-ai-translator-i8.zip
#
# containing:
#
#   DRP-AI_Translator_i8-vX.YY-Linux-x86_64-Install
#
# We also support an already extracted installer.
#

TRANSLATOR_INSTALLER="$(
    find_single_file \
        'DRP-AI_Translator_i8-*-Linux-x86_64-Install' ||
        true
)"

TRANSLATOR_ZIP=""

if [[ -z "${TRANSLATOR_INSTALLER}" ]]; then
    TRANSLATOR_ZIP="$(
        find_single_file '*drp-ai-translator-i8*.zip' ||
            true
    )"
fi

if [[ -z "${TRANSLATOR_INSTALLER}" &&
      -z "${TRANSLATOR_ZIP}" ]]; then

    warn "DRP-AI Translator i8 not found"
    warn "Expected either:"
    warn "  ${DOWNLOAD_DIR}/DRP-AI_Translator_i8-*-Linux-x86_64-Install"
    warn "or:"
    warn "  ${DOWNLOAD_DIR}/*drp-ai-translator-i8*.zip"
    exit 2
fi

log "SDK:"
log "  ${SDK_FILE}"

if [[ -n "${TRANSLATOR_INSTALLER}" ]]; then
    log "Translator installer:"
    log "  ${TRANSLATOR_INSTALLER}"
else
    log "Translator archive:"
    log "  ${TRANSLATOR_ZIP}"
fi

#
# Validate archives before extracting several GB of data.
#

log ""
log "Checking SDK archive..."

if ! unzip -t "${SDK_FILE}" >/dev/null; then
    die "SDK ZIP archive failed integrity check"
fi

log "SDK archive: OK"

if [[ -n "${TRANSLATOR_ZIP}" ]]; then
    log "Checking Translator archive..."

    if ! unzip -t "${TRANSLATOR_ZIP}" >/dev/null; then
        die "Translator ZIP archive failed integrity check"
    fi

    log "Translator archive: OK"
fi

#
# Temporary extraction area.
#

TMP_DIR="$(mktemp -d)"

cleanup() {
    rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

#
# Extract Translator installer if required.
#

if [[ -n "${TRANSLATOR_ZIP}" ]]; then
    log ""
    log "Extracting Translator installer..."

    TRANSLATOR_TMP="${TMP_DIR}/translator"
    mkdir -p "${TRANSLATOR_TMP}"

    unzip -q "${TRANSLATOR_ZIP}" \
        -d "${TRANSLATOR_TMP}"

    TRANSLATOR_INSTALLER="$(
        find "${TRANSLATOR_TMP}" \
            -type f \
            -name 'DRP-AI_Translator_i8-*-Linux-x86_64-Install' \
            -print \
            -quit
    )"

    [[ -n "${TRANSLATOR_INSTALLER}" ]] ||
        die "Could not find DRP-AI Translator installer inside ${TRANSLATOR_ZIP}"
fi

log ""
log "Translator installer:"
log "  $(basename "${TRANSLATOR_INSTALLER}")"

#
# Extract application toolchain installer from the SDK ZIP.
#

log ""
log "Extracting SDK toolchain installer..."

SDK_TMP="${TMP_DIR}/sdk"
mkdir -p "${SDK_TMP}"

unzip -q "${SDK_FILE}" \
    -d "${SDK_TMP}"

TOOLCHAIN_SCRIPT="$(
    find "${SDK_TMP}" \
        -type f \
        -name '*toolchain*.sh' \
        -print \
        -quit
)"

[[ -n "${TOOLCHAIN_SCRIPT}" ]] ||
    die "Could not find *toolchain*.sh inside SDK archive"

log "SDK toolchain installer:"
log "  $(basename "${TOOLCHAIN_SCRIPT}")"

#
# Prepare minimal Docker build context.
#

log ""
log "Preparing Docker build context..."

rm -rf "${BUILD_DIR:?}/"*

[[ -f "${RENESAS_ROOT}/Dockerfile" ]] ||
    die "Dockerfile not found at ${RENESAS_ROOT}/Dockerfile"

cp "${RENESAS_ROOT}/Dockerfile" \
   "${BUILD_DIR}/Dockerfile"

RENESAS_COMMIT="$(
    git -C "${RENESAS_ROOT}" rev-parse HEAD
)"

log "Pinning Docker checkout to:"
log "  ${RENESAS_COMMIT}"

sed -i \
    "/RUN git clone --recursive https:\/\/github.com\/renesas-rz\/rzv_drp-ai_tvm.git  \${TVM_ROOT}/a RUN git -C \${TVM_ROOT} checkout ${RENESAS_COMMIT} && git -C \${TVM_ROOT} submodule update --init --recursive" \
    "${BUILD_DIR}/Dockerfile"

cp "${TRANSLATOR_INSTALLER}" \
   "${BUILD_DIR}/"

cp "${TOOLCHAIN_SCRIPT}" \
   "${BUILD_DIR}/"

chmod +x \
    "${BUILD_DIR}/$(basename "${TRANSLATOR_INSTALLER}")" \
    "${BUILD_DIR}/$(basename "${TOOLCHAIN_SCRIPT}")"

log ""
log "Docker build context:"

find "${BUILD_DIR}" \
    -maxdepth 1 \
    -type f \
    -printf '  %f\n' |
    sort

log ""
log "Docker image name:"
log "  drp-ai_tvm_v2h_image_${USER}"

log ""
log "Preparation complete."
log ""
log "Do NOT build yet."
log "First inspect the output above."
