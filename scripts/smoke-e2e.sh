#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

fail() {
    echo "[ERROR] $1"
    exit 1
}

assert_eq() {
    local actual="$1"
    local expected="$2"
    local label="$3"
    if [[ "${actual}" != "${expected}" ]]; then
        fail "${label} (expected: ${expected}, actual: ${actual})"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local label="$3"
    if [[ "${haystack}" != *"${needle}"* ]]; then
        fail "${label} (missing: ${needle})"
    fi
}

export HY2_LIB_ONLY=1
# shellcheck source=../hy2.sh
source "${ROOT_DIR}/hy2.sh"

__mock_systemctl_mode="always_success"
__mock_systemctl_calls=0
__mock_journalctl_log=""
systemctl() {
    if [[ "${1:-}" == "restart" ]]; then
        __mock_systemctl_calls=$((__mock_systemctl_calls + 1))
        case "${__mock_systemctl_mode}" in
            always_success) return 0 ;;
            fail_then_success)
                if [[ "${__mock_systemctl_calls}" -eq 1 ]]; then
                    return 1
                fi
                return 0
                ;;
            always_fail) return 1 ;;
        esac
    fi
    return 0
}
journalctl() {
    printf "%s\n" "${__mock_journalctl_log}"
    return 0
}

tmp_dir="$(mktemp -d)"
cleanup() {
    rm -rf "${tmp_dir}"
}
trap cleanup EXIT

HY2_CONF_DIR="${tmp_dir}/etc-hysteria"
HY2_CONF_FILE="${HY2_CONF_DIR}/config.yaml"
HY2_META_FILE="${HY2_CONF_DIR}/meta.info"
HY2_BACKUP_DIR="${HY2_CONF_DIR}/backup"
HY2_DIAG_DIR="${tmp_dir}"
HY2_DIAG_LATEST="${HY2_DIAG_DIR}/hy2-diagnose-latest.log"
mkdir -p "${HY2_CONF_DIR}" "${HY2_BACKUP_DIR}"

echo "[INFO] Running validator checks..."
is_valid_port "1" || fail "port 1 should be valid"
is_valid_port "65535" || fail "port 65535 should be valid"
is_valid_port "00008" || fail "port with leading zeros should be parsed as decimal"
! is_valid_port "0" || fail "port 0 should be invalid"
! is_valid_port "70000" || fail "port 70000 should be invalid"
is_positive_integer "00008" || fail "positive integer with leading zeros should be valid"
! is_positive_integer "0" || fail "zero should not be a positive integer"
is_valid_domain "example.com" || fail "example.com should be valid domain"
! is_valid_domain "-bad.com" || fail "-bad.com should be invalid domain"
is_valid_url "https://bing.com" || fail "https URL should be valid"
! is_valid_url "ftp://example.com" || fail "ftp URL should be invalid"
is_valid_email "dev@example.com" || fail "email should be valid"
! is_valid_email "dev@localhost" || fail "email without TLD should be invalid"
version_at_least "v2.12.2" "${RECOMMENDED_HY2_VERSION}" || fail "equal versions should satisfy minimum"
version_at_least "2.13.0" "${RECOMMENDED_HY2_VERSION}" || fail "newer version should satisfy minimum"
! version_at_least "2.12.1" "${RECOMMENDED_HY2_VERSION}" || fail "older version should not satisfy minimum"
! version_at_least "invalid" "${RECOMMENDED_HY2_VERSION}" || fail "invalid version should be rejected"

echo "[INFO] Running config generation checks..."
write_self_signed_config "443" "pa'ss" "https://example.com"
write_meta_info "1.2.3.4" "443" "pa'ss" "bing.com" "true" "30" "120"

conf_text="$(cat "${HY2_CONF_FILE}")"
assert_contains "${conf_text}" "listen: :443" "self-signed config listen missing"
assert_contains "${conf_text}" "password: 'pa''ss'" "password yaml escaping mismatch"

read_meta_info || fail "read_meta_info should succeed for valid meta"
assert_eq "${ip}" "1.2.3.4" "meta ip mismatch"
assert_eq "${port}" "443" "meta port mismatch"
assert_eq "${password}" "pa'ss" "meta password mismatch"
assert_eq "${sni}" "bing.com" "meta sni mismatch"
assert_eq "${insecure}" "true" "meta insecure mismatch"
assert_eq "${up_mbps}" "30" "meta up_mbps mismatch"
assert_eq "${down_mbps}" "120" "meta down_mbps mismatch"

