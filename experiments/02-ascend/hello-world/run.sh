#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

CANN_ROOT="${CANN_ROOT:-${HOME}/Ascend/cann}"
NPU_ARCH="${NPU_ARCH:-dav-3510}"
SOC_VERSION="${SOC_VERSION:-Ascend950}"

BUILD_DIR="${SCRIPT_DIR}/out"
BIN="${BUILD_DIR}/hello-world-950"
SIM_OUTPUT="${BUILD_DIR}/sim-output"
SIM_REPORT="${BUILD_DIR}/sim-report"

SET_ENV="${CANN_ROOT}/set_env.sh"

if [[ ! -f "${SET_ENV}" ]]; then
    echo "[ascend-hello] ERROR: CANN environment not found:"
    echo "               ${SET_ENV}"
    echo
    echo "Run ../../../../scripts/install-cann.sh first."
    exit 1
fi

# shellcheck disable=SC1090
source "${SET_ENV}"

for tool in bisheng npusim; do
    if ! command -v "${tool}" >/dev/null; then
        echo "[ascend-hello] ERROR: ${tool} not found after sourcing CANN."
        exit 1
    fi
done

mkdir -p "${BUILD_DIR}"
rm -rf "${SIM_OUTPUT}" "${SIM_REPORT}"

echo "[ascend-hello] Building"
echo "[ascend-hello]   architecture: ${NPU_ARCH}"

bisheng hello_world.asc \
    --npu-arch="${NPU_ARCH}" \
    -o "${BIN}"

echo
file "${BIN}"

echo
echo "[ascend-hello] Running Ascend NPU simulation"
echo "[ascend-hello]   SoC: ${SOC_VERSION}"

npusim record \
    -s "${SOC_VERSION}" \
    -o "${SIM_OUTPUT}" \
    "${BIN}"

ARCHIVE="$(
    find "${SIM_OUTPUT}" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -name 'npusim_*' \
        -print \
        | sort \
        | tail -1
)"

if [[ -z "${ARCHIVE}" ]]; then
    echo "[ascend-hello] ERROR: npusim archive not found." >&2
    exit 1
fi

echo
echo "[ascend-hello] Simulation archive:"
echo "[ascend-hello]   ${ARCHIVE}"

if ! /usr/bin/python3 -c 'import plotly' >/dev/null 2>&1; then
    echo
    echo "[ascend-hello] ERROR: python3 Plotly package is required for reports."
    echo "[ascend-hello] Install it with:"
    echo "               sudo apt install python3-plotly"
    exit 1
fi

echo
echo "[ascend-hello] Generating performance report"

npusim report \
    -e "${ARCHIVE}" \
    -o "${SIM_REPORT}" \
    -n 0

echo
echo "============================================================"
echo " Ascend950 Hello World report"
echo "============================================================"
echo

cat "${SIM_REPORT}/SUMMARY.md"

echo
echo "=== AI Core utilization ==="
python3 -m json.tool \
    "${SIM_REPORT}/results/kernel_0_reports/aicore_utilization.json"

echo
echo "=== Pipeline summary ==="
python3 - <<PY
import json

path = "${SIM_REPORT}/results/kernel_0_reports/summary.json"

with open(path) as f:
    data = json.load(f)

print("kernel_info:")
for key, value in data.get("kernel_info", {}).items():
    print(f"  {key}: {value}")

print()
print("pipelines:")
pipelines = (
    data.get("pipe_utilization", {})
        .get("pipeline_util_summary", {})
)

for name, values in pipelines.items():
    print(f"  {name}: mean={values.get('mean')}")

print()
print("dominant pipeline:")
diag = data.get("top_level_diagnosis", {})
print(f"  {diag.get('dominant_pipeline')}: "
      f"{diag.get('dominant_pipeline_util')}")
PY

echo
echo "[ascend-hello] SUCCESS"
echo
echo "[ascend-hello] HTML report:"
echo "  ${SIM_REPORT}/index.html"
