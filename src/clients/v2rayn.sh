# shellcheck shell=bash
# 职责: v2rayN 配置片段与兼容提醒

render_v2rayn_yaml_snippet() {
    local ip="$1"
    local port="$2"
    local password="$3"
    local up_mbps="$4"
    local down_mbps="$5"
    local sni="$6"
    local insecure="$7"
    local cert_sha="${8:-}"
    local yaml_server yaml_password yaml_sni

    yaml_server="$(yaml_single_quote "$(format_host_for_url "${ip}"):${port}")"
    yaml_password="$(yaml_single_quote "${password}")"
    yaml_sni="$(yaml_single_quote "${sni}")"

    cat << EOF
server: ${yaml_server}
auth: ${yaml_password}
bandwidth:
  up: ${up_mbps} mbps
  down: ${down_mbps} mbps
tls:
  sni: ${yaml_sni}
  insecure: ${insecure}
EOF
    if [[ -n "${cert_sha}" ]]; then
        printf '  pinSHA256: %s\n' "${cert_sha}"
    fi
    cat << EOF
socks5:
  listen: 127.0.0.1:1080
http:
  listen: 127.0.0.1:8080
EOF
}

print_client_security_notice() {
    print_line
    echo -e "${_yellow}[客户端安全提醒：CA / 自签均适用]${_plain}"
    echo -e "  v2rayN >= 7.24.9 修复旧版下载器中间人攻击风险；建议使用 7.25.6 或更新稳定版。"
    echo -e "  仅更新 v2rayN 不代表内核已修复，请在客户端核对实际 Xray-core 版本。"
    echo -e "  Xray-core 26.10.10 / 26.10.17 已因证书信任问题撤版。"
    echo -e "  请使用 26.10.21（上游预发布安全修复）或后续明确包含修复的版本。"
    echo -e "  公告：https://github.com/XTLS/Xray-core/releases/tag/v26.10.21"
    echo -e "  通过 v2rayN 管理 Sing-box 1.14 内核时，请使用 v2rayN >= 7.25.4。"
    echo -e "  客户端内核需在客户端更新；菜单 (11) 更新的是 VPS 面板与 Hysteria2 内核。"
}

print_v2rayn_insecure_notice() {
    print_line
    echo -e "${_yellow}[v2rayN / Xray 自签证书提醒]${_plain}"
    echo -e "  原生 Hysteria2 使用 insecure=1 与 pinSHA256 验证自签证书。"
    echo -e "  v2rayN / Xray 使用 pcs 映射 pinnedPeerCertSha256。"
    echo -e "  自签功能兼容最低要求：v2rayN >= 7.17.1，Xray-core >= 26.2.6（不是当前安全建议）。"
    echo -e "  Sing-box 自签配置使用公钥固定，请使用 Sing-box >= 1.13.0。"
    echo -e "  分享链接已移除 allowInsecure，不再依赖已废弃的跳过验证字段。"
    echo -e "  重新生成自签证书后指纹会变化，客户端必须重新导入节点。"
}