echo "[INFO] Running SNI picker checks..."
pick_self_signed_sni <<< ""
assert_eq "${PICKED_SNI}" "bing.com" "default SNI selection mismatch"

pick_self_signed_sni <<< "4"
assert_eq "${PICKED_SNI}" "www.microsoft.com" "preset SNI selection mismatch"

pick_self_signed_sni <<< $'0\ncustom.example.com\n'
assert_eq "${PICKED_SNI}" "custom.example.com" "manual SNI input mismatch"

pick_self_signed_sni <<< "9"
assert_eq "${PICKED_SNI}" "bing.com" "invalid SNI fallback mismatch"

echo "[INFO] Running staged config input checks..."
reset_hy2_config_draft
collect_hy2_connection_settings <<< $'00443\nfixed-password\nhttps://example.com\n25\n125\n'
assert_eq "${HY2_DRAFT_PORT}" "443" "draft port normalization mismatch"
assert_eq "${HY2_DRAFT_PASSWORD}" "fixed-password" "draft password mismatch"
assert_eq "${HY2_DRAFT_MASQUERADE_URL}" "https://example.com" "draft masquerade URL mismatch"
assert_eq "${HY2_DRAFT_UP_MBPS}" "25" "draft upload bandwidth mismatch"
assert_eq "${HY2_DRAFT_DOWN_MBPS}" "125" "draft download bandwidth mismatch"

collect_hy2_certificate_settings <<< $'1\nexample.com\n\n'
assert_eq "${HY2_DRAFT_CERT_TYPE}" "1" "draft certificate mode mismatch"
assert_eq "${HY2_DRAFT_DOMAIN}" "example.com" "draft certificate domain mismatch"
assert_eq "${HY2_DRAFT_EMAIL}" "admin@example.com" "draft default email mismatch"
assert_eq "${HY2_DRAFT_SNI}" "example.com" "draft CA SNI mismatch"
assert_eq "${HY2_DRAFT_INSECURE}" "false" "draft CA security mode mismatch"

reset_hy2_config_draft
collect_hy2_connection_settings <<< $'\n\n\n\n\n'
assert_eq "${HY2_DRAFT_PORT}" "8443" "default draft port mismatch"
[[ "${HY2_DRAFT_PASSWORD}" =~ ^[0-9a-f]{32}$ ]] || fail "default draft password format mismatch"
assert_eq "${HY2_DRAFT_MASQUERADE_URL}" "https://bing.com" "default draft masquerade URL mismatch"
assert_eq "${HY2_DRAFT_UP_MBPS}" "50" "default draft upload bandwidth mismatch"
assert_eq "${HY2_DRAFT_DOWN_MBPS}" "200" "default draft download bandwidth mismatch"

collect_hy2_certificate_settings <<< $'\n\n'
assert_eq "${HY2_DRAFT_CERT_TYPE}" "2" "default draft certificate mode mismatch"
assert_eq "${HY2_DRAFT_SNI}" "bing.com" "default draft self-signed SNI mismatch"
assert_eq "${HY2_DRAFT_INSECURE}" "true" "default draft self-signed security mode mismatch"

echo "[INFO] Running update submenu checks..."
clear() { :; }
wait_return() { :; }
__mock_update_action=""
install_hy2_core() { __mock_update_action="core"; }
update_panel_script() { __mock_update_action="panel"; }
show_update_menu <<< "1"
assert_eq "${__mock_update_action}" "core" "update submenu core dispatch mismatch"
show_update_menu <<< "2"
assert_eq "${__mock_update_action}" "panel" "update submenu panel dispatch mismatch"

echo "[INFO] Running diagnostic context checks..."
diagnostic_reset_context
diagnostic_print_result "OK" "context-ok"
diagnostic_print_result "WARN" "context-warn"
diagnostic_add_item "same conclusion" "first suggestion" "first command"
diagnostic_add_item "same conclusion" "second suggestion" "second command"
assert_eq "${DIAG_OK_COUNT}" "1" "diagnostic OK count mismatch"
assert_eq "${DIAG_WARN_COUNT}" "1" "diagnostic WARN count mismatch"
assert_eq "${#DIAG_CONCLUSIONS[@]}" "1" "diagnostic suggestion deduplication mismatch"
diagnostic_render_summary
grep -Fq "诊断结果: 1 OK / 1 WARN / 0 FAIL" "${HY2_DIAG_LATEST}" || fail "diagnostic summary was not exported"
grep -Fq "[建议] first suggestion" "${HY2_DIAG_LATEST}" || fail "deduplicated diagnostic suggestion was not exported"

