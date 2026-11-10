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

kernel_forbidden_call() {
  printf 'unexpected mutation or network: %s\n' "$*" >> "${TEST_TMP_DIR}/forbidden-call"
  return 99
}

mock_kernel_environment() {
  HY2_OS_RELEASE_FILE="${TEST_TMP_DIR}/os-release"
  HY2_MPTCP_ENABLED_FILE="${TEST_TMP_DIR}/mptcp-enabled"
  printf 'ID=ubuntu\nVERSION_ID="26.04"\n' > "${HY2_OS_RELEASE_FILE}"
  printf '1\n' > "${HY2_MPTCP_ENABLED_FILE}"
  test_kernel_release=7.0.0-1015-oracle
  test_kernel_package_version=7.0.0-1015.17
  uname() {
    case "$*" in
      -s) echo Linux ;;
      -r) printf '%s\n' "${test_kernel_release}" ;;
      *) return 1 ;;
    esac
  }
  dpkg-query() {
    printf '%s\n' "$*" >> "${TEST_TMP_DIR}/package-queries"
    [[ "${!#}" == "linux-image-${test_kernel_release}" ]] || return 1
    printf 'installed linux-image-%s %s\n' "${test_kernel_release}" "${test_kernel_package_version}"
  }
  rpm() { return 1; }
  apt-get() { kernel_forbidden_call apt-get "$@"; }
  dnf() { kernel_forbidden_call dnf "$@"; }
  yum() { kernel_forbidden_call yum "$@"; }
  curl() { kernel_forbidden_call curl "$@"; }
  wget() { kernel_forbidden_call wget "$@"; }
  sysctl() { kernel_forbidden_call sysctl "$@"; }
  nft() { kernel_forbidden_call nft "$@"; }
  iptables() { kernel_forbidden_call iptables "$@"; }
  reboot() { kernel_forbidden_call reboot "$@"; }
  hysteria() { kernel_forbidden_call hysteria "$@"; }
  go() { kernel_forbidden_call go "$@"; }
  diagnostic_reset_context
}

@test "kernel diagnostics should record the running oracle kernel without claiming patch verification" {
  mock_kernel_environment
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [ "${DIAG_WARN_COUNT}" -eq 2 ]
  grep -Fq '7.0.0-1015-oracle' "${DIAG_FILE}"
  grep -Fq 'linux-image-7.0.0-1015-oracle 7.0.0-1015.17' "${DIAG_FILE}"
  grep -Fq 'ubuntu 26.04' "${DIAG_FILE}"
  grep -Fq 'CVE-2026-98432' "${DIAG_FILE}"
  grep -Fq '不代表存在实际 MPTCP 监听' "${DIAG_FILE}"
  grep -Fq 'linux-image-7.0.0-1015-oracle' "${TEST_TMP_DIR}/package-queries"
  [[ "${DIAG_SUGGESTIONS[0]}" == *'正式安全更新'* && "${DIAG_SUGGESTIONS[0]}" == *'重启'* ]]
}

@test "disabled MPTCP and a newer kernel package should not prove the kernel CVE fixed" {
  mock_kernel_environment
  printf '0\n' > "${HY2_MPTCP_ENABLED_FILE}"
  test_kernel_release=99.0.0-9999-generic
  test_kernel_package_version=99.0.0-9999.9999
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [ "${DIAG_WARN_COUNT}" -eq 2 ]
  grep -Fq '关闭 MPTCP 不等于修复' "${DIAG_FILE}"
  grep -Fq '修复状态需按发行版公告核验' "${DIAG_FILE}"
}

@test "missing or malformed MPTCP state should remain unknown" {
  mock_kernel_environment
  HY2_MPTCP_ENABLED_FILE="${TEST_TMP_DIR}/missing-mptcp"
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  grep -Fq 'MPTCP 状态未知' "${DIAG_FILE}"
  local state
  for state in '' 2 '0 extra' $'0\n1' '$(touch SHOULD_NOT_EXECUTE)'; do
    printf '%s\n' "${state}" > "${HY2_MPTCP_ENABLED_FILE}"
    diagnostic_reset_context
    diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
    [ "${DIAG_OK_COUNT}" -eq 0 ]
    grep -Fq 'MPTCP 状态未知' "${DIAG_FILE}"
    ! grep -Fq 'SHOULD_NOT_EXECUTE' "${DIAG_FILE}"
  done
}

