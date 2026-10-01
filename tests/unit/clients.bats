#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

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

@test "v2rayN insecure notice should warn self-signed users" {
  run print_v2rayn_insecure_notice
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"v2rayN / Xray 自签证书提醒"* ]]
  [[ "${output}" == *"insecure=1"* ]]
  [[ "${output}" == *"pinSHA256"* ]]
  [[ "${output}" == *"pcs"* ]]
  [[ "${output}" == *"Xray-core >= 26.2.6"* ]]
  [[ "${output}" == *"v2rayN >= 7.24.9"* ]]
  [[ "${output}" == *"v2rayN >= 7.25.4"* ]]
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
