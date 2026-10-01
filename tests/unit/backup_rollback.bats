#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "failed snapshot copy should preserve the previous recoverable snapshot" {
  local name
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    printf 'stable-%s' "${name}" > "${HY2_CONF_DIR}/${name}"
  done
  backup_runtime_files
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    printf 'changed-%s' "${name}" > "${HY2_CONF_DIR}/${name}"
  done
  cp() {
    if [[ "$*" == *'server.key.bak'* ]]; then return 1; fi
    command cp "$@"
  }
  run backup_runtime_files
  [ "${status}" -ne 0 ]
  unset -f cp
  restore_runtime_files
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    [ "$(<"${HY2_CONF_DIR}/${name}")" = "stable-${name}" ]
  done
}

@test "manual restore should roll back when restart succeeds but service exits" {
  sleep() { :; }
  cp "${TEST_FIXTURE_DIR}/config/ca.yaml" "${HY2_CONF_FILE}"
  create_manual_backup
  printf 'current-config' > "${HY2_CONF_FILE}"
  printf 'current-meta' > "${HY2_META_FILE}"
  printf 'current-cert' > "${HY2_CONF_DIR}/server.crt"
  printf 'current-key' > "${HY2_CONF_DIR}/server.key"
  restart_calls=0
  systemctl() {
    case "${1:-}" in
      show) echo root ;;
      restart) restart_calls=$((restart_calls + 1)); return 0 ;;
      is-active) (( restart_calls > 1 )) ;;
      *) return 0 ;;
    esac
  }
  run restore_latest_manual_backup
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'本次手动恢复未生效'* ]]
  [ "$(<"${HY2_CONF_FILE}")" = 'current-config' ]
  [ "$(<"${HY2_META_FILE}")" = 'current-meta' ]
  [ "$(<"${HY2_CONF_DIR}/server.crt")" = 'current-cert' ]
  [ "$(<"${HY2_CONF_DIR}/server.key")" = 'current-key' ]
}

@test "config restart should fail and roll back when the service does not stay active" {
  sleep() { :; }
  printf 'stable-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  printf 'changed-config' > "${HY2_CONF_FILE}"
  restart_calls=0
  systemctl() {
    case "${1:-}" in
      restart) restart_calls=$((restart_calls + 1)); return 0 ;;
      is-active) (( restart_calls > 1 )) ;;
      show) echo root ;;
      *) return 0 ;;
    esac
  }
  run restart_service_with_rollback
  [ "${status}" -ne 0 ]
  [ "$(<"${HY2_CONF_FILE}")" = 'stable-config' ]
}

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
  local snapshot_dir
  snapshot_dir="$(get_runtime_snapshot_dir)"
  [ ! -e "${snapshot_dir}/server.crt.bak" ]
  [ -f "${snapshot_dir}/server.crt.bak.absent" ]
  [ "$(<"${HY2_BACKUP_DIR}/server.crt.bak")" = 'stale-cert' ]

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

@test "incomplete runtime snapshot should not modify any live files" {
  local name
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    printf 'backup-%s' "${name}" > "${HY2_CONF_DIR}/${name}"
  done
  backup_runtime_files
  rm "$(get_runtime_snapshot_dir)/server.key.bak"
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    printf 'current-%s' "${name}" > "${HY2_CONF_DIR}/${name}"
  done

  run restore_runtime_files
  [ "${status}" -ne 0 ]
  for name in "${RUNTIME_FILE_NAMES[@]}"; do
    [ "$(<"${HY2_CONF_DIR}/${name}")" = "current-${name}" ]
  done
}

