#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

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
    assert_list_contains "${list_file}" "src/bootstrap.sh"
    assert_list_contains "${list_file}" "src/main.sh"
    assert_list_contains "${list_file}" "src/core/output.sh"
    assert_list_contains "${list_file}" "src/core/input.sh"
    assert_list_contains "${list_file}" "src/core/environment.sh"
    assert_list_contains "${list_file}" "src/core/validation.sh"
    assert_list_contains "${list_file}" "src/core/encoding.sh"
    assert_list_contains "${list_file}" "src/core/files.sh"
    assert_list_contains "${list_file}" "src/core/network.sh"
    assert_list_contains "${list_file}" "src/core/metadata.sh"
    assert_list_contains "${list_file}" "src/hysteria/certificate.sh"
    assert_list_contains "${list_file}" "src/hysteria/config_write.sh"
    assert_list_contains "${list_file}" "src/hysteria/config_input.sh"
    assert_list_contains "${list_file}" "src/hysteria/config_apply.sh"
    assert_list_contains "${list_file}" "src/hysteria/config.sh"
    assert_list_contains "${list_file}" "src/hysteria/permissions.sh"
    assert_list_contains "${list_file}" "src/hysteria/rollback.sh"
    assert_list_contains "${list_file}" "src/hysteria/service.sh"
    assert_list_contains "${list_file}" "src/hysteria/install.sh"
    assert_list_contains "${list_file}" "src/clients/hysteria2.sh"
    assert_list_contains "${list_file}" "src/clients/singbox_outbound.sh"
    assert_list_contains "${list_file}" "src/clients/singbox_dns.sh"
    assert_list_contains "${list_file}" "src/clients/singbox_route.sh"
    assert_list_contains "${list_file}" "src/clients/singbox_full.sh"
    assert_list_contains "${list_file}" "src/clients/singbox.sh"
    assert_list_contains "${list_file}" "src/clients/v2rayn.sh"
    assert_list_contains "${list_file}" "src/clients/summary.sh"
    assert_list_contains "${list_file}" "src/clients/exports.sh"
    assert_list_contains "${list_file}" "src/clients/display.sh"
    assert_list_contains "${list_file}" "src/clients/cheatsheet.sh"
    assert_list_contains "${list_file}" "src/panel/update.sh"
    assert_list_contains "${list_file}" "src/panel/menu.sh"
    assert_list_contains "${list_file}" "src/operations/diagnostic_context.sh"
    assert_list_contains "${list_file}" "src/operations/diagnostic_checks.sh"
    assert_list_contains "${list_file}" "src/operations/diagnostic_report.sh"
    assert_list_contains "${list_file}" "src/operations/diagnostics.sh"
    assert_list_contains "${list_file}" "src/operations/backup_create.sh"
    assert_list_contains "${list_file}" "src/operations/backup_restore.sh"
    assert_list_contains "${list_file}" "src/operations/backup.sh"
    assert_list_contains "${list_file}" "scripts/build-panel.sh"
    assert_list_contains "${list_file}" "scripts/verify.sh"
    assert_list_contains "${list_file}" "scripts/benchmark.sh"
    assert_list_contains "${list_file}" "scripts/check-style.sh"
    assert_list_contains "${list_file}" "scripts/check-menu-sync.sh"
    assert_list_contains "${list_file}" "scripts/check-brand-sync.sh"
    assert_list_contains "${list_file}" "scripts/check-version-sync.sh"
    assert_list_contains "${list_file}" "scripts/check-release-package.sh"
    assert_list_contains "${list_file}" "scripts/smoke-e2e.sh"
    assert_list_contains "${list_file}" "tests/unit/hy2_core.bats"
    assert_list_contains "${list_file}" "tests/e2e/config-flow.sh"
    assert_list_contains "${list_file}" "tests/e2e/client-render.sh"
    assert_list_contains "${list_file}" "tests/e2e/runtime-contracts.sh"
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
