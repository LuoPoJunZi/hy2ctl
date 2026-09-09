#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

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

@test "certificate fingerprint normalizer should return lowercase hex" {
  raw="sha256 Fingerprint=AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99:AA:BB:CC:DD:EE:FF:00:11:22:33:44:55:66:77:88:99"
  run normalize_certificate_sha256 "${raw}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899" ]

  run normalize_certificate_sha256 "not-a-fingerprint"
  [ "${status}" -ne 0 ]
}
