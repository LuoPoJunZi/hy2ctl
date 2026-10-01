# shellcheck shell=bash
# 职责: Sing-box 完整模板展示入口

show_singbox_template() {
    if ! require_meta_info; then
        return
    fi

    local json_ip json_password json_sni cert_public_key_sha=""
    if [[ "${insecure}" == "true" ]]; then
        cert_public_key_sha="$(get_certificate_public_key_sha256 "${HY2_CONF_DIR}/server.crt" 2>/dev/null || true)"
        if [[ -z "${cert_public_key_sha}" ]]; then
            err "自签证书公钥指纹读取失败，无法安全生成 Sing-box 配置。"
            echo -e "  请通过主菜单 (1) 重新配置自签证书后再导出。"
            wait_return
            return 1
        fi
    fi
    json_ip="$(json_escape "${ip}")"
    json_password="$(json_escape "${password}")"
    json_sni="$(json_escape "${sni}")"

    clear
    print_line
    echo -e "     ${_green}--- Sing-box 完整模板 (Android/iOS / 1.14+) ---${_plain}"
    print_line
    echo -e "${_blue}[兼容]${_plain} 通过 v2rayN 使用 Sing-box 1.14 内核时，建议 v2rayN >= 7.25.4。"
    if ! render_singbox_full_template "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${cert_public_key_sha}"; then
        err "生成 Sing-box 完整模板失败，请重新配置节点。"
    fi
    print_line
    wait_return
}
