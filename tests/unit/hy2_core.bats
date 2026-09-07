#!/usr/bin/env bats

setup() {
  export HY2_LIB_ONLY=1
  # shellcheck source=../../hy2.sh
  source "${BATS_TEST_DIRNAME}/../../hy2.sh"

  TMP_DIR="$(mktemp -d)"
  export HY2_CONF_DIR="${TMP_DIR}/etc-hysteria"
  export HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
  export HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
  export HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
  export HY2_DIAG_DIR="${TMP_DIR}"
  export HY2_DIAG_LATEST="${TMP_DIR}/hy2-diagnose-latest.log"
  mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"
}

teardown() {
  rm -rf "${TMP_DIR}"
}

@test "validators should accept/reject expected values" {
  run is_valid_port "443"
  [ "${status}" -eq 0 ]

  run is_valid_port "70000"
  [ "${status}" -ne 0 ]

  run is_valid_port "00008"
  [ "${status}" -eq 0 ]

  run is_positive_integer "00008"
  [ "${status}" -eq 0 ]

  run is_positive_integer "0"
  [ "${status}" -ne 0 ]

  run is_valid_domain "example.com"
  [ "${status}" -eq 0 ]

  run is_valid_domain "-bad.com"
  [ "${status}" -ne 0 ]

  run is_valid_url "https://example.com"
  [ "${status}" -eq 0 ]

  run is_valid_url "ftp://example.com"
  [ "${status}" -ne 0 ]
}

@test "version comparison should handle release boundaries" {
  run version_at_least "v2.12.2" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -eq 0 ]

  run version_at_least "2.13.0" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -eq 0 ]

  run version_at_least "2.12.1" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -ne 0 ]

  run version_at_least "invalid" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -ne 0 ]
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

  cat > "${HY2_CONF_FILE}" <<'EOF'
listen: :443
acme:
  domains:
    - example.com
EOF
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
  cat > "${backup_dir}/config.yaml" <<'EOF'
listen: :443
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
EOF

  run validate_manual_backup_dir "${backup_dir}"
  [ "${status}" -ne 0 ]

  printf "backup-cert" > "${backup_dir}/server.crt"
  printf "backup-key" > "${backup_dir}/server.key"
  run validate_manual_backup_dir "${backup_dir}"
  [ "${status}" -eq 0 ]
}

@test "show_service_failure_hint should classify permission denied logs" {
  journalctl() {
    cat <<'EOF'
FATAL failed to read server config {"error":"open /etc/hysteria/config.yaml: permission denied"}
EOF
  }

  run show_service_failure_hint
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"服务用户无权读取 config.yaml"* ]]
}

@test "sing-box full template should use modern rule-set format" {
  public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
  rendered="$(render_singbox_full_template "8.8.8.8" "45612" "20" "100" "abc123" "bing.com" "true" "${public_key_sha}")"
  [[ "${rendered}" == *'"rule_set": "geosite-cn"'* ]]
  [[ "${rendered}" == *'"action": "hijack-dns"'* ]]
  [[ "${rendered}" == *'"address": ['* ]]
  [[ "${rendered}" == *'"type": "https"'* ]]
  [[ "${rendered}" == *'"detour": "proxy"'* ]]
  [[ "${rendered}" == *'"default_domain_resolver": "cf"'* ]]
  [[ "${rendered}" == *'"http_clients": ['* ]]
  [[ "${rendered}" == *'"tag": "rule-set-proxy"'* ]]
  [[ "${rendered}" == *'"default_http_client": "rule-set-proxy"'* ]]
  [[ "${rendered}" != *'"download_detour"'* ]]
  [[ "${rendered}" == *'"certificate_public_key_sha256": ["'"${public_key_sha}"'"]'* ]]
  [[ "${rendered}" != *'"geosite":'* ]]
  [[ "${rendered}" != *'"geoip":'* ]]
  [[ "${rendered}" != *'"inet4_address"'* ]]
  [[ "${rendered}" != *'"type": "dns"'* ]]
  [[ "${rendered}" != *'"detour": "direct"'* ]]
}

@test "self-signed sing-box output should require a public key pin" {
  run render_singbox_outbound_snippet "8.8.8.8" "443" "20" "100" "abc123" "bing.com" "true"
  [ "${status}" -ne 0 ]

  run render_singbox_full_template "8.8.8.8" "443" "20" "100" "abc123" "bing.com" "true" "invalid"
  [ "${status}" -ne 0 ]

  run render_singbox_outbound_snippet "8.8.8.8" "443" "20" "100" "abc123" "example.com" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'certificate_public_key_sha256'* ]]
}

@test "sing-box public key field should preserve requested indentation" {
  public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
  run render_singbox_public_key_field "true" "${public_key_sha}" "    "
  [ "${status}" -eq 0 ]
  [ "${output}" = $',\n    "certificate_public_key_sha256": ["'"${public_key_sha}"'"]' ]

  run render_singbox_public_key_field "invalid" "${public_key_sha}" "    "
  [ "${status}" -ne 0 ]
}

