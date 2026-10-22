#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

teardown() {
  local forbidden_call=0
  if [[ -f "${TEST_TMP_DIR}/forbidden-call" ]]; then
    cat "${TEST_TMP_DIR}/forbidden-call"
    forbidden_call=1
  fi
  test_cleanup_environment
  [[ "${forbidden_call}" -eq 0 ]]
}

mock_ubuntu_trust() {
  HY2_OS_RELEASE_FILE="${TEST_TMP_DIR}/os-release"
  printf 'ID=ubuntu\nVERSION_ID="%s"\n' "${1:-26.04}" > "${HY2_OS_RELEASE_FILE}"
  dpkg-query() { printf 'installed %s\n' "${test_ca_version}"; }
  dpkg() {
    [[ "$*" == "--compare-versions ${test_ca_version} ge ${test_ca_baseline}" ]] || return 2
    return "${test_ca_compare_status:-0}"
  }
  # 诊断只能读本机信息；调用下面任何命令都会让测试失败。
  apt-get() { printf 'unexpected-package-write\n' >> "${TEST_TMP_DIR}/forbidden-call"; return 99; }
  dnf() { printf 'unexpected-package-write\n' >> "${TEST_TMP_DIR}/forbidden-call"; return 99; }
  yum() { printf 'unexpected-package-write\n' >> "${TEST_TMP_DIR}/forbidden-call"; return 99; }
  curl() { printf 'unexpected-network\n' >> "${TEST_TMP_DIR}/forbidden-call"; return 99; }
  test_ca_version=20260816ubuntu0.26.04.1
  test_ca_baseline=20260816ubuntu0.26.04.1
  diagnostic_reset_context
}

@test "menu 8 should include both trust checks in the saved report" {
  clear() { :; }
  wait_return() { :; }
  diagnostic_check_core() { :; }
  diagnostic_check_service() { :; }
  diagnostic_check_runtime_files() { :; }
  diagnostic_check_server_config() { :; }
  diagnostic_check_public_ip() { :; }
  diagnostic_check_go_trust() { diagnostic_print_result WARN go-trust-unknown; }
  diagnostic_check_ca_trust() { diagnostic_print_result WARN ca-trust-unknown; }
  show_diagnostics > "${TEST_TMP_DIR}/report.out"
  grep -Fq go-trust-unknown "${HY2_DIAG_LATEST}"
  grep -Fq ca-trust-unknown "${HY2_DIAG_LATEST}"
  grep -Fq '0 OK / 2 WARN / 0 FAIL' "${HY2_DIAG_LATEST}"
}

