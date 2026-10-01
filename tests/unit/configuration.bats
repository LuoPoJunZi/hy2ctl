#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "atomic writer should reject directory targets without moving data inside" {
  local target="${TEST_TMP_DIR}/target-directory"
  mkdir "${target}"
  run write_file_atomic "${target}" <<< 'must-not-be-written'
  [ "${status}" -ne 0 ]
  [ -z "$(ls -A "${target}")" ]
  [ -z "$(find "${TEST_TMP_DIR}" -name 'target-directory.tmp.*')" ]
}

@test "config and meta writers should preserve values correctly" {
  write_self_signed_config "443" "pa'ss" "https://example.com"
  [ "$?" -eq 0 ]
  grep -Fq "password: 'pa''ss'" "${HY2_CONF_FILE}"

  write_meta_info "1.2.3.4" "443" "pa'ss" "bing.com" "true" "20" "100"
  [ "$?" -eq 0 ]

  read_meta_info
  [ "$?" -eq 0 ]
  [ "${ip}" = "1.2.3.4" ]
  [ "${port}" = "443" ]
  [ "${password}" = "pa'ss" ]
  [ "${sni}" = "bing.com" ]
  [ "${insecure}" = "true" ]
}

@test "staged config collectors should normalize validated values" {
  reset_hy2_config_draft
  collect_hy2_connection_settings <<< $'00443\nfixed-password\nhttps://example.com\n25\n125\n'
  [ "$?" -eq 0 ]
  [ "${HY2_DRAFT_PORT}" = "443" ]
  [ "${HY2_DRAFT_PASSWORD}" = "fixed-password" ]
  [ "${HY2_DRAFT_MASQUERADE_URL}" = "https://example.com" ]
  [ "${HY2_DRAFT_UP_MBPS}" = "25" ]
  [ "${HY2_DRAFT_DOWN_MBPS}" = "125" ]

  collect_hy2_certificate_settings <<< $'1\nexample.com\n\n'
  [ "$?" -eq 0 ]
  [ "${HY2_DRAFT_CERT_TYPE}" = "1" ]
  [ "${HY2_DRAFT_DOMAIN}" = "example.com" ]
  [ "${HY2_DRAFT_EMAIL}" = "admin@example.com" ]
  [ "${HY2_DRAFT_SNI}" = "example.com" ]
  [ "${HY2_DRAFT_INSECURE}" = "false" ]
}

@test "config collectors should apply connection and self-signed defaults" {
  reset_hy2_config_draft
  collect_hy2_connection_settings <<< $'\n\n\n\n\n'
  [ "$?" -eq 0 ]
  [ "${HY2_DRAFT_PORT}" = "8443" ]
  [[ "${HY2_DRAFT_PASSWORD}" =~ ^[0-9a-f]{32}$ ]]
  [ "${HY2_DRAFT_MASQUERADE_URL}" = "https://bing.com" ]
  [ "${HY2_DRAFT_UP_MBPS}" = "50" ]
  [ "${HY2_DRAFT_DOWN_MBPS}" = "200" ]

  collect_hy2_certificate_settings <<< $'\n\n'
  [ "$?" -eq 0 ]
  [ "${HY2_DRAFT_CERT_TYPE}" = "2" ]
  [ "${HY2_DRAFT_SNI}" = "bing.com" ]
  [ "${HY2_DRAFT_INSECURE}" = "true" ]
}
