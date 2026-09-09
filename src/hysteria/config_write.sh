# shellcheck shell=bash
# 职责: Hysteria2 服务端配置文件写入

write_ca_config() {
    local port="$1"
    local domain="$2"
    local email="$3"
    local password="$4"
    local masquerade_url="$5"

    write_file_atomic "${HY2_CONF_FILE}" << EOF
listen: :${port}
acme:
  domains:
    - $(yaml_single_quote "${domain}")
  email: $(yaml_single_quote "${email}")
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}

write_self_signed_config() {
    local port="$1"
    local password="$2"
    local masquerade_url="$3"

    write_file_atomic "${HY2_CONF_FILE}" << EOF
listen: :${port}
tls:
  cert: ${HY2_CONF_DIR}/server.crt
  key: ${HY2_CONF_DIR}/server.key
auth:
  type: password
  password: $(yaml_single_quote "${password}")
masquerade:
  type: proxy
  proxy:
    url: $(yaml_single_quote "${masquerade_url}")
    rewriteHost: true
EOF
}
