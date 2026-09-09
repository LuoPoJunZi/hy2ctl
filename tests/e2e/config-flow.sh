#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck source=../helpers/assertions.sh
source "${ROOT_DIR}/tests/helpers/assertions.sh"

# shellcheck source=../helpers/environment.sh
source "${ROOT_DIR}/tests/helpers/environment.sh"
test_load_panel
test_create_environment
tmp_dir="${TEST_TMP_DIR}"
trap test_cleanup_environment EXIT

# shellcheck source=../helpers/mocks.sh
source "${ROOT_DIR}/tests/helpers/mocks.sh"

# Mock runtime-only dependencies for deterministic e2e replay.
ensure_hy2_core_installed() { return 0; }
fetch_server_ip() { echo "9.9.9.9"; }
clear() { :; }
sleep() { :; }
echo "[INFO] Replaying config_hy2 interactive CA flow..."
if ! config_hy2 <<< $'23456\ntest-password\n\n30\n60\n1\nexample.com\n\n'; then
  fail "config_hy2 should succeed in replay flow"
fi

[[ -f "${HY2_CONF_FILE}" ]] || fail "config file not created"
[[ -f "${HY2_META_FILE}" ]] || fail "meta file not created"

assert_contains_file "${HY2_CONF_FILE}" "listen: :23456" "listen port mismatch"
assert_contains_file "${HY2_CONF_FILE}" "domains:" "acme block missing"
assert_contains_file "${HY2_CONF_FILE}" "example.com" "domain not written"
assert_contains_file "${HY2_META_FILE}" "ip=9.9.9.9" "meta ip mismatch"
assert_contains_file "${HY2_META_FILE}" "port=23456" "meta port mismatch"
assert_contains_file "${HY2_META_FILE}" "sni=example.com" "meta sni mismatch"
assert_contains_file "${HY2_META_FILE}" "insecure=false" "meta insecure mismatch"
assert_contains_file "${HY2_META_FILE}" "up_mbps=30" "meta up_mbps mismatch"
assert_contains_file "${HY2_META_FILE}" "down_mbps=60" "meta down_mbps mismatch"

echo "[INFO] Replaying config_hy2 interactive self-signed flow..."
if [[ "${OSTYPE:-}" == msys* ]]; then
  export MSYS2_ARG_CONV_EXCL="/CN="
fi
if ! config_hy2 <<< $'24457\nself-password\n\n35\n70\n2\n1\n'; then
  fail "self-signed config_hy2 should succeed in replay flow"
fi

assert_contains_file "${HY2_CONF_FILE}" "listen: :24457" "self-signed listen port mismatch"
assert_contains_file "${HY2_CONF_FILE}" "tls:" "self-signed tls block missing"
[[ -f "${HY2_CONF_DIR}/server.crt" ]] || fail "self-signed certificate was not created"
[[ -f "${HY2_CONF_DIR}/server.key" ]] || fail "self-signed private key was not created"
assert_contains_file "${HY2_META_FILE}" "port=24457" "self-signed meta port mismatch"
assert_contains_file "${HY2_META_FILE}" "sni=bing.com" "self-signed meta sni mismatch"
assert_contains_file "${HY2_META_FILE}" "insecure=true" "self-signed meta insecure mismatch"
assert_contains_file "${HY2_META_FILE}" "up_mbps=35" "self-signed meta up_mbps mismatch"
assert_contains_file "${HY2_META_FILE}" "down_mbps=70" "self-signed meta down_mbps mismatch"

echo "[INFO] Replaying pre-restart failure rollback..."
printf "stable-config" > "${HY2_CONF_FILE}"
printf "stable-meta" > "${HY2_META_FILE}"
fetch_server_ip() { :; }

if config_hy2 <<< $'34567\nnext-password\n\n40\n80\n1\nnext.example.com\n\n'; then
  fail "config_hy2 should fail when public IP lookup is empty"
fi

assert_file_equals "${HY2_CONF_FILE}" "stable-config" "config should roll back after IP lookup failure"
assert_file_equals "${HY2_META_FILE}" "stable-meta" "meta should roll back after IP lookup failure"

echo "[OK] E2E config flow replay passed."
