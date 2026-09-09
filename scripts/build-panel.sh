#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_FILE="${ROOT_DIR}/hy2.sh"
MODE="${1:-write}"

MODULES=(
    "src/bootstrap.sh"
    "src/core/output.sh"
    "src/core/input.sh"
    "src/core/environment.sh"
    "src/core/validation.sh"
    "src/core/encoding.sh"
    "src/core/files.sh"
    "src/core/network.sh"
    "src/core/metadata.sh"
    "src/hysteria/certificate.sh"
    "src/hysteria/permissions.sh"
    "src/hysteria/rollback.sh"
    "src/hysteria/service.sh"
    "src/hysteria/install.sh"
    "src/hysteria/config_write.sh"
    "src/hysteria/config_input.sh"
    "src/hysteria/config_apply.sh"
    "src/hysteria/config.sh"
    "src/clients/hysteria2.sh"
    "src/clients/singbox_outbound.sh"
    "src/clients/singbox_dns.sh"
    "src/clients/singbox_route.sh"
    "src/clients/singbox_full.sh"
    "src/clients/singbox.sh"
    "src/clients/v2rayn.sh"
    "src/clients/summary.sh"
    "src/clients/exports.sh"
    "src/clients/display.sh"
    "src/clients/cheatsheet.sh"
    "src/panel/update.sh"
    "src/operations/diagnostic_context.sh"
    "src/operations/diagnostic_checks.sh"
    "src/operations/diagnostic_report.sh"
    "src/operations/diagnostics.sh"
    "src/operations/backup_create.sh"
    "src/operations/backup_restore.sh"
    "src/operations/backup.sh"
    "src/panel/menu.sh"
    "src/main.sh"
)

fail() {
    echo "[ERROR] $1"
    exit 1
}

validate_manifest() {
    local discovered listed duplicates module

    discovered="$(cd "${ROOT_DIR}" && find src -type f -name '*.sh' -print | sort)"
    listed="$(printf '%s\n' "${MODULES[@]}" | sort)"
    if [[ "${discovered}" != "${listed}" ]]; then
        fail "Source module manifest is incomplete or contains an invalid path"
    fi

    MODULE_PATHS=()
    for module in "${MODULES[@]}"; do
        [[ -s "${ROOT_DIR}/${module}" ]] || fail "Missing source module: ${module}"
        MODULE_PATHS+=("${ROOT_DIR}/${module}")
    done
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