echo "[INFO] Running share snippet checks..."
cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
share_url="$(render_hysteria2_share_url "8.8.8.8" "45612" "pa ss" "bing.com" "true" "${cert_sha}")"
assert_eq "${share_url}" "hysteria2://pa%20ss@8.8.8.8:45612/?sni=bing.com&insecure=1&pinSHA256=${cert_sha}&pcs=${cert_sha}#hy2ctl" "Hysteria2 share URL mismatch"
if [[ "${share_url}" == *"insecure=true"* ]]; then
    fail "Hysteria2 share URL must use insecure=1 instead of insecure=true"
fi
if [[ "${share_url}" == *"allowInsecure"* ]]; then
    fail "Hysteria2 share URL must not contain removed allowInsecure"
fi
if render_hysteria2_share_url "8.8.8.8" "45612" "abc123" "bing.com" "true" >/dev/null 2>&1; then
    fail "self-signed Hysteria2 share URL must require a certificate fingerprint"
fi

assert_eq "$(url_encode "密码")" "%E5%AF%86%E7%A0%81" "UTF-8 URL encoding mismatch"

secure_share_url="$(render_hysteria2_share_url "2001:db8::1" "443" "abc123" "example.com" "false")"
assert_eq "${secure_share_url}" "hysteria2://abc123@[2001:db8::1]:443/?sni=example.com#hy2ctl" "secure Hysteria2 share URL mismatch"

normalized_sha="$(normalize_certificate_sha256 "sha256 Fingerprint=01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF:01:23:45:67:89:AB:CD:EF")"
assert_eq "${normalized_sha}" "${cert_sha}" "certificate SHA-256 normalization mismatch"

singbox_public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="
rendered_json="$(render_singbox_outbound_snippet "8.8.8.8" "45612" "20" "100" "abc123" "bing.com" "true" "${singbox_public_key_sha}")"
assert_contains "${rendered_json}" "\"type\": \"hysteria2\"" "sing-box type missing"
assert_contains "${rendered_json}" "\"server_port\": 45612" "sing-box port missing"
assert_contains "${rendered_json}" "\"server_name\": \"bing.com\"" "sing-box sni missing"
assert_contains "${rendered_json}" "\"certificate_public_key_sha256\": [\"${singbox_public_key_sha}\"]" "sing-box public key pin missing"

rendered_full_json="$(render_singbox_full_template "8.8.8.8" "45612" "20" "100" "abc123" "bing.com" "true" "${singbox_public_key_sha}")"
assert_contains "${rendered_full_json}" "\"rule_set\": \"geosite-cn\"" "sing-box full template rule_set missing"
assert_contains "${rendered_full_json}" "\"action\": \"hijack-dns\"" "sing-box full template dns action missing"
assert_contains "${rendered_full_json}" "\"address\": [" "sing-box full template tun address missing"
assert_contains "${rendered_full_json}" "\"type\": \"https\"" "sing-box full template new dns server missing"
assert_contains "${rendered_full_json}" "\"detour\": \"proxy\"" "sing-box full template remote dns detour missing"
assert_contains "${rendered_full_json}" "\"default_domain_resolver\": \"cf\"" "sing-box full template default resolver missing"
assert_contains "${rendered_full_json}" "\"http_clients\": [" "sing-box full template HTTP clients missing"
assert_contains "${rendered_full_json}" "\"tag\": \"rule-set-proxy\"" "sing-box full template rule-set HTTP client tag missing"
assert_contains "${rendered_full_json}" "\"default_http_client\": \"rule-set-proxy\"" "sing-box full template default HTTP client missing"
assert_contains "${rendered_full_json}" "\"certificate_public_key_sha256\": [\"${singbox_public_key_sha}\"]" "sing-box full template public key pin missing"
if [[ "${rendered_full_json}" == *"\"geosite\":"* || "${rendered_full_json}" == *"\"geoip\":"* || "${rendered_full_json}" == *"\"inet4_address\""* || "${rendered_full_json}" == *"\"type\": \"dns\""* || "${rendered_full_json}" == *"\"download_detour\""* ]]; then
    fail "sing-box full template should not contain removed legacy fields"
fi
if [[ "${rendered_full_json}" == *"\"detour\": \"direct\""* ]]; then
    fail "sing-box full template should not detour local dns to direct outbound"
