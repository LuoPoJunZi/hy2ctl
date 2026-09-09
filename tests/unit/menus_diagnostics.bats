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

@test "show_service_failure_hint should classify permission denied logs" {
  journalctl() {
    cat "${TEST_FIXTURE_DIR}/logs/permission-denied.log"
  }

  run show_service_failure_hint
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"服务用户无权读取 config.yaml"* ]]
}
