#!/usr/bin/env bash
set -euo pipefail

PACKAGES=(
    build-essential
    git
    cmake
    ninja-build
    clang
    lld
    ccache
    python3
    python3-venv
    python3-pip
    zlib1g-dev
    libxml2-dev
)

echo "[deps] Checking host OS..."

if [[ ! -r /etc/os-release ]]; then
    echo "[deps] ERROR: /etc/os-release not found."
    exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

echo "[deps] Detected: ${PRETTY_NAME:-unknown}"

if [[ "${ID:-}" != "ubuntu" ]]; then
    echo "[deps] ERROR: This script currently supports Ubuntu only."
    exit 1
fi

if [[ "${VERSION_ID:-}" != "24.04" ]]; then
    echo "[deps] WARNING: Expected Ubuntu 24.04, detected ${VERSION_ID:-unknown}."
    echo "[deps] Continuing anyway."
fi

echo
echo "[deps] Checking required packages..."

missing_packages=()

for package in "${PACKAGES[@]}"; do
    if dpkg-query -W -f='${Status}' "${package}" 2>/dev/null \
        | grep -q "install ok installed"; then
        printf "[deps] %-20s OK\n" "${package}"
    else
        printf "[deps] %-20s MISSING\n" "${package}"
        missing_packages+=("${package}")
    fi
done

if (( ${#missing_packages[@]} > 0 )); then
    echo
    echo "[deps] Installing missing packages:"
    printf '  %s\n' "${missing_packages[@]}"

    sudo apt-get update

    sudo apt-get install -y \
        "${missing_packages[@]}"
else
    echo
    echo "[deps] All required packages are already installed."
fi

echo
echo "[deps] Verifying required tools..."

check_tool()
{
    local tool="$1"

    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "[deps] ERROR: '${tool}' not found in PATH."
        exit 1
    fi

    printf "[deps] %-12s %s\n" \
        "${tool}" \
        "$(command -v "${tool}")"
}

check_tool cmake
check_tool ninja
check_tool clang
check_tool lld
check_tool ccache
check_tool python3
check_tool pip3
check_tool git

echo
echo "------------------------------------------------------------"
echo "[deps] Tool versions"
echo "------------------------------------------------------------"

cmake --version | head -n1
ninja --version
clang --version | head -n1
lld --version | head -n1
ccache --version | head -n1
python3 --version
pip3 --version
git --version

echo
echo "[deps] Checking development headers..."

check_header()
{
    local header="$1"
    local package="$2"

    if dpkg-query -L "${package}" 2>/dev/null \
        | grep -q "/${header}$"; then
        printf "[deps] %-20s OK (%s)\n" \
            "${header}" \
            "${package}"
    else
        printf "[deps] %-20s ERROR (%s)\n" \
            "${header}" \
            "${package}"
        exit 1
    fi
}

check_header "zlib.h" "zlib1g-dev"
check_header "libxml/parser.h" "libxml2-dev"

echo
echo "------------------------------------------------------------"
echo "[deps] Host dependency check PASSED"
echo "------------------------------------------------------------"
