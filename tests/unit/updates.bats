#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

@test "sing-box test installer should pin both supported versions and bound downloads" {
  export RUNNER_TEMP="${TEST_TMP_DIR}"
  export GITHUB_PATH="${TEST_TMP_DIR}/github-path"
  export SING_BOX_TEST_COMMAND_LOG="${TEST_TMP_DIR}/installer-commands"
  curl() { printf 'curl %s\n' "$*" >> "${SING_BOX_TEST_COMMAND_LOG}"; }
  sha256sum() { local line; IFS= read -r line; printf 'sha256 %s\n' "${line}" >> "${SING_BOX_TEST_COMMAND_LOG}"; }
  tar() { printf 'tar %s\n' "$*" >> "${SING_BOX_TEST_COMMAND_LOG}"; }
  export -f curl sha256sum tar

  run bash "${TEST_ROOT_DIR}/scripts/install-test-sing-box.sh" '1.14.0'
  [ "${status}" -eq 0 ]
  grep -Fq '2375de6999f4f56ab46b4fc5ddf26a6aba1d3e61a0f4e7ddec2f4690457d5f63' "${SING_BOX_TEST_COMMAND_LOG}"
  grep -Fq 'sing-box-1.14.0-linux-amd64.tar.gz' "${SING_BOX_TEST_COMMAND_LOG}"

  run bash "${TEST_ROOT_DIR}/scripts/install-test-sing-box.sh"
  [ "${status}" -eq 0 ]
  grep -Fq 'a684484d7477d1437282ee411f4d131d0340aaad60a7868841ebd5d87dd8a0c6' "${SING_BOX_TEST_COMMAND_LOG}"
  grep -Fq 'sing-box-1.14.2-linux-amd64.tar.gz' "${SING_BOX_TEST_COMMAND_LOG}"
  grep -Fq -- '--connect-timeout 10 --max-time 180' "${SING_BOX_TEST_COMMAND_LOG}"
  grep -Fq 'sing-box-1.14.0' "${GITHUB_PATH}"
  grep -Fq 'sing-box-1.14.2' "${GITHUB_PATH}"
}

@test "sing-box test installer should reject unreviewed versions without downloading" {
  curl() { echo 'unexpected-download'; }
  export -f curl
  run bash "${TEST_ROOT_DIR}/scripts/install-test-sing-box.sh" '1.15.0-alpha.9'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Unreviewed sing-box test version'* ]]
  [[ "${output}" != *'unexpected-download'* ]]
}

@test "sing-box test installer should stop before extraction if checksum validation fails" {
  export RUNNER_TEMP="${TEST_TMP_DIR}"
  export GITHUB_PATH="${TEST_TMP_DIR}/github-path"
  curl() { :; }
  sha256sum() { return 1; }
  tar() { echo 'unexpected-extraction'; }
  export -f curl sha256sum tar
  run bash "${TEST_ROOT_DIR}/scripts/install-test-sing-box.sh"
  [ "${status}" -ne 0 ]
  [[ "${output}" != *'unexpected-extraction'* ]]
  [ ! -e "${TEST_TMP_DIR}/sing-box-1.14.2" ]
  [ ! -e "${GITHUB_PATH}" ]
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
