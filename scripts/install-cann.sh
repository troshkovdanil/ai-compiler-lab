#!/usr/bin/env bash
set -euo pipefail

CANN_VERSION="${CANN_VERSION:-9.2.0-beta.1}"
INSTALL_PATH="${CANN_INSTALL_PATH:-${HOME}/Ascend}"
DOWNLOAD_DIR="${CANN_DOWNLOAD_DIR:-${HOME}/Downloads}"

PACKAGE="Ascend-cann_${CANN_VERSION}_linux-x86_64.run"
URL="https://ascend-cann-open.obs.cn-north-4.myhuaweicloud.com/CANN/CANN%20${CANN_VERSION}/${PACKAGE}"

echo "[cann] Version:      ${CANN_VERSION}"
echo "[cann] Install path: ${INSTALL_PATH}"
echo "[cann] Package:      ${PACKAGE}"

if [[ "$(uname -m)" != "x86_64" ]]; then
    echo "[cann] ERROR: this script currently supports x86_64 only." >&2
    exit 1
fi

mkdir -p "${DOWNLOAD_DIR}"
cd "${DOWNLOAD_DIR}"

if [[ ! -f "${PACKAGE}" ]]; then
    echo "[cann] Downloading CANN..."
    wget "${URL}" -O "${PACKAGE}"
else
    echo "[cann] Reusing existing ${DOWNLOAD_DIR}/${PACKAGE}"
fi

chmod +x "${PACKAGE}"

echo "[cann] Checking installer integrity..."
"./${PACKAGE}" --check

mkdir -p "${INSTALL_PATH}"

echo
echo "[cann] Installing development toolkit only."
echo "[cann] Huawei EULA will be shown interactively."
echo

"./${PACKAGE}" \
    --devel \
    --whitelist=toolkit \
    --install-path="${INSTALL_PATH}"

SET_ENV="${INSTALL_PATH}/cann/set_env.sh"

if [[ ! -f "${SET_ENV}" ]]; then
    echo "[cann] ERROR: installation completed but ${SET_ENV} was not found." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${SET_ENV}"

echo
echo "[cann] Installed tools:"
for tool in bisheng bishengir-opt bishengir-compile npusim msprof; do
    printf "  %-20s" "${tool}"
    command -v "${tool}" || true
done

echo
echo "[cann] BiSheng:"
bisheng --version | head -5

echo
echo "[cann] AscendNPU-IR:"
bishengir-opt --version

echo
echo "[cann] Installation complete."
echo "[cann] For a new shell:"
echo "       source ${SET_ENV}"

if ! /usr/bin/python3 -c 'import plotly' >/dev/null 2>&1; then
    echo
    echo "[cann] NOTE: Plotly is missing from /usr/bin/python3."
    echo "[cann] npusim execution will work, but HTML report generation will not."
    echo "[cann] On Ubuntu install:"
    echo "       sudo apt install python3-plotly"
fi
