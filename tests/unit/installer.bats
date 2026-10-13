#!/usr/bin/env bats

# shellcheck source=../helpers/environment.sh
source "${BATS_TEST_DIRNAME}/../helpers/environment.sh"

setup() {
  test_create_environment
  # shellcheck source=../../install.sh
  source "${TEST_ROOT_DIR}/install.sh"
  INSTALLER_PRESENT_COMMANDS='curl wget openssl'
  INSTALLER_UPDATE_STATUS=0
  INSTALLER_INSTALL_STATUS=0
  INSTALLER_LEAVE_MISSING=0
  INSTALLER_COMMAND_LOG="${TEST_TMP_DIR}/package-commands"
  : > "${INSTALLER_COMMAND_LOG}"
}

teardown() { test_cleanup_environment; }

# 只模拟依赖可用性；其他命令仍使用 Bash 内建检测。
command() {
  if [[ "${1:-}" == '-v' ]]; then
    case "${2:-}" in
      curl|wget|openssl)
        [[ " ${INSTALLER_PRESENT_COMMANDS} " == *" ${2} "* ]]
        return
        ;;
    esac
  fi
  builtin command "$@"
}

# 所有包管理器均为函数模拟，任何测试都不会调用真实 APT/DNF/YUM。
installer_mock_package_manager() {
  local manager="$1" action='' arg
  shift
  printf '%s %s\n' "${manager}" "$*" >> "${INSTALLER_COMMAND_LOG}"
  printf 'frontend=%s\n' "${DEBIAN_FRONTEND:-unset}" >> "${INSTALLER_COMMAND_LOG}"
  for arg in "$@"; do
    case "${arg}" in
      update|install) action="${arg}"; break ;;
    esac
  done
  if [[ "${action}" == update ]]; then
    if [[ "${INSTALLER_UPDATE_STATUS}" -ne 0 ]]; then
      printf "E: The repository 'https:/ubuntu-ports resolute-security Release' does not have a Release file.\n" >&2
    fi
    return "${INSTALLER_UPDATE_STATUS}"
  fi
  if [[ "${INSTALLER_INSTALL_STATUS}" -ne 0 ]]; then
    printf 'E: Could not get lock /var/lib/dpkg/lock-frontend\n' >&2
    return "${INSTALLER_INSTALL_STATUS}"
  fi
  if [[ "${INSTALLER_LEAVE_MISSING}" -eq 0 ]]; then
    INSTALLER_PRESENT_COMMANDS+=' curl openssl'
  fi
  return 0
}

apt-get() { installer_mock_package_manager apt-get "$@"; }
dnf() { installer_mock_package_manager dnf "$@"; }
yum() { installer_mock_package_manager yum "$@"; }

@test "installer sourcing should not deploy or change shell options" {
  run bash -c 'set +eu; set +o pipefail; source "$1" || exit 1; [[ "$-" != *e* && "$-" != *u* ]] || exit 1; if shopt -qo pipefail; then exit 1; fi; declare -F install_dependencies' _ "${TEST_ROOT_DIR}/install.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == 'install_dependencies' ]]
}

@test "ready dependencies should bypass broken Ubuntu security repositories" {
  INSTALLER_UPDATE_STATUS=100
  run install_dependencies apt-get
  [ "${status}" -eq 0 ]
  [ ! -s "${INSTALLER_COMMAND_LOG}" ]
  [[ "${output}" == *'基础依赖已齐全'* ]]
}

@test "missing optional wget should not trigger package installation" {
  INSTALLER_PRESENT_COMMANDS='curl openssl'
  run install_dependencies apt-get
  [ "${status}" -eq 0 ]
  [ ! -s "${INSTALLER_COMMAND_LOG}" ]
}

@test "APT should install only missing required commands" {
  INSTALLER_PRESENT_COMMANDS='curl wget'
  run install_dependencies apt-get
  [ "${status}" -eq 0 ]
  grep -Eq 'apt-get .*update$' "${INSTALLER_COMMAND_LOG}"
  grep -Eq 'apt-get .*install -y openssl$' "${INSTALLER_COMMAND_LOG}"
  ! grep -Eq 'install .*curl|install .*wget' "${INSTALLER_COMMAND_LOG}"
}

@test "APT should request curl and openssl when both are missing" {
  INSTALLER_PRESENT_COMMANDS='wget'
  run install_dependencies apt-get
  [ "${status}" -eq 0 ]
  grep -Eq 'apt-get .*install -y curl openssl$' "${INSTALLER_COMMAND_LOG}"
}

@test "APT should wait for dpkg locks and use noninteractive bounded downloads" {
  INSTALLER_PRESENT_COMMANDS='curl'
  run install_dependencies apt-get
  [ "${status}" -eq 0 ]
  grep -Fq 'DPkg::Lock::Timeout=60' "${INSTALLER_COMMAND_LOG}"
  grep -Fq 'Acquire::Retries=2' "${INSTALLER_COMMAND_LOG}"
  grep -Fq 'Acquire::http::Timeout=20' "${INSTALLER_COMMAND_LOG}"
  grep -Fq 'Acquire::https::Timeout=20' "${INSTALLER_COMMAND_LOG}"
  grep -Fq 'frontend=noninteractive' "${INSTALLER_COMMAND_LOG}"
}

@test "failed APT index refresh should expose the real error and stop installation" {
  INSTALLER_PRESENT_COMMANDS='curl'
  INSTALLER_UPDATE_STATUS=100
  run install_dependencies apt-get
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'does not have a Release file'* ]]
  [[ "${output}" == *'APT 软件包索引刷新失败'* ]]
  ! grep -Fq 'install -y' "${INSTALLER_COMMAND_LOG}"
}

@test "failed APT package installation should expose lock errors" {
  INSTALLER_PRESENT_COMMANDS='curl'
  INSTALLER_INSTALL_STATUS=100
  run install_dependencies apt-get
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Could not get lock'* ]]
  [[ "${output}" == *'APT 依赖安装失败'* ]]
}

@test "successful package status should not conceal still-missing dependencies" {
  INSTALLER_PRESENT_COMMANDS='curl'
  INSTALLER_LEAVE_MISSING=1
  run install_dependencies apt-get
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'缺少依赖命令: openssl'* ]]
}

@test "RPM managers should not replace existing curl or require optional wget" {
  local manager
  for manager in dnf yum; do
    INSTALLER_PRESENT_COMMANDS='curl'
    : > "${INSTALLER_COMMAND_LOG}"
    run install_dependencies "${manager}"
    [ "${status}" -eq 0 ]
    grep -Fxq "${manager} install -y openssl" "${INSTALLER_COMMAND_LOG}"
    ! grep -Eq 'install .*curl|install .*wget' "${INSTALLER_COMMAND_LOG}"
  done
}

@test "RPM install failures should be visible and remain failures" {
  INSTALLER_PRESENT_COMMANDS='curl'
  INSTALLER_INSTALL_STATUS=1
  run install_dependencies dnf
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'dnf 依赖安装失败'* ]]
}

@test "unsupported managers should fail without invoking a package command" {
  INSTALLER_PRESENT_COMMANDS='curl'
  run install_dependencies unsupported
  [ "${status}" -ne 0 ]
  [ ! -s "${INSTALLER_COMMAND_LOG}" ]
  [[ "${output}" == *'不支持的包管理器'* ]]
}
