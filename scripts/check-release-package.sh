#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=lib/source-manifest.sh
source "${ROOT_DIR}/scripts/lib/source-manifest.sh"

fail() {
    echo "[ERROR] $1"
    exit 1
}

assert_list_contains() {
    local list_file="$1"
    local expected="$2"
    if ! grep -Fxq -- "${expected}" "${list_file}"; then
        fail "Release package missing required path: ${expected}"
    fi
}

assert_list_not_contains() {
    local list_file="$1"
    local unexpected="$2"
    if grep -Fxq -- "${unexpected}" "${list_file}"; then
        fail "Release package contains local-only path: ${unexpected}"
    fi
}

check_forbidden_paths() {
    local list_file="$1"
    if grep -Eq '(^|/)lib/hy2(/|$)|(^|/)scripts/measure-memory\.sh$' "${list_file}"; then
        fail "Release package contains reverted PR #2 modular files."
    fi
    if grep -Eq '(^|/)\.codex-ci-check|(^|/)\.codex-ci-check.*\.tar$' "${list_file}"; then
        fail "Release package contains local Codex check artifacts."
    fi
}

check_required_paths() {
    local list_file="$1"
    assert_list_contains "${list_file}" "hy2.sh"
    assert_list_contains "${list_file}" "install.sh"
    assert_list_contains "${list_file}" "README.md"
    assert_list_contains "${list_file}" "CHANGELOG.md"
    assert_list_contains "${list_file}" "LICENSE"
    assert_list_contains "${list_file}" ".editorconfig"
    assert_list_contains "${list_file}" ".gitattributes"
    assert_list_contains "${list_file}" ".gitignore"
    local path directory
    load_panel_modules "${ROOT_DIR}" || fail "Invalid source module manifest"
    for path in "${MODULES[@]}"; do
        assert_list_contains "${list_file}" "${path}"
    done
    # 工程辅助文件必须完整随源码发布，避免只打包入口而遗漏 helpers/fixtures。
    assert_list_contains "${list_file}" "scripts/panel-modules.list"
    assert_list_contains "${list_file}" "scripts/lib/source-manifest.sh"
    for directory in scripts tests docs; do
        [[ -d "${directory}" ]] || fail "Missing engineering directory: ${directory}"
    done
    while IFS= read -r -d '' path; do
        assert_list_contains "${list_file}" "${path}"
    done < <(find scripts tests docs -type f -print0)

}

check_local_only_paths_absent() {
    local list_file="$1"
    assert_list_not_contains "${list_file}" "AGENTS.md"
    assert_list_not_contains "${list_file}" "LOCAL_WORK_MEMORY.md"
    assert_list_not_contains "${list_file}" "PROJECT_MEMORY.md"
    assert_list_not_contains "${list_file}" ".github/workflows/lint.yml"
    assert_list_not_contains "${list_file}" ".github/workflows/release.yml"
}

check_tracked_tree() {
    local list_file
    list_file="$(mktemp)"
    if git ls-files --cached --others --exclude-standard > "${list_file}" 2>/dev/null; then
        sort -o "${list_file}" "${list_file}"
    else
        find . -type f \
            ! -path './.git/*' \
            ! -path './.github/*' \
            | sed -E 's#^\./##' \
            | sort > "${list_file}"
    fi
    check_required_paths "${list_file}"
    check_forbidden_paths "${list_file}"
    assert_list_not_contains "${list_file}" "AGENTS.md"
    assert_list_not_contains "${list_file}" "LOCAL_WORK_MEMORY.md"
    assert_list_not_contains "${list_file}" "PROJECT_MEMORY.md"
    rm -f "${list_file}"
}

check_archive() {
    local archive="$1"
    local list_file
    [[ -f "${archive}" ]] || fail "Release archive not found: ${archive}"
    list_file="$(mktemp)"
    tar -tzf "${archive}" | sed -E 's#^\./##; s#/$##' | sort > "${list_file}"
    check_required_paths "${list_file}"
    check_local_only_paths_absent "${list_file}"
    check_forbidden_paths "${list_file}"
    rm -f "${list_file}"
}

check_tracked_tree
if [[ -n "${1:-}" ]]; then
    check_archive "$1"
fi

echo "[OK] Release package checks passed."
