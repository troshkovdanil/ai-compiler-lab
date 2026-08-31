#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

RENESAS_ROOT="${REPO_ROOT}/third_party/rzv_drp-ai_tvm"

log() {
    printf '[renesas-env] %s\n' "$*"
}

warn() {
    printf '[renesas-env] WARNING: %s\n' "$*" >&2
}

die() {
    printf '[renesas-env] ERROR: %s\n' "$*" >&2
    exit 1
}

check_cmd() {
    local cmd="$1"

    if command -v "${cmd}" >/dev/null 2>&1; then
        printf '  %-16s %s\n' "${cmd}" "$(command -v "${cmd}")"
    else
        printf '  %-16s %s\n' "${cmd}" "MISSING"
    fi
}

check_path() {
    local label="$1"
    local path="$2"

    if [[ -e "${path}" ]]; then
        printf '  %-24s OK  %s\n' "${label}" "${path}"
    else
        printf '  %-24s MISSING  %s\n' "${label}" "${path}"
    fi
}

[[ -d "${RENESAS_ROOT}/.git" ]] ||
    die "Renesas repository not found at ${RENESAS_ROOT}"

log "Repository root:"
log "  ${REPO_ROOT}"

log ""
log "Renesas checkout:"
git -C "${RENESAS_ROOT}" log -1 \
    --format='  commit:  %H%n  date:    %cI%n  subject: %s'

log ""
log "Git status:"
git -C "${RENESAS_ROOT}" status --short --branch |
    sed 's/^/  /'

log ""
log "Host tools:"
check_cmd git
check_cmd python3
check_cmd pip3
check_cmd cmake
check_cmd make
check_cmd gcc
check_cmd g++
check_cmd docker
check_cmd wget
check_cmd curl
check_cmd unzip
check_cmd tar

log ""
log "Host versions:"

python3 --version 2>&1 | sed 's/^/  /'

if command -v cmake >/dev/null 2>&1; then
    cmake --version | head -1 | sed 's/^/  /'
fi

if command -v gcc >/dev/null 2>&1; then
    gcc --version | head -1 | sed 's/^/  /'
fi

if command -v docker >/dev/null 2>&1; then
    docker --version | sed 's/^/  /'

    if docker info >/dev/null 2>&1; then
        log "Docker daemon: accessible"
    else
        warn "Docker is installed, but docker info failed"
    fi
fi

log ""
log "Renesas repository layout:"

check_path "tutorials" "${RENESAS_ROOT}/tutorials"
check_path "apps"      "${RENESAS_ROOT}/apps"
check_path "docs"      "${RENESAS_ROOT}/docs"
check_path "setup"     "${RENESAS_ROOT}/setup"
check_path "obj"       "${RENESAS_ROOT}/obj"

log ""
log "Compiler scripts:"

for script in \
    compile_onnx_model_quant.py \
    compile_tflite_model_quant.py \
    compile_pytorch_model_quant.py \
    compile_exir_model_quant.py
do
    check_path \
        "${script}" \
        "${RENESAS_ROOT}/tutorials/${script}"
done

log ""
log "MERA documentation:"
check_path \
    "About_mera.md" \
    "${RENESAS_ROOT}/docs/About_mera.md"

log ""
log "Searching repository for environment variables..."

for var in SDK TRANSLATOR QUANTIZER TVM_ROOT PRODUCT; do
    printf '\n  [%s]\n' "${var}"

    grep -R \
        --line-number \
        --exclude-dir=.git \
        --exclude='*.so' \
        --exclude='*.a' \
        --exclude='*.bin' \
        --exclude='*.jpg' \
        --exclude='*.png' \
        --exclude='*.onnx' \
        --exclude='*.tflite' \
        "\b${var}\b" \
        "${RENESAS_ROOT}/setup" \
        "${RENESAS_ROOT}/tutorials" \
        "${RENESAS_ROOT}/README.md" \
        2>/dev/null |
        head -20 |
        sed 's/^/    /' ||
        true
done

log ""
log "Current shell environment:"

for var in SDK TRANSLATOR QUANTIZER TVM_ROOT PRODUCT; do
    value="${!var:-}"

    if [[ -n "${value}" ]]; then
        printf '  %-12s %s\n' "${var}" "${value}"
    else
        printf '  %-12s %s\n' "${var}" "<not set>"
    fi
done

log ""
log "Potential installed Renesas packages:"

SEARCH_ROOTS=(
    "${HOME}"
    "/opt"
)

for pattern in \
    '*drp*translator*' \
    '*drp*quantizer*' \
    '*rz*v2h*sdk*'
do
    log "Pattern: ${pattern}"

    found=0

    for root in "${SEARCH_ROOTS[@]}"; do
        [[ -d "${root}" ]] || continue

        while IFS= read -r path; do
            printf '  %s\n' "${path}"
            found=1
        done < <(
            find "${root}" \
                -maxdepth 4 \
                -type d \
                -iname "${pattern}" \
                2>/dev/null |
                head -20
        )
    done

    if [[ "${found}" -eq 0 ]]; then
        printf '  <none found>\n'
    fi
done

log ""
log "Environment inspection complete."
log "No software was installed or modified."