@test "failed MPTCP reads should not accept partial output" {
  mock_kernel_environment
  cat() {
    if [[ "${!#}" == "${HY2_MPTCP_ENABLED_FILE}" ]]; then echo 0; return 1; fi
    command cat "$@"
  }
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq 'MPTCP 状态未知' "${DIAG_FILE}"
}

@test "kernel probes should reject invalid releases before querying package tools" {
  mock_kernel_environment
  local release
  for release in '' '-bad' '7.0;touch bad' $'7.0\nother' '7.0/../../etc/passwd'; do
    run get_running_kernel_package "${release}"
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
  done
  [ ! -e "${TEST_TMP_DIR}/package-queries" ]
}

@test "failed uname releases should not be mistaken for the running kernel" {
  mock_kernel_environment
  uname() { if [[ "$*" == -s ]]; then echo Linux; else echo 7.0.0-1015-oracle; return 1; fi; }
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq '运行中的 Linux 内核版本未知' "${DIAG_FILE}"
  [ ! -e "${TEST_TMP_DIR}/package-queries" ]
}

@test "non-Linux or unknown operating systems should not pass the kernel check" {
  mock_kernel_environment
  uname() { echo MINGW64_NT; }
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ ! -e "${TEST_TMP_DIR}/package-queries" ]
  uname() { return 1; }
  diagnostic_reset_context
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
}

@test "running kernel package query should reject unrelated uninstalled and malformed results" {
  mock_kernel_environment
  local result
  for result in '' 'installed linux-image-99.0-newer 99.0' 'config-files linux-image-7.0.0-1015-oracle 7.0' 'installed linux-image-7.0.0-1015-oracle bad/version' $'installed linux-image-7.0.0-1015-oracle 7.0\nextra'; do
    dpkg-query() { printf '%s\n' "${result}"; }
    run get_running_kernel_package "${test_kernel_release}"
    [ "${status}" -ne 0 ]
    [ -z "${output}" ]
  done
  dpkg-query() { printf 'installed linux-image-%s 7.0\n' "${test_kernel_release}"; return 1; }
  run get_running_kernel_package "${test_kernel_release}"
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "running kernel package query should support the matching unsigned image" {
  mock_kernel_environment
  dpkg-query() {
    [[ "${!#}" == "linux-image-unsigned-${test_kernel_release}" ]] || return 1
    printf 'installed linux-image-unsigned-%s 7.0.0-1015.17\n' "${test_kernel_release}"
  }
  run get_running_kernel_package "${test_kernel_release}"
  [ "${status}" -eq 0 ]
  [ "${output}" = 'linux-image-unsigned-7.0.0-1015-oracle 7.0.0-1015.17' ]
}

@test "RPM kernel query should identify the running boot image without Ubuntu baselines" {
  mock_kernel_environment
  command() { [[ "${2:-}" != dpkg-query ]] || return 1; builtin command "$@"; }
  test_kernel_release=6.12.0-100.1.el9uek.aarch64
  rpm() {
    [[ "${!#}" == "/boot/vmlinuz-${test_kernel_release}" ]] || return 1
    printf 'kernel-uek-core 6.12.0-100.1.el9uek\n'
  }
  printf 'ID=ol\nVERSION_ID=9\n' > "${HY2_OS_RELEASE_FILE}"
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  grep -Fq 'kernel-uek-core 6.12.0-100.1.el9uek' "${DIAG_FILE}"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [[ "${DIAG_COMMANDS[0]}" != *ubuntu.com* ]]
}

@test "missing package tools and OS information should leave kernel patch status unknown" {
  mock_kernel_environment
  command() {
    case "${2:-}" in dpkg-query|rpm) return 1 ;; esac
    builtin command "$@"
  }
  HY2_OS_RELEASE_FILE="${TEST_TMP_DIR}/missing-os-release"
  diagnostic_check_kernel_security > "${TEST_TMP_DIR}/kernel.out"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  grep -Fq 'unknown unknown' "${DIAG_FILE}"
  grep -Fq '运行内核包未知' "${DIAG_FILE}"
}
