# shellcheck shell=bash
# 职责: Sing-box 完整配置模板组合

render_singbox_http_clients_section() {
    cat << 'EOF'
  "http_clients": [
    {
      "tag": "rule-set-proxy",
      "detour": "proxy"
    }
  ],
EOF
}

render_singbox_inbounds_section() {
    cat << 'EOF'
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "address": [
        "172.19.0.1/30"
      ],
      "auto_route": true,
      "strict_route": false
    }
  ],
EOF
}

render_singbox_experimental_section() {
    cat << 'EOF'
  "experimental": {
    "cache_file": {
      "enabled": true
    }
  }
EOF
}

render_singbox_full_template() {
    local json_ip="$1"
    local port="$2"
    local up_mbps="$3"
    local down_mbps="$4"
    local json_password="$5"
    local json_sni="$6"
    local insecure="$7"
    local public_key_sha="${8:-}"
    local public_key_field

    public_key_field="$(render_singbox_public_key_field "${insecure}" "${public_key_sha}" "        ")" || return 1

    # 校验证书固定材料后顺序输出；调用方必须检查返回码，不得发布失败的部分输出。
    printf '{\n' || return 1
    render_singbox_http_clients_section || return 1
    render_singbox_dns_section || return 1
    render_singbox_inbounds_section || return 1
    render_singbox_outbounds_section "${json_ip}" "${port}" "${up_mbps}" "${down_mbps}" "${json_password}" "${json_sni}" "${insecure}" "${public_key_field}" || return 1
    render_singbox_route_section || return 1
    render_singbox_experimental_section || return 1
    printf '}\n'
}
