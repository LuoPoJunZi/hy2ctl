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

print_v2rayn_insecure_notice() {
    print_line
    echo -e "${_yellow}[v2rayN / Xray 自签证书提醒]${_plain}"
    echo -e "  原生 Hysteria2 使用 insecure=1 与 pinSHA256 验证自签证书。"
    echo -e "  v2rayN / Xray 使用 pcs 映射 pinnedPeerCertSha256。"
    echo -e "  使用 Xray 时请确保：v2rayN >= 7.17.1，Xray-core >= 26.2.6。"
    echo -e "  请使用 v2rayN >= 7.24.9，以修复旧版下载器的中间人攻击风险。"
    echo -e "  Sing-box 自签配置使用公钥固定，请使用 Sing-box >= 1.13.0。"
    echo -e "  通过 v2rayN 管理 Sing-box 1.14 内核时，请使用 v2rayN >= 7.25.4。"
    echo -e "  分享链接已移除 allowInsecure，不再依赖已废弃的跳过验证字段。"
    echo -e "  重新生成自签证书后指纹会变化，客户端必须重新导入节点。"
}
