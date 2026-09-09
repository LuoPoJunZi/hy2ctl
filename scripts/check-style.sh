#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

error_count=0

report_error() {
    echo "[ERROR] $1"
    error_count=$((error_count + 1))
}

check_text_file() {
    local file="$1"
    local final_byte_lines

    if LC_ALL=C grep -n $'\r$' "${file}" >/dev/null 2>&1; then
        report_error "CRLF line endings are not allowed: ${file}"
    fi

    case "${file}" in
        *.md) ;;
        *)
            if LC_ALL=C grep -nE '[[:blank:]]+$' "${file}" >/dev/null 2>&1; then
                report_error "Trailing whitespace is not allowed: ${file}"
            fi
            ;;
    esac

    if [[ -s "${file}" ]]; then
        final_byte_lines="$(tail -c 1 "${file}" | wc -l | tr -d '[:space:]')"
        if [[ "${final_byte_lines}" -eq 0 ]]; then
            report_error "Missing final newline: ${file}"
        fi
    fi

    case "${file}" in
        *.yml|*.yaml)
            if LC_ALL=C grep -n $'\t' "${file}" >/dev/null 2>&1; then
                report_error "Tabs are not allowed in YAML: ${file}"
            fi
            ;;
    esac
}

while IFS= read -r -d '' file; do
    [[ -f "${file}" ]] || continue
    case "${file}" in
        .editorconfig|.gitattributes|.gitignore|LICENSE|*.md|*.sh|*.bats|*.yml|*.yaml|*.list|tests/fixtures/*)
            check_text_file "${file}"
            ;;
    esac
done < <(git ls-files --cached --others --exclude-standard -z)

if [[ "${error_count}" -ne 0 ]]; then
    echo "[ERROR] Style checks failed with ${error_count} issue(s)."
    exit 1
fi

echo "[OK] Repository text style checks passed."
