#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
THIRD_PARTY_DIR="${ROOT_DIR}/third_party"
DEST="${THIRD_PARTY_DIR}/ascendnpu-ir"

ASCENDNPU_IR_URL="${ASCENDNPU_IR_URL:-https://github.com/Ascend/AscendNPU-IR.git}"
ASCENDNPU_IR_REV="${ASCENDNPU_IR_REV:-0e81fb9f843e}"

mkdir -p "${THIRD_PARTY_DIR}"

if [[ ! -d "${DEST}/.git" ]]; then
    echo "[ascendnpu-ir] cloning..."
    git clone "${ASCENDNPU_IR_URL}" "${DEST}"
else
    echo "[ascendnpu-ir] repository already exists:"
    echo "               ${DEST}"
fi

cd "${DEST}"

echo "[ascendnpu-ir] fetching updates..."
git fetch --all --tags

echo "[ascendnpu-ir] checking out ${ASCENDNPU_IR_REV}"
git checkout "${ASCENDNPU_IR_REV}"

echo
echo "[ascendnpu-ir] revision:"
git rev-parse HEAD
git log -1 --oneline

echo
echo "[ascendnpu-ir] done"
