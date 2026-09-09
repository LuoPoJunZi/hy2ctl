#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "restart_service_with_rollback should restore backup after restart failure" {
  systemctl() {
    if [ "${1:-}" = "restart" ]; then
      restart_calls=$((restart_calls + 1))
      if [ "${restart_calls}" -eq 1 ]; then
        return 1
      fi
      return 0
    fi
    return 0
  }

  printf "stable-config" > "${HY2_CONF_FILE}"
  printf "stable-meta" > "${HY2_META_FILE}"
  printf "stable-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "stable-key" > "${HY2_CONF_DIR}/server.key"
  backup_runtime_files
  printf "broken-config" > "${HY2_CONF_FILE}"
  printf "broken-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "broken-key" > "${HY2_CONF_DIR}/server.key"

  run restart_service_with_rollback
  [ "${status}" -ne 0 ]
  [ "$(cat "${HY2_CONF_FILE}")" = "stable-config" ]
  [ "$(cat "${HY2_CONF_DIR}/server.crt")" = "stable-cert" ]
  [ "$(cat "${HY2_CONF_DIR}/server.key")" = "stable-key" ]
}

@test "runtime snapshot should replace stale backups and preserve absent files" {
  printf "stable-config" > "${HY2_CONF_FILE}"
  printf "stable-meta" > "${HY2_META_FILE}"
  printf "stale-cert" > "${HY2_BACKUP_DIR}/server.crt.bak"

  backup_runtime_files
  [ "$?" -eq 0 ]
  [ ! -e "${HY2_BACKUP_DIR}/server.crt.bak" ]
  [ -f "${HY2_BACKUP_DIR}/server.crt.bak.absent" ]

  printf "generated-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "generated-key" > "${HY2_CONF_DIR}/server.key"
  restore_runtime_files
  [ "$?" -eq 0 ]
  [ ! -e "${HY2_CONF_DIR}/server.crt" ]
  [ ! -e "${HY2_CONF_DIR}/server.key" ]
}

@test "manual CA backup restore should remove stale self-signed files" {
  systemctl() {
    case "${1:-}" in
      show) echo "root" ;;
      restart) return 0 ;;
    esac
    return 0
  }

  cp "${TEST_FIXTURE_DIR}/config/ca.yaml" "${HY2_CONF_FILE}"
  printf "stable-meta" > "${HY2_META_FILE}"
  create_manual_backup
  [ "$?" -eq 0 ]

  printf "changed-config" > "${HY2_CONF_FILE}"
  printf "changed-meta" > "${HY2_META_FILE}"
  printf "stale-cert" > "${HY2_CONF_DIR}/server.crt"
  printf "stale-key" > "${HY2_CONF_DIR}/server.key"

  restore_latest_manual_backup
  [ "$?" -eq 0 ]
  grep -Fq "acme:" "${HY2_CONF_FILE}"
  [ "$(cat "${HY2_META_FILE}")" = "stable-meta" ]
  [ ! -e "${HY2_CONF_DIR}/server.crt" ]
  [ ! -e "${HY2_CONF_DIR}/server.key" ]
}

@test "manual self-signed backup validation should require certificate files" {
  backup_dir="${HY2_BACKUP_DIR}/manual-test"
  mkdir -p "${backup_dir}"
  cp "${TEST_FIXTURE_DIR}/config/self-signed.yaml" "${backup_dir}/config.yaml"

  run validate_manual_backup_dir "${backup_dir}"
  [ "${status}" -ne 0 ]

  printf "backup-cert" > "${backup_dir}/server.crt"
  printf "backup-key" > "${backup_dir}/server.key"
  run validate_manual_backup_dir "${backup_dir}"
  [ "${status}" -eq 0 ]
}