@test "conflicting snapshot states should be rejected before restoring" {
  printf 'backup-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  printf 'current-config' > "${HY2_CONF_FILE}"
  printf 'unexpected-key' > "$(get_runtime_snapshot_dir)/server.key.bak"

  run restore_runtime_files
  [ "${status}" -ne 0 ]
  [ "$(<"${HY2_CONF_FILE}")" = 'current-config' ]
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

@test "failed snapshot publication should preserve old snapshot and clean staging" {
  printf 'stable-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  local previous_dir
  previous_dir="$(get_runtime_snapshot_dir)"
  printf 'changed-config' > "${HY2_CONF_FILE}"
  mkdir "${HY2_BACKUP_DIR}/manual-preserved"
  printf 'manual-copy' > "${HY2_BACKUP_DIR}/manual-preserved/config.yaml"
  mv() {
    [[ "${@: -1}" != "${HY2_BACKUP_DIR}/runtime.current" ]] || return 1
    command mv "$@"
  }
  run backup_runtime_files
  [ "${status}" -ne 0 ]
  [ "$(get_runtime_snapshot_dir)" = "${previous_dir}" ]
  [ "$(find "${HY2_BACKUP_DIR}" -maxdepth 1 -type d -name 'runtime-*' | wc -l)" -eq 1 ]
  [ "$(<"${HY2_BACKUP_DIR}/manual-preserved/config.yaml")" = 'manual-copy' ]
  restore_runtime_files
  [ "$(<"${HY2_CONF_FILE}")" = 'stable-config' ]
}

@test "successful snapshot publication should supersede only the old automatic snapshot" {
  printf 'first-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  local previous_dir
  previous_dir="$(get_runtime_snapshot_dir)"
  mkdir "${HY2_BACKUP_DIR}/manual-preserved"
  printf 'manual-copy' > "${HY2_BACKUP_DIR}/manual-preserved/config.yaml"
  printf 'second-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  [ "$(get_runtime_snapshot_dir)" != "${previous_dir}" ]
  [ ! -e "${previous_dir}" ]
  [ -f "$(get_runtime_snapshot_dir)/config.yaml.bak" ]
  [ "$(<"${HY2_BACKUP_DIR}/manual-preserved/config.yaml")" = 'manual-copy' ]
  printf 'broken-config' > "${HY2_CONF_FILE}"
  restore_runtime_files
  [ "$(<"${HY2_CONF_FILE}")" = 'second-config' ]
}

@test "legacy flat runtime snapshots should remain recoverable after upgrade" {
  printf 'legacy-config' > "${HY2_BACKUP_DIR}/config.yaml.bak"
  local name
  for name in meta.info server.crt server.key; do
    : > "${HY2_BACKUP_DIR}/${name}.bak.absent"
    printf 'generated-file' > "${HY2_CONF_DIR}/${name}"
  done
  [ "$(get_runtime_snapshot_dir)" = "${HY2_BACKUP_DIR}" ]
  restore_runtime_files
  [ "$(<"${HY2_CONF_FILE}")" = 'legacy-config' ]
  [ ! -e "${HY2_META_FILE}" ]
  [ ! -e "${HY2_CONF_DIR}/server.crt" ]
  [ ! -e "${HY2_CONF_DIR}/server.key" ]
}

@test "invalid snapshot pointers should not fall back to obsolete backups or escape the root" {
  printf 'legacy-config' > "${HY2_BACKUP_DIR}/config.yaml.bak"
  printf 'current-config' > "${HY2_CONF_FILE}"
  local pointer
  for pointer in '../outside' '/tmp/runtime-ABC123' 'runtime-missing' $'runtime-ABC123\nother-entry'; do
    printf '%s\n' "${pointer}" > "${HY2_BACKUP_DIR}/runtime.current"
    run restore_runtime_files
    [ "${status}" -ne 0 ]
    [ "$(<"${HY2_CONF_FILE}")" = 'current-config' ]
  done
}

@test "snapshot cleanup should reject the current snapshot and unrelated directories" {
  printf 'current-config' > "${HY2_CONF_FILE}"
  backup_runtime_files
  run discard_runtime_snapshot "$(get_runtime_snapshot_dir)"
  [ "${status}" -ne 0 ]
  [ -f "$(get_runtime_snapshot_dir)/config.yaml.bak" ]
  mkdir "${HY2_BACKUP_DIR}/manual-protected"
  run discard_runtime_snapshot "${HY2_BACKUP_DIR}/manual-protected"
  [ "${status}" -ne 0 ]
  [ -d "${HY2_BACKUP_DIR}/manual-protected" ]
  run discard_runtime_snapshot "${HY2_BACKUP_DIR}"
  [ "${status}" -ne 0 ]
}

@test "manual restore should report rollback failure if the reverted service also exits" {
  sleep() { :; }
  cp "${TEST_FIXTURE_DIR}/config/ca.yaml" "${HY2_CONF_FILE}"
  create_manual_backup
  printf 'current-config' > "${HY2_CONF_FILE}"
  systemctl() {
    case "${1:-}" in
      show) echo root ;;
      is-active) return 1 ;;
      *) return 0 ;;
    esac
  }
  run restore_latest_manual_backup
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'自动回滚失败'* ]]
  [[ "${output}" != *'本次手动恢复未生效'* ]]
  [ "$(<"${HY2_CONF_FILE}")" = 'current-config' ]
}
