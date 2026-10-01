#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

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
  run version_at_least "v2.12.3" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -eq 0 ]

  run version_at_least "2.13.0" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -eq 0 ]

  run version_at_least "2.12.2" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -ne 0 ]

  run version_at_least "invalid" "${RECOMMENDED_HY2_VERSION}"
  [ "${status}" -ne 0 ]
}

@test "URL encoder should percent-encode UTF-8 bytes" {
  run url_encode "密码"
  [ "${status}" -eq 0 ]
  [ "${output}" = "%E5%AF%86%E7%A0%81" ]
}
