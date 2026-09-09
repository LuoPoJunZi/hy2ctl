#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
SING_BOX_BIN="${SING_BOX_BIN:-sing-box}"

# shellcheck source=../helpers/assertions.sh
source "${ROOT_DIR}/tests/helpers/assertions.sh"

validate_singbox_json() {
  local payload="$1"
  printf '%s\n' "${payload}" | "${PYTHON_BIN}" -c '
import json
import sys

data = json.load(sys.stdin)
assert data["dns"]["servers"][0]["detour"] == "proxy"
assert "detour" not in data["dns"]["servers"][1]
assert data["http_clients"][0]["tag"] == "rule-set-proxy"
assert data["http_clients"][0]["detour"] == "proxy"
assert data["route"]["default_domain_resolver"] == "cf"
assert data["route"]["default_http_client"] == "rule-set-proxy"
assert all("download_detour" not in item for item in data["route"]["rule_set"])
assert data["route"]["final"] == "proxy"
' || fail "Sing-box full template is not valid modern JSON"
}

validate_with_singbox() {
  local payload="$1"
  local label="$2"
  local config_file

  if ! command -v "${SING_BOX_BIN}" >/dev/null 2>&1; then
    if [[ "${REQUIRE_SING_BOX_CHECK:-0}" == "1" ]]; then
      fail "Required sing-box binary is unavailable: ${SING_BOX_BIN}"
    fi
    echo "[INFO] Skipping native sing-box check (${SING_BOX_BIN} not found)."
    return
  fi

  config_file="$(mktemp)"
  printf '%s\n' "${payload}" > "${config_file}"
  if ! "${SING_BOX_BIN}" check -c "${config_file}"; then
    rm -f "${config_file}"
    fail "${label} template failed native sing-box validation"
  fi
  rm -f "${config_file}"
}

export HY2_LIB_ONLY=1
# shellcheck source=../../hy2.sh
source "${ROOT_DIR}/hy2.sh"

echo "[INFO] Checking JSON escaping of all Bash-representable control bytes..."
control_text=$'密码 "quote" \\ slash\n\r\t'
for ((code = 1; code < 32; code++)); do
  printf -v escaped '\\u%04x' "${code}"
  printf -v char '%b' "${escaped}"
  control_text+="${char}"
done
escaped_text="$(json_escape "${control_text}")"
printf '"%s"\n' "${escaped_text}" | "${PYTHON_BIN}" -c '
import json
import sys
expected = "密码 \"quote\" \\ slash\n\r\t" + "".join(chr(i) for i in range(1, 32))
assert json.load(sys.stdin) == expected
' || fail "JSON escaping failed control-byte/UTF-8 round trip"

cert_sha="0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
public_key_sha="47DEQpj8HBSa+/TImW+5JCeuQeRkm5NMpJWZG3hSuFU="

echo "[INFO] Parsing CA and self-signed Sing-box templates..."
ca_json="$(render_singbox_full_template "8.8.8.8" "443" "20" "100" "abc123" "example.com" "false")"
self_json="$(render_singbox_full_template "8.8.8.8" "443" "20" "100" "abc123" "bing.com" "true" "${public_key_sha}")"
validate_singbox_json "${ca_json}"
validate_singbox_json "${self_json}"
echo "[INFO] Validating templates with sing-box 1.14+ when available..."
validate_with_singbox "${ca_json}" "CA"
validate_with_singbox "${self_json}" "self-signed"
assert_contains "${self_json}" '"certificate_public_key_sha256": ["'"${public_key_sha}"'"]' "self-signed public key pin missing"
if [[ "${ca_json}" == *"certificate_public_key_sha256"* ]]; then
  fail "CA template should not contain a self-signed public key pin"
fi

echo "[INFO] Checking client export safety gate..."
wait_return() { :; }
insecure="true"
if ensure_client_export_material "" "${public_key_sha}" >/dev/null 2>&1; then
  fail "client export should reject a missing certificate fingerprint"
fi
if ensure_client_export_material "${cert_sha}" "" >/dev/null 2>&1; then
  fail "client export should reject a missing public key pin"
fi
ensure_client_export_material "${cert_sha}" "${public_key_sha}" || fail "complete self-signed export material should pass"
insecure="false"
ensure_client_export_material "" "" || fail "CA export should not require self-signed pins"

echo "[INFO] Rendering combined client exports..."
ip="8.8.8.8"
port="443"
password="abc123"
sni="bing.com"
up_mbps="20"
down_mbps="100"
insecure="true"
clear() { :; }
summary="$(print_client_summary "${cert_sha}" "${public_key_sha}")"
assert_contains "${summary}" "服务器 IP :" "client summary server label missing"
assert_contains "${summary}" "${cert_sha}" "client summary certificate pin missing"
assert_contains "${summary}" "${public_key_sha}" "client summary public key pin missing"

exports="$(print_client_exports "${cert_sha}" "${public_key_sha}")"
assert_contains "${exports}" "pinSHA256=${cert_sha}" "Hysteria2 certificate pin missing"
assert_contains "${exports}" "pcs=${cert_sha}" "v2rayN/Xray certificate pin missing"
assert_contains "${exports}" '"certificate_public_key_sha256": ["'"${public_key_sha}"'"]' "Sing-box public key pin missing"
assert_contains "${exports}" "pinSHA256: ${cert_sha}" "native Hysteria2 YAML pin missing"
if [[ "${exports}" == *"allowInsecure"* ]]; then
  fail "client exports must not contain removed allowInsecure"
fi

echo "[OK] Client render flow passed."