@test "client export safety gate should require both self-signed pins" {
  wait_return() { :; }
  insecure="true"
  cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="

  run ensure_client_export_material "" "${public_key_sha}"
  [ "${status}" -ne 0 ]
  run ensure_client_export_material "${cert_sha}" ""
  [ "${status}" -ne 0 ]
  run ensure_client_export_material "${cert_sha}" "${public_key_sha}"
  [ "${status}" -eq 0 ]
}

@test "certificate public key hash should be valid base64 SHA-256" {
  command -v openssl >/dev/null 2>&1 || skip "openssl is not installed"
  if [[ "${OSTYPE:-}" == msys* ]]; then
    export MSYS2_ARG_CONV_EXCL="/CN="
  fi
  generate_self_signed_certificate "bing.com"
  [ "$?" -eq 0 ]

  run get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt"
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^[A-Za-z0-9+/]{43}=$ ]]
}

@test "v2rayN insecure notice should warn self-signed users" {
  run print_v2rayn_insecure_notice
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"v2rayN / Xray 自签证书提醒"* ]]
  [[ "${output}" == *"insecure=1"* ]]
  [[ "${output}" == *"pinSHA256"* ]]
  [[ "${output}" == *"pcs"* ]]
  [[ "${output}" == *"Xray-core >= 26.2.6"* ]]
  [[ "${output}" == *"v2rayN >= 7.24.9"* ]]
  [[ "${output}" == *"Sing-box >= 1.13.0"* ]]
  [[ "${output}" == *"pinnedPeerCertSha256"* ]]
  [[ "${output}" == *"已移除 allowInsecure"* ]]
  [[ "${output}" == *"重新导入节点"* ]]
}

@test "hysteria2 share URL should use URI boolean values" {
  cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  run render_hysteria2_share_url "8.8.8.8" "45612" "pa ss" "bing.com" "true" "${cert_sha}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "hysteria2://pa%20ss@8.8.8.8:45612/?sni=bing.com&insecure=1&pinSHA256=${cert_sha}&pcs=${cert_sha}#hy2ctl" ]
  [[ "${output}" != *"allowInsecure"* ]]

  run render_hysteria2_share_url "2001:db8::1" "443" "abc123" "example.com" "false"
  [ "${status}" -eq 0 ]
  [ "${output}" = "hysteria2://abc123@[2001:db8::1]:443/?sni=example.com#hy2ctl" ]
}

@test "hysteria2 share URL should reject invalid insecure values" {
  run render_hysteria2_share_url "8.8.8.8" "443" "abc123" "bing.com" "yes"
  [ "${status}" -ne 0 ]
}

@test "self-signed hysteria2 share URL should require a certificate fingerprint" {
  run render_hysteria2_share_url "8.8.8.8" "443" "abc123" "bing.com" "true"
  [ "${status}" -ne 0 ]
}

@test "URL encoder should percent-encode UTF-8 bytes" {
  run url_encode "密码"
  [ "${status}" -eq 0 ]
  [ "${output}" = "%E5%AF%86%E7%A0%81" ]
}

@test "certificate fingerprint normalizer should return lowercase hex" {
  raw="sha256 Fingerprint=AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
  run normalize_certificate_sha256 "${raw}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899" ]

  run normalize_certificate_sha256 "not-a-fingerprint"
  [ "${status}" -ne 0 ]
}

@test "native Hysteria2 YAML should include certificate pin when available" {
  cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  run render_v2rayn_yaml_snippet "8.8.8.8" "45612" "abc123" "20" "100" "bing.com" "true" "${cert_sha}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"pinSHA256: ${cert_sha}"* ]]
}

@test "native Hysteria2 YAML should quote special values and format IPv6" {
  run render_v2rayn_yaml_snippet "2001:db8::1" "443" "pa'ss #1" "20" "100" "example.com" "false"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"server: '[2001:db8::1]:443'"* ]]
  [[ "${output}" == *"auth: 'pa''ss #1'"* ]]
  [[ "${output}" == *"sni: 'example.com'"* ]]
}

@test "verify_hy2_installer should require Bash syntax and shebang" {
  installer_file="${TMP_DIR}/hysteria-installer.sh"
  cat > "${installer_file}" <<'EOF'
#!/usr/bin/env bash
echo "Hysteria installer"
EOF

  run verify_hy2_installer "${installer_file}"
  [ "${status}" -eq 0 ]

  printf '\nif then\n' >> "${installer_file}"
  run verify_hy2_installer "${installer_file}"
  [ "${status}" -ne 0 ]
}

@test "verify_downloaded_panel should require a valid panel version" {
  panel_file="${TMP_DIR}/hy2-valid.sh"
  cat > "${panel_file}" <<'EOF'
#!/bin/bash
sh_ver="v9.8.7"
echo "hy2ctl 管理面板"
main_menu() { :; }
EOF

  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -eq 0 ]
  run extract_panel_version "${panel_file}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "v9.8.7" ]

  printf '\nif then\n' >> "${panel_file}"
  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -ne 0 ]
  sed -i '$d' "${panel_file}"
  sed -i '$d' "${panel_file}"

  sed -i '/^sh_ver=/d' "${panel_file}"
  run verify_downloaded_panel "${panel_file}"
  [ "${status}" -ne 0 ]
}