fi
if render_singbox_outbound_snippet "8.8.8.8" "443" "20" "100" "abc123" "bing.com" "true" >/dev/null 2>&1; then
    fail "self-signed sing-box output must require a public key pin"
fi
secure_singbox_json="$(render_singbox_outbound_snippet "8.8.8.8" "443" "20" "100" "abc123" "example.com" "false")"
if [[ "${secure_singbox_json}" == *"certificate_public_key_sha256"* ]]; then
    fail "CA sing-box output should not contain a self-signed public key pin"
fi

if [[ "${OSTYPE:-}" == msys* ]]; then
    export MSYS2_ARG_CONV_EXCL="/CN="
fi
generate_self_signed_certificate "bing.com" || fail "self-signed certificate generation should succeed"
generated_public_key_sha="$(get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt")"
is_valid_certificate_public_key_sha256 "${generated_public_key_sha}" || fail "generated public key SHA-256 should be valid"

rendered_yaml="$(render_v2rayn_yaml_snippet "8.8.8.8" "45612" "abc123" "20" "100" "bing.com" "true" "${cert_sha}")"
assert_contains "${rendered_yaml}" "server: '8.8.8.8:45612'" "v2rayN server line missing"
assert_contains "${rendered_yaml}" "auth: 'abc123'" "v2rayN auth line missing"
assert_contains "${rendered_yaml}" "pinSHA256: ${cert_sha}" "native Hysteria2 certificate pin missing"

special_yaml="$(render_v2rayn_yaml_snippet "2001:db8::1" "443" "pa'ss #1" "20" "100" "example.com" "false")"
assert_contains "${special_yaml}" "server: '[2001:db8::1]:443'" "v2rayN IPv6 server formatting mismatch"
assert_contains "${special_yaml}" "auth: 'pa''ss #1'" "v2rayN auth YAML escaping mismatch"

notice_output="$(print_v2rayn_insecure_notice 2>&1)"
assert_contains "${notice_output}" "v2rayN / Xray 自签证书提醒" "v2rayN insecure notice title missing"
assert_contains "${notice_output}" "insecure=1" "v2rayN insecure notice URI value missing"
assert_contains "${notice_output}" "pinSHA256" "v2rayN certificate pin notice missing"
assert_contains "${notice_output}" "pcs" "v2rayN Xray URI pin parameter missing"
assert_contains "${notice_output}" "Xray-core >= 26.2.6" "v2rayN Xray version notice missing"
assert_contains "${notice_output}" "v2rayN >= 7.24.9" "v2rayN security version notice missing"
assert_contains "${notice_output}" "Sing-box >= 1.13.0" "sing-box pin version notice missing"
assert_contains "${notice_output}" "pinnedPeerCertSha256" "v2rayN Xray pin mapping notice missing"
assert_contains "${notice_output}" "已移除 allowInsecure" "removed allowInsecure notice missing"

assert_eq "$(format_host_for_url "2001:db8::1")" "[2001:db8::1]" "IPv6 host formatting mismatch"
assert_eq "$(format_host_for_url "8.8.8.8")" "8.8.8.8" "IPv4 host formatting mismatch"

echo "[INFO] Running rollback checks..."
printf "stable-config" > "${HY2_CONF_FILE}"
printf "stable-meta" > "${HY2_META_FILE}"
backup_runtime_files || fail "backup_runtime_files should succeed"
printf "broken-config" > "${HY2_CONF_FILE}"

__mock_systemctl_mode="fail_then_success"
__mock_systemctl_calls=0
if restart_service_with_rollback; then
    fail "restart_service_with_rollback should fail when first restart fails"
fi
assert_eq "${__mock_systemctl_calls}" "2" "rollback restart call count mismatch"
assert_eq "$(cat "${HY2_CONF_FILE}")" "stable-config" "config should be restored after rollback"

printf "stale-cert" > "${HY2_BACKUP_DIR}/server.crt.bak"
rm -f "${HY2_CONF_DIR}/server.crt" "${HY2_CONF_DIR}/server.key"
backup_runtime_files || fail "backup_runtime_files should replace stale backup state"
[[ ! -e "${HY2_BACKUP_DIR}/server.crt.bak" ]] || fail "stale certificate backup should be removed"
[[ -f "${HY2_BACKUP_DIR}/server.crt.bak.absent" ]] || fail "missing certificate marker should be created"
printf "generated-cert" > "${HY2_CONF_DIR}/server.crt"
printf "generated-key" > "${HY2_CONF_DIR}/server.key"
restore_runtime_files || fail "restore_runtime_files should restore absent-file state"
[[ ! -e "${HY2_CONF_DIR}/server.crt" ]] || fail "generated certificate should be removed during rollback"
[[ ! -e "${HY2_CONF_DIR}/server.key" ]] || fail "generated private key should be removed during rollback"

