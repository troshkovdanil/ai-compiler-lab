#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

THIRD_PARTY_DIR="${REPO_ROOT}/third_party"
DEST_DIR="${THIRD_PARTY_DIR}/rzv_drp-ai_tvm"

RENESAS_REPO_URL="https://github.com/renesas-rz/rzv_drp-ai_tvm.git"

REF="${1:-main}"

log() {
    printf '[renesas] %s\n' "$*"
}

die() {
    printf '[renesas] ERROR: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local cmd="$1"

    command -v "${cmd}" >/dev/null 2>&1 ||
        die "Required command not found: ${cmd}"
}

check_repo_layout() {
    local repo="$1"

    local required_paths=(
        "tutorials"
        "apps"
        "docs"
    )

    local path
    for path in "${required_paths[@]}"; do
        [[ -e "${repo}/${path}" ]] ||
            die "Unexpected repository layout: missing ${path}"
    done
}

require_command git

mkdir -p "${THIRD_PARTY_DIR}"

log "Repository root: ${REPO_ROOT}"
log "Destination:     ${DEST_DIR}"
log "Requested ref:   ${REF}"

if [[ -e "${DEST_DIR}" ]]; then
    [[ -d "${DEST_DIR}/.git" ]] ||
        die "${DEST_DIR} exists but is not a Git repository"

    origin_url="$(
        git -C "${DEST_DIR}" remote get-url origin 2>/dev/null || true
    )"

    [[ "${origin_url}" == "${RENESAS_REPO_URL}" ]] ||
        [[ "${origin_url}" == "https://github.com/renesas-rz/rzv_drp-ai_tvm" ]] ||
        die "Existing repository has unexpected origin: ${origin_url:-<none>}"

    if [[ -n "$(git -C "${DEST_DIR}" status --porcelain)" ]]; then
        die "Existing Renesas checkout has local modifications; refusing to update"
    fi

    log "Existing checkout found"
    log "Fetching updates..."

    git -C "${DEST_DIR}" fetch --tags --prune origin
else
    log "Cloning Renesas DRP-AI TVM..."

    git clone "${RENESAS_REPO_URL}" "${DEST_DIR}"

    git -C "${DEST_DIR}" fetch --tags --prune origin
fi

if git -C "${DEST_DIR}" show-ref \
        --verify \
        --quiet \
        "refs/remotes/origin/${REF}"; then

    log "Checking out branch: ${REF}"

    git -C "${DEST_DIR}" checkout -B "${REF}" "origin/${REF}"

elif git -C "${DEST_DIR}" rev-parse \
        --verify \
        --quiet \
        "${REF}^{commit}" >/dev/null; then

    log "Checking out ref/tag/commit: ${REF}"

    git -C "${DEST_DIR}" checkout --detach "${REF}"

else
    die "Cannot find requested ref: ${REF}"
fi

check_repo_layout "${DEST_DIR}"

log "Checkout verified"
log ""

git -C "${DEST_DIR}" status --short --branch

log ""
log "Revision:"
git -C "${DEST_DIR}" log -1 \
    --format='  commit: %H%n  date:   %cI%n  subject: %s'

log ""
log "Recent tags:"
git -C "${DEST_DIR}" tag \
    --sort=-version:refname |
    head -10 |
    sed 's/^/  /'

log ""
if command -v docker >/dev/null 2>&1; then
    log "Docker: $(docker --version)"

    if docker info >/dev/null 2>&1; then
        log "Docker daemon: accessible"
    else
        log "WARNING: Docker is installed but the daemon is not accessible"
    fi
else
    log "WARNING: Docker is not installed"
fi

log ""
log "Renesas DRP-AI TVM source is ready:"
log "  ${DEST_DIR}"
