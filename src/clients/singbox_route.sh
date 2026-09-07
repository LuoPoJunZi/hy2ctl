# shellcheck shell=bash
# 职责: Sing-box 路由规则与远程规则集分段

render_singbox_route_section() {
    cat << 'EOF'
  "route": {
    "default_domain_resolver": "cf",
    "default_http_client": "rule-set-proxy",
    "rules": [
      {
        "action": "sniff"
      },
      {
        "protocol": "dns",
        "action": "hijack-dns"
      },
      {
        "ip_is_private": true,
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": [
          "geosite-cn",
          "geoip-cn"
        ],
        "action": "route",
        "outbound": "direct"
      },
      {
        "rule_set": "geosite-category-ads-all",
        "action": "reject"
      }
    ],
    "rule_set": [
      {
        "type": "remote",
        "tag": "geosite-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geoip-cn",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"
      },
      {
        "type": "remote",
        "tag": "geosite-category-ads-all",
        "format": "binary",
        "url": "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-category-ads-all.srs"
      }
    ],
    "final": "proxy",
    "auto_detect_interface": true
  },
EOF
}