__mock_systemctl_mode="always_success"
__mock_systemctl_calls=0
restart_service_with_rollback || fail "restart_service_with_rollback should pass when restart succeeds"
assert_eq "${__mock_systemctl_calls}" "1" "success restart call count mismatch"

echo "[INFO] Running manual backup/restore checks..."
malformed_backup="${HY2_BACKUP_DIR}/manual-malformed"
mkdir -p "${malformed_backup}"
cat > "${malformed_backup}/config.yaml" <<'EOF'
listen: :443
tls:
  cert: /etc/hysteria/server.crt
  key: /etc/hysteria/server.key
EOF
if validate_manual_backup_dir "${malformed_backup}" >/dev/null 2>&1; then
    fail "self-signed backup without certificate files should be rejected"
fi
printf "backup-cert" > "${malformed_backup}/server.crt"
printf "backup-key" > "${malformed_backup}/server.key"
validate_manual_backup_dir "${malformed_backup}" || fail "complete self-signed backup should pass validation"
rm -rf "${malformed_backup}"

cat > "${HY2_CONF_FILE}" <<'EOF'
listen: :443
acme:
  domains:
    - example.com
EOF
printf "manual-meta" > "${HY2_META_FILE}"
create_manual_backup || fail "manual CA backup should succeed"
printf "changed-config" > "${HY2_CONF_FILE}"
printf "changed-meta" > "${HY2_META_FILE}"
printf "stale-cert" > "${HY2_CONF_DIR}/server.crt"
printf "stale-key" > "${HY2_CONF_DIR}/server.key"
restore_latest_manual_backup || fail "manual CA backup restore should succeed"
grep -Fq "acme:" "${HY2_CONF_FILE}" || fail "manual backup should restore CA config"
assert_eq "$(cat "${HY2_META_FILE}")" "manual-meta" "manual backup should restore meta"
[[ ! -e "${HY2_CONF_DIR}/server.crt" ]] || fail "CA restore should remove stale certificate"
[[ ! -e "${HY2_CONF_DIR}/server.key" ]] || fail "CA restore should remove stale private key"

echo "[INFO] Running failure hint checks..."
__mock_journalctl_log="FATAL failed to read server config {\"error\": \"open /etc/hysteria/config.yaml: permission denied\"}"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "服务用户无权读取 config.yaml" "permission hint missing"

__mock_journalctl_log="listen tcp :443: bind: address already in use"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "监听端口被占用" "port conflict hint missing"

__mock_journalctl_log="acme: challenge timeout and dns lookup failed"
hint_output="$(show_service_failure_hint 2>&1 || true)"
assert_contains "${hint_output}" "CA 证书申请失败" "acme hint missing"

echo "[INFO] Running panel download verification checks..."
installer_file="${tmp_dir}/hysteria-installer.sh"
cat > "${installer_file}" <<'EOF'
#!/usr/bin/env bash
echo "Hysteria installer"
EOF
verify_hy2_installer "${installer_file}" || fail "valid Hysteria installer should pass"
printf '\nif then\n' >> "${installer_file}"
! verify_hy2_installer "${installer_file}" || fail "invalid Hysteria installer syntax should fail"

panel_file="${tmp_dir}/hy2-valid.sh"
cat > "${panel_file}" <<'EOF'
#!/bin/bash
sh_ver="v9.8.7"
echo "hy2ctl 管理面板"
main_menu() { :; }
EOF
verify_downloaded_panel "${panel_file}" || fail "valid downloaded panel should pass"
assert_eq "$(extract_panel_version "${panel_file}")" "v9.8.7" "downloaded panel version mismatch"
printf '\nif then\n' >> "${panel_file}"
! verify_downloaded_panel "${panel_file}" || fail "downloaded panel with invalid syntax should fail"
sed -i '$d' "${panel_file}"
sed -i '$d' "${panel_file}"
sed -i '/^sh_ver=/d' "${panel_file}"
! verify_downloaded_panel "${panel_file}" || fail "downloaded panel without version should fail"

if grep -Fq 'hy2.evzzz.com' hy2.sh install.sh README.md; then
    fail "deprecated custom-domain installer should not be present"
fi

echo "[OK] Smoke E2E checks passed."
