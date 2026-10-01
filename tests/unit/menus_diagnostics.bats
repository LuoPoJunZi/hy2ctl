#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "service operations should forward supported actions and reject others" {
  systemctl() { printf '%s\n' "$*"; return 7; }
  run change_hy2_service_state restart
  [ "${status}" -eq 7 ]
  [ "${output}" = "restart ${HY2_SERVICE}" ]
  systemctl() { echo "unexpected-systemctl"; return 0; }
  run change_hy2_service_state disable
  [ "${status}" -ne 0 ]
  [[ "${output}" != *unexpected-systemctl* ]]
}

@test "update menu should dispatch core and panel updates" {
  clear() { :; }
  wait_return() { :; }
  install_hy2_core() { echo "core-updater-called"; }
  update_panel_script() { echo "panel-updater-called"; }

  run show_update_menu <<< "1"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"core-updater-called"* ]]

  run show_update_menu <<< "2"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"panel-updater-called"* ]]
}

@test "diagnostic context should count results and deduplicate suggestions" {
  diagnostic_reset_context
  diagnostic_print_result "OK" "context-ok"
  diagnostic_print_result "WARN" "context-warn"
  diagnostic_add_item "same conclusion" "first suggestion" "first command"
  diagnostic_add_item "same conclusion" "second suggestion" "second command"

  [ "${DIAG_OK_COUNT}" -eq 1 ]
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_FAIL_COUNT}" -eq 0 ]
  [ "${#DIAG_CONCLUSIONS[@]}" -eq 1 ]
  [ "${DIAG_SUGGESTIONS[0]}" = "first suggestion" ]

  diagnostic_render_summary
  grep -Fq "诊断结果: 1 OK / 1 WARN / 0 FAIL" "${HY2_DIAG_LATEST}"
  grep -Fq "[建议] first suggestion" "${HY2_DIAG_LATEST}"
}

@test "core diagnostics should distinguish security risk from recommended updates" {
  hysteria() { :; }

  get_hy2_core_version() { printf 'v2.8.1\n'; }
  diagnostic_reset_context
  diagnostic_check_core > "${TEST_TMP_DIR}/core-diagnostic.out"
  output="$(<"${TEST_TMP_DIR}/core-diagnostic.out")"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [[ "${output}" == *"低于安全基线 v${HY2_SECURITY_BASELINE_VERSION}"* ]]
  [[ "${DIAG_CONCLUSIONS[0]}" == *"高危安全风险"* ]]
  [[ "${DIAG_SUGGESTIONS[0]}" == *"立即更新到 v${RECOMMENDED_HY2_VERSION}"* ]]

  get_hy2_core_version() { printf 'v2.9.2\n'; }
  diagnostic_reset_context
  diagnostic_check_core > "${TEST_TMP_DIR}/core-diagnostic.out"
  output="$(<"${TEST_TMP_DIR}/core-diagnostic.out")"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [[ "${output}" == *"低于建议版本 v${RECOMMENDED_HY2_VERSION}"* ]]
  [[ "${output}" != *"高危安全风险"* ]]
  [ "${DIAG_CONCLUSIONS[0]}" = "Hysteria2 内核版本较旧。" ]

  get_hy2_core_version() { printf 'v2.12.2\n'; }
  diagnostic_reset_context
  diagnostic_check_core > "${TEST_TMP_DIR}/core-diagnostic.out"
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [[ "${DIAG_SUGGESTIONS[0]}" == *'HTTP 代理传输 10 秒断开'* ]]

  get_hy2_core_version() { printf 'v2.12.3\n'; }
  diagnostic_reset_context
  diagnostic_check_core > "${TEST_TMP_DIR}/core-diagnostic.out"
  output="$(<"${TEST_TMP_DIR}/core-diagnostic.out")"
  [ "${DIAG_OK_COUNT}" -eq 1 ]
  [ "${DIAG_WARN_COUNT}" -eq 0 ]
  [[ "${output}" == *"Hysteria2 内核版本: v2.12.3"* ]]
  [ "${#DIAG_CONCLUSIONS[@]}" -eq 0 ]
}

@test "diagnostic reports created in the same second should not overwrite each other" {
  date() { printf '20261001-120000\n'; }
  diagnostic_reset_context
  local first_report="${DIAG_FILE}"
  diagnostic_log 'first report'
  diagnostic_reset_context
  [ "${DIAG_FILE}" != "${first_report}" ]
  [ "$(<"${first_report}")" = 'first report' ]
  [ -f "${DIAG_FILE}" ]
}

@test "failed latest report export should warn without announcing a shortcut" {
  diagnostic_reset_context
  mkdir "${HY2_DIAG_LATEST}"
  run diagnostic_render_summary
  [[ "${output}" == *'最新报告快捷路径更新失败'* ]]
  [[ "${output}" != *'最新报告快捷路径:'* ]]
  [ -z "$(ls -A "${HY2_DIAG_LATEST}")" ]
  [ -f "${DIAG_FILE}" ]
}

@test "latest diagnostic export should replace a symlink without changing its target" {
  local victim="${TEST_TMP_DIR}/unrelated-file"
  printf 'keep-original' > "${victim}"
  ln -s "${victim}" "${HY2_DIAG_LATEST}"
  [[ -L "${HY2_DIAG_LATEST}" ]] || skip 'Native symlinks are unavailable on this platform'
  diagnostic_reset_context
  diagnostic_print_result 'OK' 'safe-report'
  diagnostic_render_summary
  [ "$(<"${victim}")" = 'keep-original' ]
  [ ! -L "${HY2_DIAG_LATEST}" ]
  grep -Fq 'safe-report' "${HY2_DIAG_LATEST}"
}

@test "show_service_failure_hint should classify permission denied logs" {
  journalctl() {
    cat "${TEST_FIXTURE_DIR}/logs/permission-denied.log"
  }

  run show_service_failure_hint
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"服务用户无权读取 config.yaml"* ]]
}
