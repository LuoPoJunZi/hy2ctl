#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"
# shellcheck source=../helpers/assertions.sh
source "${ROOT_DIR}/tests/helpers/assertions.sh"
# shellcheck source=../helpers/environment.sh
source "${ROOT_DIR}/tests/helpers/environment.sh"
test_create_environment
trap test_cleanup_environment EXIT
# shellcheck source=../../scripts/lib/source-manifest.sh
source "${ROOT_DIR}/scripts/lib/source-manifest.sh"

test_manifest() (
    local fixture="${TEST_TMP_DIR}/manifest-fixture"
    mkdir -p "${fixture}/src/core/nested" "${fixture}/scripts/lib"
    cp "${ROOT_DIR}/scripts/build-panel.sh" "${fixture}/scripts/"
    cp "${ROOT_DIR}/scripts/lib/source-manifest.sh" "${fixture}/scripts/lib/"
    printf '#!/bin/bash\nsh_ver="v1.2.3"\n' > "${fixture}/src/bootstrap.sh"
    printf 'fixture_function() { :; }\n' > "${fixture}/src/core/nested/module.sh"
    printf 'main_menu() { :; }\n' > "${fixture}/src/main.sh"
    printf '%s\n' src/bootstrap.sh src/core/nested/module.sh src/main.sh > "${fixture}/scripts/panel-modules.list"
    load_panel_modules "${fixture}"
    assert_eq "${#MODULES[@]}" 3 'Manifest module count'
    assert_eq "${MODULES[1]}" src/core/nested/module.sh 'Manifest order'
    bash "${fixture}/scripts/build-panel.sh"
    bash "${fixture}/scripts/build-panel.sh" --check
    # 用原来的逐文件拼接方式独立核对构建结果。
    {
        cat "${fixture}/src/bootstrap.sh"
        printf '\n'
        cat "${fixture}/src/core/nested/module.sh"
        printf '\n'
        cat "${fixture}/src/main.sh"
    } > "${fixture}/expected.sh"
    cmp "${fixture}/expected.sh" "${fixture}/hy2.sh"

    local invalid
    for invalid in \
        $'src/bootstrap.sh\nsrc/core/nested/module.sh\nsrc/core/nested/module.sh\nsrc/main.sh' \
        $'src/bootstrap.sh\nsrc/main.sh' \
        $'src/main.sh\nsrc/core/nested/module.sh\nsrc/bootstrap.sh' \
        $'src/bootstrap.sh\nsrc/../outside.sh\nsrc/main.sh' \
        $'src/bootstrap.sh\n$(touch SHOULD_NOT_EXIST)\nsrc/main.sh'; do
        printf '%s\n' "${invalid}" > "${fixture}/scripts/panel-modules.list"
        if (cd "${fixture}" && load_panel_modules "${fixture}") > /dev/null 2>&1; then
            fail 'Invalid module manifest accepted'
        fi
    done
    [[ ! -e "${fixture}/SHOULD_NOT_EXIST" ]] || fail 'Manifest content was executed'
    echo '[OK] Manifest enforces order, completeness, uniqueness and data-only paths.'
)

test_release_archive() (
    local archive="${TEST_TMP_DIR}/release.tar.gz"
    local -a files=(hy2.sh install.sh README.md CHANGELOG.md LICENSE .editorconfig .gitattributes .gitignore src scripts tests docs)
    tar -czf "${archive}" "${files[@]}"
    bash scripts/check-release-package.sh "${archive}"
    tar --exclude='tests/helpers' -czf "${archive}" "${files[@]}"
    if bash scripts/check-release-package.sh "${archive}" > "${TEST_TMP_DIR}/archive.log" 2>&1; then
        fail 'Release accepted missing test helpers'
    fi
    assert_contains_file "${TEST_TMP_DIR}/archive.log" tests/helpers 'Archive failure did not identify helpers'
    local local_path
    for local_path in AGENTS.md LOCAL_BLOG_TUTORIAL.md PROJECT_MEMORY.md .env server.key code.tar.gz; do
        printf 'local-only fixture\n' > "${TEST_TMP_DIR}/${local_path}"
        tar -czf "${archive}" "${files[@]}" -C "${TEST_TMP_DIR}" "${local_path}"
        if bash scripts/check-release-package.sh "${archive}" > "${TEST_TMP_DIR}/archive.log" 2>&1; then
            fail "Release accepted forbidden file: ${local_path}"
        fi
        rm -f "${TEST_TMP_DIR:?}/${local_path}"
    done
    echo '[OK] Release archive includes helpers/fixtures/docs and rejects local-only files.'
)

test_manifest
test_release_archive
echo '[OK] Repository layout checks passed.'
