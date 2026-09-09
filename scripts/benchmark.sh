#!/usr/bin/env bash
set -euo pipefail

# 不访问网络/服务、不写节点配置。可传入旧版发布文件，在同一机器做 A/B 比较。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PANEL_FILE="${1:-${ROOT_DIR}/hy2.sh}"
ITERATIONS="${2:-30}"
[[ "${ITERATIONS}" =~ ^[1-9][0-9]{0,3}$ ]] || { echo 'Iterations must be 1-9999' >&2; exit 1; }
export HY2_LIB_ONLY=1
# shellcheck source=../hy2.sh
source "${PANEL_FILE}"
hysteria() { printf 'Version: v2.12.2\nBuildDate: benchmark\n'; }

measure() {
    local label="$1" i
    shift
    TIMEFORMAT="${label}: %3R seconds (${ITERATIONS} iterations)"
    time {
        for ((i = 0; i < ITERATIONS; i++)); do
            "$@" > /dev/null
        done
    }
}

printf 'Panel: %s\nBash: %s\n' "${PANEL_FILE}" "${BASH_VERSION}"
measure version-probe get_hy2_core_version
measure full-template render_singbox_full_template 8.8.8.8 8443 50 200 benchmark bing.com true \
    '47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU='
