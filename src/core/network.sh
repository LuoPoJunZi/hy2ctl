# shellcheck shell=bash
# 职责: 有界脚本下载与服务器公网地址发现

# target 由调用方通过 mktemp 创建；失败后的删除、校验与替换仍由调用方负责。
download_script() {
    curl -fL --retry 2 --connect-timeout 8 --max-time 120 \
        -o "$2" "$1" >/dev/null 2>&1
}

fetch_server_ip() {
    local ip
    ip="$(curl -fsS4 --max-time 6 https://api.ipify.org 2>/dev/null || true)"
    if [[ -z "${ip}" ]]; then
        ip="$(curl -fsS6 --max-time 6 https://api64.ipify.org 2>/dev/null || true)"
    fi
    if [[ -z "${ip}" ]]; then
        ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    fi
    echo "${ip}"
}
