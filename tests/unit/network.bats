#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "IP validators should handle IPv4 and compressed or embedded IPv6" {
  local address
  for address in 8.8.8.8 0.0.0.0 255.255.255.255 ::1 :: 2001:db8::1 \
    2001:4860:4860::8888 1:2:3:4:5:6:7:8 ::ffff:192.0.2.1; do
    run is_valid_ip "${address}"
    [ "${status}" -eq 0 ]
  done
  for address in '' 'error page' 256.1.2.3 1.2.3 01.2.3.4 1.2.3.4:443 \
    1:2:3:4:5:6:7 1:2:3:4:5:6:7:8:9 2001:::1 1::2::3 \
    :1:2:3:4:5:6:7 2001:db8::gg '[2001:db8::1]' 'fe80::1%eth0' \
    ::ffff:256.0.0.1 $'8.8.8.8\nip=1.2.3.4'; do
    run is_valid_ip "${address}"
    [ "${status}" -ne 0 ]
  done
}

@test "address classification should reject local and reserved IPs" {
  local address
  for address in 8.8.8.8 1.1.1.1 172.32.0.1 100.128.0.1 192.0.0.9 192.0.0.10 \
    2001:4860:4860::8888 2001:1::1 2001:3::1 2001:4:112::1 64:ff9b::808:808; do
    run is_public_ip "${address}"
    [ "${status}" -eq 0 ]
  done
  for address in 0.0.0.0 127.0.0.1 10.0.0.1 172.16.0.1 172.31.255.255 \
    192.168.1.1 169.254.1.1 100.64.0.1 100.127.255.255 198.18.0.1 \
    192.0.2.1 198.51.100.1 203.0.113.1 224.0.0.1 255.255.255.255 \
    :: ::1 fc00::1 fd12::1 fe80::1 ff02::1 2001:db8::1 2001:0DB8::1 \
    ::ffff:127.0.0.1 2001:2::1 2001:10::1 3fff::1 3fff:0fff::1 \
    64:ff9b:1::1 64:ff9b::7f00:1 192.0.0.8 192.0.0.170 '<html>error</html>'; do
    run is_public_ip "${address}"
    [ "${status}" -ne 0 ]
  done
}

@test "public IP lookup should reject error pages and try the other family" {
  curl() {
    case "$*" in
      *api64.ipify.org*) printf '2001:4860:4860::8888\n' ;;
      *) printf '<html>upstream error</html>\n' ;;
    esac
  }
  hostname() { echo '10.0.0.1'; }
  run fetch_server_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = '2001:4860:4860::8888' ]
}

@test "local fallback should prefer a public address over a private first entry" {
  curl() { return 1; }
  hostname() { printf '10.0.0.1 8.8.8.8 2001:4860:4860::8888\n'; }
  run fetch_server_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = '8.8.8.8' ]
}

@test "failed IP lookup should never return malformed response content" {
  curl() { printf 'not-an-address'; }
  hostname() { printf 'not-an-address\n'; }
  run fetch_server_ip
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

@test "IP diagnostics should not label a private local fallback as public" {
  curl() { return 1; }
  hostname() { echo '192.168.1.2'; }
  diagnostic_reset_context
  diagnostic_check_public_ip > "${TEST_TMP_DIR}/ip-diagnostic.out"
  output="$(<"${TEST_TMP_DIR}/ip-diagnostic.out")"
  [ "${DIAG_OK_COUNT}" -eq 0 ]
  [ "${DIAG_WARN_COUNT}" -eq 1 ]
  [[ "${output}" == *'本机地址'* ]]
  [[ "${output}" != *'公网 IP 探测成功'* ]]
}

@test "public IP lookup should ignore partial curl output and enforce deadlines" {
  curl() {
    printf '%s\n' "$*" >> "${TEST_TMP_DIR}/curl-args"
    printf '8.8.8.8\n'
    return 28
  }
  hostname() { echo '10.0.0.1'; }
  run fetch_server_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = '10.0.0.1' ]
  grep -Fq -- '--connect-timeout 3 --max-time 6 --max-filesize 128' "${TEST_TMP_DIR}/curl-args"
  [ "$(wc -l < "${TEST_TMP_DIR}/curl-args")" -eq 2 ]
}

@test "public IP lookup should reject oversized output even when curl reports success" {
  curl() {
    case "$*" in
      *api64.ipify.org*) printf '2001:4860:4860::8888' ;;
      *) printf '8.8.8.8%200s' '' ;;
    esac
  }
  run fetch_public_ip
  [ "${status}" -eq 0 ]
  [ "${output}" = '2001:4860:4860::8888' ]
}

@test "IP diagnostics should count an externally confirmed public address as OK" {
  curl() { printf ' 8.8.8.8\r\n'; }
  diagnostic_reset_context
  diagnostic_check_public_ip > "${TEST_TMP_DIR}/ip-diagnostic.out"
  [ "${DIAG_OK_COUNT}" -eq 1 ]
  [ "${DIAG_WARN_COUNT}" -eq 0 ]
  grep -Fq '公网 IP 探测成功: 8.8.8.8' "${TEST_TMP_DIR}/ip-diagnostic.out"
}

@test "activation should reject invalid IP data before metadata write or restart" {
  sleep() { :; }
  printf 'stable-config' > "${HY2_CONF_FILE}"
  printf 'stable-meta' > "${HY2_META_FILE}"
  backup_runtime_files
  printf 'changed-config' > "${HY2_CONF_FILE}"
  fetch_server_ip() { printf '<html>unusable</html>'; }
  systemctl() {
    [[ "${1:-}" != restart ]] || echo 'unexpected-restart'
    return 0
  }
  run activate_hy2_config 8443 test-password bing.com true 50 200
  [ "${status}" -ne 0 ]
  [[ "${output}" != *'unexpected-restart'* ]]
  [ "$(<"${HY2_CONF_FILE}")" = 'stable-config' ]
  [ "$(<"${HY2_META_FILE}")" = 'stable-meta' ]
}
