#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/hy2.sh"
MODE="${1:-write}"

# shellcheck source=lib/source-manifest.sh
source "${ROOT_DIR}/scripts/lib/source-manifest.sh"

fail() {
    echo "[ERROR] $1"
    exit 1
}

validate_manifest() {
    local duplicates
    load_panel_modules "${ROOT_DIR}" || fail "Invalid source module manifest"
    duplicates="$(grep -hE '^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{' "${MODULE_PATHS[@]}" |
        sed -E 's/\(\).*//' | sort | uniq -d)"
    if [[ -n "${duplicates}" ]]; then
        printf '[ERROR] Duplicate function definitions:\n%s\n' "${duplicates}"
        exit 1
    fi
}

build_panel() {
    local target="$1"

    # 源码遵循 LF 与末尾换行约定；单次读取全部模块，保留模块间一个空行。
    awk 'FNR == 1 && NR > 1 { print "" } { print }' "${MODULE_PATHS[@]}" > "${target}"

    bash -n "${target}" || fail "Generated panel failed Bash syntax validation"
    grep -Fq 'sh_ver="v' "${target}" || fail "Generated panel is missing sh_ver"
    grep -Fq 'main_menu()' "${target}" || fail "Generated panel is missing main_menu"
}

validate_manifest

case "${MODE}" in
    write)
        tmp_file="$(mktemp "${ROOT_DIR}/.hy2-build.XXXXXX")"
        trap 'rm -f "${tmp_file}"' EXIT
        build_panel "${tmp_file}"
        chmod +x "${tmp_file}"
        mv -f "${tmp_file}" "${OUTPUT_FILE}"
        trap - EXIT
        echo "[OK] Generated ${OUTPUT_FILE} from ${#MODULES[@]} source modules."
        ;;
    --check)
        tmp_file="$(mktemp)"
        trap 'rm -f "${tmp_file}"' EXIT
        build_panel "${tmp_file}"
        if ! cmp -s "${tmp_file}" "${OUTPUT_FILE}"; then
            fail "hy2.sh is out of date. Run: bash scripts/build-panel.sh"
        fi
        echo "[OK] Generated panel is in sync with source modules."
        ;;
    *)
        fail "Usage: $0 [write|--check]"
        ;;
esac
