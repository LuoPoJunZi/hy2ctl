#!/usr/bin/env bats

# shellcheck source=../helpers/bats-setup.sh
source "${BATS_TEST_DIRNAME}/../helpers/bats-setup.sh"

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