@test "Go build probe should read only a stable Toolchain field from the running binary" {
  hysteria() { printf 'Version: v2.13.0\nToolchain:\tgo1.27.3\nLibraries: go1.99.0\n'; }
  run get_hy2_go_version
  [ "${status}" -eq 0 ]
  [ "${output}" = go1.27.3 ]
  hysteria() { printf 'Version: v2.13.0\nLibraries: go1.27.3\n'; }
  run get_hy2_go_version
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "Go build probe should reject failed commands and non-release toolchains" {
  local toolchain
  for toolchain in unknown go1.27rc3 go1.28.0rc1 go1.27.3-custom; do
    hysteria() { printf 'Toolchain: %s\n' "${toolchain}"; }
    run get_hy2_go_version
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
  done
  hysteria() { printf 'Toolchain: go1.27.3\n'; return 1; }
  run get_hy2_go_version
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "Go CA mitigation should compare each maintained branch separately" {
  local version
  for version in go1.26.10 go1.26.11 go1.27.3 go1.27.4 go1.28.0; do
    run go_version_has_ca_mitigation "${version}"
    [ "${status}" -eq 0 ]
  done
  for version in go1.25.99 go1.26.9 go1.27.0 go1.27.2 go1.28rc1 unknown; do
    run go_version_has_ca_mitigation "${version}"
    [ "${status}" -ne 0 ]
  done
}

@test "Go diagnostics should warn for old toolchains even with a current Hysteria release" {
  hysteria() { printf 'Version: v2.13.0\nToolchain: go1.27.2\n'; }
  diagnostic_reset_context
  diagnostic_check_go_trust > "${TEST_TMP_DIR}/go.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq go1.27.2 "${DIAG_FILE}"
  [[ "${DIAG_SUGGESTIONS[0]}" == *'仅升级系统 Go 不会修复现有二进制'* ]]
  [[ "${DIAG_SUGGESTIONS[0]}" == *'1.26.10'* ]]
}

@test "Go diagnostics should mark unreadable build versions as unknown not safe" {
  hysteria() { printf 'Toolchain: unknown\n'; }
  diagnostic_reset_context
  diagnostic_check_go_trust > "${TEST_TMP_DIR}/go.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq 'Go 构建版本未知' "${DIAG_FILE}"
}

@test "Go diagnostics should scope patched results to the toolchain baseline" {
  hysteria() { printf 'Toolchain: go1.27.3\n'; }
  diagnostic_reset_context
  diagnostic_check_go_trust > "${TEST_TMP_DIR}/go.out"
  [ "${DIAG_OK_COUNT}" -eq 1 ]
  [ "${DIAG_WARN_COUNT}" -eq 0 ]
  grep -Fq '不代表系统 CA 已更新' "${DIAG_FILE}"
}

@test "Ubuntu CA diagnostics should use the release-specific official baseline" {
  local release
  for release in 22.04 24.04 26.04 26.10; do
    mock_ubuntu_trust "${release}"
    test_ca_version="20260816ubuntu0.${release}.1"
    test_ca_baseline="${test_ca_version}"
    diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
    [ "${DIAG_OK_COUNT}" -eq 1 ]
    [ "${DIAG_WARN_COUNT}" -eq 0 ]
    grep -Fq "${test_ca_version}" "${DIAG_FILE}"
    grep -Fq USN-8944-1 "${DIAG_FILE}"
    ! grep -Eq 'unexpected-package-write|unexpected-network' "${TEST_TMP_DIR}/ca.out"
  done
}

@test "Ubuntu CA diagnostics should warn for an outdated package using dpkg ordering" {
  mock_ubuntu_trust
  test_ca_version=20260816
  test_ca_compare_status=1
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq '低于' "${DIAG_FILE}"
  [[ "${DIAG_COMMANDS[0]}" == *'apt-get install --only-upgrade ca-certificates'* ]]
  ! grep -Eq 'unexpected-package-write|unexpected-network' "${TEST_TMP_DIR}/ca.out"
}

@test "Ubuntu CA diagnostics should leave package comparison errors unknown" {
  mock_ubuntu_trust
  test_ca_compare_status=2
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq '状态未知' "${DIAG_FILE}"
  ! grep -Fq '低于' "${DIAG_FILE}"
}

@test "CA diagnostics should reject missing and malformed package query results" {
  mock_ubuntu_trust
  local package_result
  for package_result in '' 'config-files 20260816ubuntu0.26.04.1' 'installed invalid/version' 'installed 20260816 extra' $'installed 20260816\ninstalled 99999999'; do
    dpkg-query() { printf '%s\n' "${package_result}"; }
    diagnostic_reset_context
    diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
    [ "${DIAG_WARN_COUNT}" -eq 1 ]
    [ "${DIAG_OK_COUNT}" -eq 0 ]
  done
  dpkg-query() { printf 'installed 20260816ubuntu0.26.04.1\n'; return 1; }
  diagnostic_reset_context
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
}

@test "CA package probe should query RPM without applying Ubuntu version semantics" {
  command() {
    [[ "${2:-}" != dpkg-query ]] || return 1
    builtin command "$@"
  }
  rpm() {
    [[ "$*" == '-q --qf %{VERSION}-%{RELEASE} ca-certificates' ]] || return 1
    printf '2026.2.92_v9.0.319-1.el9\n'
  }
  run get_ca_certificates_version
  [ "${status}" -eq 0 ]
  [ "${output}" = '2026.2.92_v9.0.319-1.el9' ]
  rpm() { printf '2026.2.92\nsecond-package\n'; }
  run get_ca_certificates_version
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "Go diagnostics should skip an absent core without consulting the system Go SDK" {
  command() {
    [[ "${2:-}" != hysteria ]] || return 1
    builtin command "$@"
  }
  go() { echo unexpected-go-sdk; return 99; }
  diagnostic_reset_context
  run diagnostic_check_go_trust
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "CA diagnostics should not infer Ubuntu package fixes for other distributions" {
  mock_ubuntu_trust
  printf 'ID=debian\nID_LIKE=ubuntu\nVERSION_ID="13"\n' > "${HY2_OS_RELEASE_FILE}"
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq '状态未知' "${DIAG_FILE}"
  [[ "${DIAG_COMMANDS[0]}" != *apt-get* ]]
}

@test "CA diagnostics should handle missing tools and unreadable OS information" {
  mock_ubuntu_trust 20.04
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  HY2_OS_RELEASE_FILE="${TEST_TMP_DIR}/missing-os-release"
  diagnostic_reset_context
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  diagnostic_reset_context
  command() {
    case "${2:-}" in dpkg-query|dpkg|rpm) return 1 ;; esac
    builtin command "$@"
  }
  diagnostic_check_ca_trust > "${TEST_TMP_DIR}/ca.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
}

@test "OS release parser should never execute shell expressions" {
  mock_ubuntu_trust
  printf 'ID="$(touch %s)"\nVERSION_ID="26.04"\n' "${TEST_TMP_DIR}/executed" > "${HY2_OS_RELEASE_FILE}"
  run diagnostic_os_release_field ID
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
  [ ! -e "${TEST_TMP_DIR}/executed" ]
}
